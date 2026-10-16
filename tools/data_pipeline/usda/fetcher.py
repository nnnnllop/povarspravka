"""Dataset fetcher and loader for USDA FoodData Central (SR Legacy, Foundation, and Survey Foods)."""

from __future__ import annotations

import csv
import hashlib
import json
import logging
import shutil
import zipfile
from pathlib import Path
from typing import Any

from .config import (
    DEFAULT_SURVEY_ZIP,
    FOUNDATION_DIR,
    FOUNDATION_ZIP,
    NUTRIENT_CODE_MAP,
    NUTRIENT_IDS,
    SR_LEGACY_DIR,
    SR_LEGACY_ZIP,
    USDA_CACHE_DIR,
    USDA_CATEGORIES,
)

logger = logging.getLogger(__name__)

FALLBACK_LOCATIONS = [
    Path(r"C:\projects\opencalori\OpenCalori\tools\catalog\source") / DEFAULT_SURVEY_ZIP.name,
    Path(r"C:\projects\opencalori\OpenCalori-v040-review\tools\catalog\source") / DEFAULT_SURVEY_ZIP.name,
]


def compute_file_sha256(path: Path) -> str:
    """Compute sha256 checksum of a file in 1MB chunks."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_datasets_extracted() -> tuple[Path, Path | None]:
    """Ensure SR Legacy and Foundation Foods CSV directories exist and are extracted."""
    # 1. SR Legacy
    if not SR_LEGACY_DIR.is_dir():
        if SR_LEGACY_ZIP.is_file():
            extract_target = USDA_CACHE_DIR / "sr_legacy"
            extract_target.mkdir(parents=True, exist_ok=True)
            logger.info("Extracting %s to %s...", SR_LEGACY_ZIP, extract_target)
            with zipfile.ZipFile(SR_LEGACY_ZIP, "r") as zf:
                zf.extractall(extract_target)
        else:
            raise FileNotFoundError(
                f"SR Legacy dataset not found at '{SR_LEGACY_DIR}' or '{SR_LEGACY_ZIP}'."
            )

    # 2. Foundation Foods
    foundation_dir: Path | None = None
    if FOUNDATION_DIR.is_dir():
        foundation_dir = FOUNDATION_DIR
    elif FOUNDATION_ZIP.is_file():
        extract_target = USDA_CACHE_DIR / "foundation"
        extract_target.mkdir(parents=True, exist_ok=True)
        logger.info("Extracting %s to %s...", FOUNDATION_ZIP, extract_target)
        with zipfile.ZipFile(FOUNDATION_ZIP, "r") as zf:
            zf.extractall(extract_target)
        if FOUNDATION_DIR.is_dir():
            foundation_dir = FOUNDATION_DIR

    return SR_LEGACY_DIR, foundation_dir


def load_sr_legacy_and_foundation(
    sr_dir: Path, foundation_dir: Path | None = None
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Load, merge, and structure SR Legacy and Foundation foods from CSV files."""
    logger.info("Loading USDA SR Legacy foods from %s...", sr_dir)

    # Category map
    cat_map: dict[str, dict[str, Any]] = {}
    cat_path = sr_dir / "food_category.csv"
    if cat_path.is_file():
        with cat_path.open("r", encoding="utf-8", errors="replace") as f:
            for row in csv.DictReader(f):
                cid = row["id"]
                cat_info = USDA_CATEGORIES.get(
                    cid,
                    {"id": 100 + int(cid), "code": f"USDA_{row.get('code', cid)}", "name_en": row["description"], "name_ru": row["description"]}
                )
                cat_map[cid] = cat_info

    foods_dict: dict[int, dict[str, Any]] = {}

    # 1. Load SR Legacy foods (7,793 items)
    food_csv = sr_dir / "food.csv"
    with food_csv.open("r", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            fdc_id = int(row["fdc_id"])
            cid = row.get("food_category_id", "")
            cat = cat_map.get(cid, USDA_CATEGORIES["18"])  # Default to Baked or general
            foods_dict[fdc_id] = {
                "fdc_id": fdc_id,
                "description": row["description"].strip(),
                "category_id": cat["id"],
                "category_name_en": cat["name_en"],
                "category_name_ru": cat["name_ru"],
                "source": "usda",
                "protein": 0.0,
                "fat": 0.0,
                "carbs": 0.0,
                "kcal": 0.0,
                "has_explicit_kcal": False,
                "water": 0.0,
                "fiber": 0.0,
                "ash": 0.0,
                "sugars": 0.0,
                "starch": 0.0,
                "sfa": 0.0,
                "pufa": 0.0,
                "mufa": 0.0,
                "chol": 0.0,
                "alcohol": 0.0,
                "all_nutrients": {},
                "measures": [],
            }

    sr_count = len(foods_dict)
    logger.info("Loaded %d SR Legacy items", sr_count)

    # 2. Load Foundation foods (387 items)
    ff_count = 0
    if foundation_dir and (foundation_dir / "food.csv").is_file():
        logger.info("Loading USDA Foundation foods from %s...", foundation_dir)
        with (foundation_dir / "food.csv").open("r", encoding="utf-8", errors="replace") as f:
            for row in csv.DictReader(f):
                if row.get("data_type") == "foundation_food":
                    fdc_id = int(row["fdc_id"])
                    cid = row.get("food_category_id", "")
                    cat = cat_map.get(cid, USDA_CATEGORIES.get(cid, {"id": 111, "name_en": "Foundation Foods", "name_ru": "Базовые продукты"}))
                    foods_dict[fdc_id] = {
                        "fdc_id": fdc_id,
                        "description": row["description"].strip(),
                        "category_id": cat["id"],
                        "category_name_en": cat["name_en"],
                        "category_name_ru": cat["name_ru"],
                        "source": "usda",
                        "protein": 0.0,
                        "fat": 0.0,
                        "carbs": 0.0,
                        "kcal": 0.0,
                        "has_explicit_kcal": False,
                        "water": 0.0,
                        "fiber": 0.0,
                        "ash": 0.0,
                        "sugars": 0.0,
                        "starch": 0.0,
                        "sfa": 0.0,
                        "pufa": 0.0,
                        "mufa": 0.0,
                        "chol": 0.0,
                        "alcohol": 0.0,
                        "all_nutrients": {},
                        "measures": [],
                    }
                    ff_count += 1
        logger.info("Loaded %d Foundation items. Total unique foods: %d", ff_count, len(foods_dict))

    # 3. Load portions / household measures for SR Legacy
    portion_csv = sr_dir / "food_portion.csv"
    if portion_csv.is_file():
        logger.info("Loading portions from %s...", portion_csv)
        with portion_csv.open("r", encoding="utf-8", errors="replace") as f:
            for row in csv.DictReader(f):
                fdc_id = int(row["fdc_id"])
                if fdc_id in foods_dict:
                    gw = row.get("gram_weight")
                    mod = row.get("modifier") or row.get("portion_description") or ""
                    amt = row.get("amount") or "1"
                    if gw:
                        try:
                            gw_float = float(gw)
                            if gw_float > 0.0:
                                foods_dict[fdc_id]["measures"].append({
                                    "amount": amt,
                                    "modifier": mod.strip(),
                                    "grams": gw_float,
                                })
                        except (ValueError, TypeError):
                            pass

    # 4. Load portions for Foundation foods
    if foundation_dir and (foundation_dir / "food_portion.csv").is_file():
        with (foundation_dir / "food_portion.csv").open("r", encoding="utf-8", errors="replace") as f:
            for row in csv.DictReader(f):
                fdc_id = int(row["fdc_id"])
                if fdc_id in foods_dict:
                    gw = row.get("gram_weight")
                    mod = row.get("modifier") or row.get("portion_description") or ""
                    amt = row.get("amount") or "1"
                    if gw:
                        try:
                            gw_float = float(gw)
                            if gw_float > 0.0:
                                foods_dict[fdc_id]["measures"].append({
                                    "amount": amt,
                                    "modifier": mod.strip(),
                                    "grams": gw_float,
                                })
                        except (ValueError, TypeError):
                            pass

    # 5. Load nutrients from SR Legacy
    nut_csv = sr_dir / "food_nutrient.csv"
    logger.info("Loading nutrients from %s...", nut_csv)
    with nut_csv.open("r", encoding="utf-8", errors="replace") as f:
        for row in csv.DictReader(f):
            fdc_id = int(row["fdc_id"])
            if fdc_id in foods_dict:
                nid = row["nutrient_id"]
                val_str = row.get("amount")
                if not val_str:
                    continue
                try:
                    val = max(0.0, float(val_str))
                except (ValueError, TypeError):
                    continue

                food = foods_dict[fdc_id]
                # Map core macros
                if nid == "1003":  # Protein
                    food["protein"] = val
                elif nid == "1004":  # Fat
                    food["fat"] = val
                elif nid == "1005":  # Carbs
                    food["carbs"] = val
                elif nid == "1008":  # Energy
                    food["kcal"] = val
                    food["has_explicit_kcal"] = True
                elif nid == "1051":  # Water
                    food["water"] = val
                elif nid == "1079":  # Fiber
                    food["fiber"] = val
                elif nid in ("2000", "1063"):  # Sugars
                    food["sugars"] = val
                elif nid == "1009":  # Starch
                    food["starch"] = val
                elif nid == "1258":  # SFA
                    food["sfa"] = val
                elif nid == "1257":  # PUFA
                    food["pufa"] = val
                elif nid == "1292":  # MUFA
                    food["mufa"] = val
                elif nid == "1253":  # Cholesterol
                    food["chol"] = val
                elif nid == "1018":  # Alcohol
                    food["alcohol"] = val

                # Save all mapped nutrients into all_nutrients dictionary
                if nid in NUTRIENT_CODE_MAP:
                    code = NUTRIENT_CODE_MAP[nid]
                    food["all_nutrients"][code] = val

    # 6. Load nutrients for Foundation foods
    if foundation_dir and (foundation_dir / "food_nutrient.csv").is_file():
        logger.info("Loading Foundation nutrients...")
        with (foundation_dir / "food_nutrient.csv").open("r", encoding="utf-8", errors="replace") as f:
            for row in csv.DictReader(f):
                fdc_id = int(row["fdc_id"])
                if fdc_id in foods_dict:
                    nid = row["nutrient_id"]
                    val_str = row.get("amount")
                    if not val_str:
                        continue
                    try:
                        val = max(0.0, float(val_str))
                    except (ValueError, TypeError):
                        continue

                    food = foods_dict[fdc_id]
                    if nid == "1003":
                        food["protein"] = val
                    elif nid == "1004":
                        food["fat"] = val
                    elif nid == "1005":
                        food["carbs"] = val
                    elif nid == "1008":
                        food["kcal"] = val
                        food["has_explicit_kcal"] = True
                    elif nid == "1051":
                        food["water"] = val
                    elif nid == "1079":
                        food["fiber"] = val
                    elif nid in ("2000", "1063"):
                        food["sugars"] = val
                    elif nid == "1009":
                        food["starch"] = val
                    elif nid == "1258":
                        food["sfa"] = val
                    elif nid == "1257":
                        food["pufa"] = val
                    elif nid == "1292":
                        food["mufa"] = val
                    elif nid == "1253":
                        food["chol"] = val
                    elif nid == "1018":
                        food["alcohol"] = val

                    if nid in NUTRIENT_CODE_MAP:
                        code = NUTRIENT_CODE_MAP[nid]
                        food["all_nutrients"][code] = val

    # 7. Energy imputation if not explicitly present
    computed_kcal_count = 0
    for food in foods_dict.values():
        if not food["has_explicit_kcal"]:
            calc_kcal = round(
                (4.0 * food["protein"])
                + (9.0 * food["fat"])
                + (4.0 * food["carbs"])
                + (7.0 * food["alcohol"]),
                1,
            )
            food["kcal"] = calc_kcal
            food["all_nutrients"]["ENERC_KCAL"] = calc_kcal
            computed_kcal_count += 1

    metadata = {
        "dataset_type": "USDA FoodData Central (SR Legacy + Foundation Foods)",
        "sr_count": sr_count,
        "foundation_count": ff_count,
        "total_count": len(foods_dict),
        "computed_kcal_count": computed_kcal_count,
        "sr_dir": str(sr_dir),
    }

    logger.info(
        "Extracted %d foods total (SR Legacy: %d, Foundation: %d, Atwater kcal computed: %d)",
        len(foods_dict),
        sr_count,
        ff_count,
        computed_kcal_count,
    )
    return list(foods_dict.values()), metadata


def load_survey_foods_json(json_or_zip_path: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Fallback loader for Survey Foods (FNDDS) JSON or zip archive."""
    logger.info("Loading Survey Foods dataset from %s...", json_or_zip_path)
    if zipfile.is_zipfile(json_or_zip_path):
        with zipfile.ZipFile(json_or_zip_path) as archive:
            json_candidates = [n for n in archive.namelist() if n.endswith(".json")]
            target = "surveyDownload.json" if "surveyDownload.json" in json_candidates else json_candidates[0]
            with archive.open(target) as f:
                payload = json.load(f)
    else:
        with json_or_zip_path.open("r", encoding="utf-8") as f:
            payload = json.load(f)

    raw_foods = payload.get("SurveyFoods") or (payload if isinstance(payload, list) else [])
    foods: list[dict[str, Any]] = []

    for f in raw_foods:
        fdc_id = int(f.get("fdcId", 0))
        desc = str(f.get("description", "")).strip()

        # Find WWEIA category
        cat_desc = "Not included in a food category"
        for attr in f.get("foodAttributes", []):
            if attr.get("name") == "WWEIA Category description":
                cat_desc = str(attr.get("value") or "").strip()
                break

        food_item: dict[str, Any] = {
            "fdc_id": fdc_id,
            "description": desc,
            "category_id": 122,  # Meals/entrees
            "category_name_en": cat_desc,
            "category_name_ru": cat_desc,
            "source": "usda",
            "protein": 0.0,
            "fat": 0.0,
            "carbs": 0.0,
            "kcal": 0.0,
            "has_explicit_kcal": False,
            "water": 0.0,
            "fiber": 0.0,
            "ash": 0.0,
            "sugars": 0.0,
            "starch": 0.0,
            "sfa": 0.0,
            "pufa": 0.0,
            "mufa": 0.0,
            "chol": 0.0,
            "alcohol": 0.0,
            "all_nutrients": {},
            "measures": [],
        }

        for item in f.get("foodNutrients", []):
            nut = item.get("nutrient") or {}
            num = str(nut.get("number") or item.get("nutrientNumber") or "")
            amt = item.get("amount")
            if amt is None:
                continue
            try:
                v = max(0.0, float(amt))
            except (ValueError, TypeError):
                continue

            if num == "203":
                food_item["protein"] = v
            elif num == "204":
                food_item["fat"] = v
            elif num == "205":
                food_item["carbs"] = v
            elif num == "208":
                food_item["kcal"] = v
                food_item["has_explicit_kcal"] = True
            elif num == "255":
                food_item["water"] = v
            elif num == "291":
                food_item["fiber"] = v

            if num in NUTRIENT_CODE_MAP:
                food_item["all_nutrients"][NUTRIENT_CODE_MAP[num]] = v

        for p in f.get("foodPortions", []):
            pdesc = str(p.get("portionDescription") or "").strip()
            gw = p.get("gramWeight")
            if pdesc and gw is not None:
                try:
                    gw_f = float(gw)
                    if gw_f > 0:
                        food_item["measures"].append({
                            "amount": "1",
                            "modifier": pdesc,
                            "grams": gw_f,
                        })
                except (ValueError, TypeError):
                    pass

        foods.append(food_item)

    metadata = {
        "dataset_type": "USDA FoodData Central (SurveyFoods / FNDDS)",
        "total_count": len(foods),
        "source_file": json_or_zip_path.name,
    }
    return foods, metadata


def extract_and_load_foods(source_path: str | Path | None = None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Primary entry point to resolve and load USDA foods dataset."""
    if source_path:
        p = Path(source_path).resolve()
        if not p.exists():
            raise FileNotFoundError(f"Specified USDA source path does not exist: {p}")
        if p.is_dir() and (p / "food.csv").is_file():
            return load_sr_legacy_and_foundation(p)
        if p.is_file():
            if p.suffix.lower() == ".zip" and "sr_legacy" in p.name.lower():
                sr_dir, f_dir = ensure_datasets_extracted()
                return load_sr_legacy_and_foundation(sr_dir, f_dir)
            return load_survey_foods_json(p)

    # Default: Load SR Legacy + Foundation Foods
    try:
        sr_dir, foundation_dir = ensure_datasets_extracted()
        return load_sr_legacy_and_foundation(sr_dir, foundation_dir)
    except Exception as e:
        logger.warning("Could not load SR Legacy from default cache: %s. Checking survey fallback...", e)
        if DEFAULT_SURVEY_ZIP.is_file():
            return load_survey_foods_json(DEFAULT_SURVEY_ZIP)
        for fb in FALLBACK_LOCATIONS:
            if fb.is_file():
                return load_survey_foods_json(fb)
        raise
