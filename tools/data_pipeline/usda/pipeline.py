"""Main orchestrator pipeline for USDA FoodData Central dataset processing."""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any

from .config import (
    APP_ASSETS_DIR,
    DEFAULT_MANIFEST_PATH,
    DEFAULT_OUTPUT_DB,
    DEFAULT_VALIDATION_REPORT,
    MIN_VALID_PRODUCTS,
    REFERENCE_DB_PATH,
    USDA_CATEGORIES,
)
from .db_builder import merge_into_reference_db, populate_database
from .fetcher import extract_and_load_foods
from .translator import (
    TranslationEngine,
    generate_synonyms,
    normalize_for_search,
)
from .validator import DatasetValidator

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("usda_pipeline")


def run_usda_pipeline(
    source_path: str | Path | None = None,
    output_db_path: str | Path | None = None,
    manifest_path: str | Path | None = None,
    report_path: str | Path | None = None,
    limit: int | None = None,
    save_cache: bool = True,
    merge_reference: bool = True,
) -> dict[str, Any]:
    """Execute the end-to-end USDA data extraction, validation, translation, and DB build pipeline."""
    start_time = time.time()
    logger.info("=" * 60)
    logger.info("Starting USDA FoodData Central Processing Pipeline (SR Legacy / Foundation)")
    logger.info("=" * 60)

    # 1. Resolve source dataset & load raw foods
    foods_raw, meta = extract_and_load_foods(source_path)

    if limit is not None and limit > 0:
        logger.info("Applying limit: %d items", limit)
        foods_raw = foods_raw[:limit]

    # 2. Extract and prepare food categories
    category_id_map: dict[str, dict[str, Any]] = {}
    categories_list: list[dict[str, Any]] = []

    for f in foods_raw:
        cid = str(f.get("category_id", "18"))
        cname_en = f.get("category_name_en", "General")
        cname_ru = f.get("category_name_ru", cname_en)
        if cid not in category_id_map:
            cat_obj = {
                "id": int(cid) if cid.isdigit() else 100 + len(category_id_map) + 1,
                "code": f"USDA_{cid}",
                "name_en": cname_en,
                "name_ru": cname_ru,
            }
            category_id_map[cid] = cat_obj
            categories_list.append(cat_obj)

    # 3. Initialize translation engine and validator
    trans_engine = TranslationEngine()
    validator = DatasetValidator()

    # 4. Validate, translate, and format each product
    logger.info("Validating and translating food items...")
    prepared_products: list[dict[str, Any]] = []

    for i, food in enumerate(foods_raw):
        if (i + 1) % 1000 == 0 or (i + 1) == len(foods_raw):
            logger.info("Processed %d / %d foods...", i + 1, len(foods_raw))

        val_res = validator.validate(food)
        if not val_res.is_valid:
            continue

        fid = int(food["fdc_id"])
        desc_en = str(food.get("description") or "").strip()
        cid = str(food.get("category_id", "18"))
        cat_info = category_id_map.get(cid, USDA_CATEGORIES.get("18", {"id": 118, "name_ru": "Выпечка"}))

        cat_ru = cat_info["name_ru"]
        cat_id = cat_info["id"]

        # Translate product name
        name_ru = trans_engine.translate_food_description(desc_en, cat_info["name_en"])
        name_norm = normalize_for_search(name_ru)

        # Generate synonyms
        synonyms = generate_synonyms(name_ru, desc_en, cat_ru)
        synonyms_norm = {syn: normalize_for_search(syn) for syn in synonyms}

        # Measures
        measures: list[dict[str, Any]] = []
        for m in food.get("measures", []):
            mod_en = str(m.get("modifier") or m.get("amount") or "portion").strip()
            grams = float(m["grams"])
            amt = str(m.get("amount") or "1")
            mod_ru = trans_engine.translate_measure_description(mod_en)
            label_ru = f"{amt} {mod_ru}".strip() if amt and amt != "1" else mod_ru
            measures.append({
                "name_en": f"{amt} {mod_en}".strip(),
                "name_ru": label_ru,
                "grams": grams,
            })

        prepared_products.append({
            "id": fid,
            "code": f"USDA_{fid}",
            "name_ru": name_ru,
            "name_en": desc_en,
            "name_norm": name_norm,
            "group_id": cat_id,
            "source": "usda",
            "waste_pct": 0.0,
            "macros": val_res.macros,
            "all_nutrients": val_res.all_nutrients,
            "measures": measures,
            "synonyms": synonyms,
            "synonyms_norm": synonyms_norm,
        })

    if save_cache:
        trans_engine.save_cache()

    validation_summary = validator.summary()
    logger.info("Validation Summary: %s", validation_summary)

    if limit is None and validation_summary["passed"] < MIN_VALID_PRODUCTS:
        raise RuntimeError(
            f"Validation passed count {validation_summary['passed']} is below minimum threshold {MIN_VALID_PRODUCTS}"
        )

    # 5. Populate standalone SQLite database (usda_products.db)
    final_db_path = Path(output_db_path).resolve() if output_db_path else DEFAULT_OUTPUT_DB
    db_stats = populate_database(final_db_path, categories_list, prepared_products)

    # 6. Optionally merge into unified reference.db
    ref_stats: dict[str, int] | None = None
    if merge_reference:
        try:
            ref_stats = merge_into_reference_db(REFERENCE_DB_PATH, categories_list, prepared_products)
        except Exception as e:
            logger.warning("Could not merge into reference.db: %s", e)

    # 7. Write manifest and validation report
    final_manifest_path = Path(manifest_path).resolve() if manifest_path else DEFAULT_MANIFEST_PATH
    final_report_path = Path(report_path).resolve() if report_path else DEFAULT_VALIDATION_REPORT

    final_manifest_path.parent.mkdir(parents=True, exist_ok=True)
    final_report_path.parent.mkdir(parents=True, exist_ok=True)

    elapsed_sec = round(time.time() - start_time, 2)

    manifest_payload = {
        "catalogName": "USDA FoodData Central Offline Catalog (SR Legacy / Foundation)",
        "version": "1.0.0",
        "generatedAt": time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime()),
        "sourceDataset": meta,
        "databasePath": str(final_db_path),
        "databaseSizeMB": round(final_db_path.stat().st_size / (1024 * 1024), 2),
        "statistics": db_stats,
        "referenceDatabase": str(REFERENCE_DB_PATH) if merge_reference else None,
        "referenceStatistics": ref_stats,
        "elapsedSeconds": elapsed_sec,
    }

    with final_manifest_path.open("w", encoding="utf-8") as f:
        json.dump(manifest_payload, f, ensure_ascii=False, indent=2)

    with final_report_path.open("w", encoding="utf-8") as f:
        json.dump(validation_summary, f, ensure_ascii=False, indent=2)

    logger.info("Manifest written to: %s", final_manifest_path)
    logger.info("Validation report written to: %s", final_report_path)

    # 8. Deploy to app assets
    if APP_ASSETS_DIR.is_dir():
        if merge_reference and REFERENCE_DB_PATH.is_file():
            app_target_ref = APP_ASSETS_DIR / "reference.db"
            shutil.copy2(REFERENCE_DB_PATH, app_target_ref)
            logger.info("Copied unified reference database to app assets: %s", app_target_ref)

    # 9. Run Verification queries on the newly built database
    logger.info("Verifying search queries on database: %s", final_db_path)
    verify_database(final_db_path)

    logger.info("=" * 60)
    logger.info("USDA Pipeline successfully completed in %.2fs!", elapsed_sec)
    logger.info("=" * 60)

    return {
        "manifest": manifest_payload,
        "validation": validation_summary,
        "database": str(final_db_path),
    }


