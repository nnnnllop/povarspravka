"""Rebuild the Skurikhin part of the unified reference.db from the PDF pipeline.

The unified catalogue = 1103 Skurikhin rows (ids 1..1103) + USDA rows keyed by
fdc_id.  Re-running ``pipeline_runner`` would drop the USDA half, so this tool
regenerates only the Skurikhin slice, keeps every USDA row byte-identical and
rebuilds FTS for the replaced rows.

Run from the project root::

    python -m tools.data_pipeline.rebuild_skurikhin --apply

Without ``--apply`` it only reports the rows that would change.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

import pymupdf

from .skurikhin.config import DEFAULT_PDF_PATH
from .skurikhin.database_builder import build_sqlite_database, normalize_text
from .skurikhin.table_extractor import extract_all_products

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "tools" / "data_pipeline" / "output" / "reference.db"
ASSET_DB = ROOT / "app" / "assets" / "db" / "reference.db"

COMPARE_COLUMNS = [
    "id", "code", "name", "waste_pct", "protein", "fat", "carbs", "kcal",
    "water", "fiber", "ash", "organic_acids", "sugars", "starch", "sfa",
    "pufa", "chol", "alcohol", "page_num",
]


def _rows(db: Path, source: str) -> dict[int, tuple]:
    select = "SELECT %s FROM product WHERE source=? ORDER BY id" % ",".join(COMPARE_COLUMNS)
    con = sqlite3.connect(db)
    try:
        return {r[0]: r for r in con.execute(select, (source,))}
    finally:
        con.close()


def build_skurikhin_scratch(target: Path) -> None:
    doc = pymupdf.open(str(DEFAULT_PDF_PATH))
    products = extract_all_products(doc)
    if len(products) != 1103:
        raise SystemExit(f"Unexpected Skurikhin product count: {len(products)}")
    build_sqlite_database(products, target)


def diff(current: dict[int, tuple], fresh: dict[int, tuple]) -> list[str]:
    report = []
    for pid in sorted(set(current) | set(fresh)):
        if pid not in current:
            report.append(f"+ new id {pid} {fresh[pid][1]} {fresh[pid][2]}")
        elif pid not in fresh:
            report.append(f"- missing id {pid} {current[pid][1]} {current[pid][2]}")
        elif current[pid] != fresh[pid]:
            changed = {
                COMPARE_COLUMNS[i]: (current[pid][i], fresh[pid][i])
                for i in range(len(COMPARE_COLUMNS))
                if current[pid][i] != fresh[pid][i]
            }
            report.append(f"~ {pid} {fresh[pid][1]} {fresh[pid][2][:45]} {changed}")
    return report


def apply_merge(fresh_db: Path) -> None:
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = ROOT / "audit_artifacts" / f"db_backup_{stamp}"
    backup_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(DB, backup_dir / "reference.db")
    shutil.copy2(ASSET_DB, backup_dir / "asset_reference.db")

    con = sqlite3.connect(DB)
    try:
        usda_before = con.execute(
            "SELECT id,name,protein,fat,carbs,kcal,waste_pct,page_num FROM product "
            "WHERE source='usda' ORDER BY id").fetchall()
        usda_measures_before = con.execute(
            "SELECT m.* FROM measure m JOIN product p ON p.id=m.product_id "
            "WHERE p.source='usda' ORDER BY m.id").fetchall()
    finally:
        con.close()

    # Stage the merge next to the DB so a crash cannot leave a half-written file.
    staged = DB.with_suffix(".rebuild.tmp")
    if staged.exists():
        staged.unlink()
    shutil.copy2(DB, staged)

    con = sqlite3.connect(staged)
    fresh = sqlite3.connect(fresh_db)
    try:
        con.execute("PRAGMA foreign_keys=OFF")
        ids = [r[0] for r in con.execute(
            "SELECT id FROM product WHERE source='skurikhin'")]
        placeholders = ",".join("?" * len(ids))
        con.execute(f"DELETE FROM measure WHERE product_id IN ({placeholders})", ids)
        con.execute(f"DELETE FROM nutrient_value WHERE product_id IN ({placeholders})", ids)
        con.execute(f"DELETE FROM synonym WHERE product_id IN ({placeholders})", ids)
        con.execute(f"DELETE FROM product_fts WHERE rowid IN ({placeholders})", ids)
        con.execute(f"DELETE FROM product WHERE id IN ({placeholders})", ids)

        con.executemany(
            "INSERT INTO product (id,code,name,name_norm,group_id,source,page_num,"
            "waste_pct,protein,fat,carbs,kcal,water,fiber,ash,organic_acids,sugars,"
            "starch,sfa,pufa,chol,alcohol) VALUES (%s)" % ",".join("?" * 22),
            fresh.execute(
                "SELECT id,code,name,name_norm,group_id,source,page_num,waste_pct,"
                "protein,fat,carbs,kcal,water,fiber,ash,organic_acids,sugars,starch,"
                "sfa,pufa,chol,alcohol FROM product ORDER BY id").fetchall())
        con.executemany(
            "INSERT INTO measure (product_id,name,grams) VALUES (?,?,?)",
            fresh.execute("SELECT product_id,name,grams FROM measure ORDER BY id").fetchall())
        con.executemany(
            "INSERT INTO nutrient_value (product_id,nutrient_code,value) VALUES (?,?,?)",
            fresh.execute(
                "SELECT product_id,nutrient_code,value FROM nutrient_value ORDER BY id").fetchall())
        con.executemany(
            "INSERT INTO synonym (product_id,synonym,synonym_norm) VALUES (?,?,?)",
            fresh.execute("SELECT product_id,synonym,synonym_norm FROM synonym ORDER BY id").fetchall())
        con.executemany(
            "INSERT INTO product_fts (rowid,product_id,name,name_norm) VALUES (?,?,?,?)",
            fresh.execute("SELECT rowid,product_id,name,name_norm FROM product_fts ORDER BY rowid").fetchall())

        # Same FTS contract as repair_audit: name + all synonyms.
        con.execute("DELETE FROM product_fts")
        con.execute("""INSERT INTO product_fts(rowid,product_id,name,name_norm)
            SELECT p.id,p.id,p.name,p.name_norm || ' ' || coalesce((
                SELECT group_concat(s.synonym_norm,' ') FROM synonym s
                WHERE s.product_id=p.id),'')
            FROM product p ORDER BY p.id""")
        con.execute("INSERT INTO product_fts(product_fts) VALUES('optimize')")

        counts = dict(con.execute("SELECT source,count(*) FROM product GROUP BY source"))
        assert counts == {"skurikhin": 1103, "usda": 8180}, counts
        assert con.execute("SELECT count(*) FROM product_fts WHERE rowid != cast(product_id as integer)").fetchone()[0] == 0
        assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        assert not con.execute("PRAGMA foreign_key_check").fetchall()
        first = con.execute("""SELECT p.code FROM product_fts f JOIN product p ON p.id=cast(f.product_id as integer)
            WHERE product_fts MATCH '"гречка"*' LIMIT 1""").fetchone()
        assert first == ("6.6.4",), first
        usda_after = con.execute(
            "SELECT id,name,protein,fat,carbs,kcal,waste_pct,page_num FROM product "
            "WHERE source='usda' ORDER BY id").fetchall()
        assert usda_after == usda_before, "USDA rows changed"
        usda_measures_after = con.execute(
            "SELECT m.* FROM measure m JOIN product p ON p.id=m.product_id "
            "WHERE p.source='usda' ORDER BY m.id").fetchall()
        assert usda_measures_after == usda_measures_before, "USDA measures changed"
        con.commit()
        con.execute("PRAGMA journal_mode=DELETE")
    finally:
        fresh.close()
        con.close()

    shutil.copy2(staged, DB)
    shutil.copy2(staged, ASSET_DB)
    staged.unlink()
    print("BACKUP", backup_dir)
    print("DEPLOY SHA256", hashlib.sha256(DB.read_bytes()).hexdigest())
    assert DB.read_bytes() == ASSET_DB.read_bytes()


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true",
                        help="write the merged database (default: dry run)")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        scratch = Path(tmp) / "skurikhin.db"
        build_skurikhin_scratch(scratch)
        current = _rows(DB, "skurikhin")
        fresh = _rows(scratch, "skurikhin")
        changes = diff(current, fresh)
        print(f"Skurikhin rows: current={len(current)} fresh={len(fresh)} changes={len(changes)}")
        for line in changes:
            print(" ", line)
        if not args.apply:
            print("dry run: pass --apply to merge")
            return
        if not changes:
            print("nothing to do")
            return
        apply_merge(scratch)


if __name__ == "__main__":
    main()