def verify_database(db_path: Path) -> None:
    """Run verification search queries against the generated database."""
    conn = sqlite3.connect(str(db_path))
    cur = conn.cursor()

    test_queries = [
        ("картоф*", "Поиск по корню 'картоф*'"),
        ("куриц*", "Поиск по 'куриц*'"),
        ("говяд*", "Поиск по 'говяд*'"),
        ("молок*", "Поиск по 'молок*'"),
        ("яблок*", "Поиск по 'яблок*'"),
        ("картошка*", "Поиск по русскому синониму 'картошка*'"),
        ("томат*", "Поиск по синониму 'томат*'"),
        ("пахта*", "Поиск по 'пахта*'"),
        ("chicken*", "Поиск по оригинальному англ. 'chicken*'"),
        ("milk*", "Поиск по оригинальному англ. 'milk*'"),
        ("beef*", "Поиск по оригинальному англ. 'beef*'"),
        ("salmon*", "Поиск по англ. 'salmon*'"),
    ]

    for q, label in test_queries:
        cur.execute(
            """
            SELECT p.id, p.name, p.kcal, p.protein, p.fat, p.carbs
            FROM product_fts f
            JOIN product p ON f.product_id = p.id
            WHERE product_fts MATCH ?
            ORDER BY rank
            LIMIT 3
            """,
            (q,),
        )
        rows = cur.fetchall()
        logger.info("Search '%s' (%s): %d hits", q, label, len(rows))
        for r in rows:
            logger.info("   -> [%d] %s (Б: %.1f, Ж: %.1f, У: %.1f, %.0f ккал)", r[0], r[1], r[3], r[4], r[5], r[2])

    conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="USDA FoodData Central Pipeline")
    parser.add_argument("--source", type=str, help="Path to USDA dataset directory or archive")
    parser.add_argument("--output", type=str, help="Output SQLite database path")
    parser.add_argument("--manifest", type=str, help="Output manifest JSON path")
    parser.add_argument("--report", type=str, help="Output validation report JSON path")
    parser.add_argument("--limit", type=int, help="Limit number of items to process")
    parser.add_argument("--no-cache", action="store_true", help="Disable saving translation cache")
    parser.add_argument("--no-merge", action="store_true", help="Do not merge into reference.db")
    args = parser.parse_args()

    run_usda_pipeline(
        source_path=args.source,
        output_db_path=args.output,
        manifest_path=args.manifest,
        report_path=args.report,
        limit=args.limit,
        save_cache=not args.no_cache,
        merge_reference=not args.no_merge,
    )


if __name__ == "__main__":
    main()
