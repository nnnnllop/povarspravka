"""SQLite Database builder conforming to plan.md Section 6.4 schema with FTS5 search."""

from __future__ import annotations

import logging
import sqlite3
from pathlib import Path
from typing import Any

from .config import DEFAULT_OUTPUT_DB, REFERENCE_DB_PATH

logger = logging.getLogger(__name__)

CREATE_CANONICAL_TABLES_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS food_group (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS product (
    id INTEGER PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    name_norm TEXT NOT NULL,
    group_id INTEGER NOT NULL,
    source TEXT NOT NULL,
    page_num INTEGER,
    waste_pct REAL DEFAULT 0.0,
    protein REAL NOT NULL DEFAULT 0.0,
    fat REAL NOT NULL DEFAULT 0.0,
    carbs REAL NOT NULL DEFAULT 0.0,
    kcal REAL NOT NULL DEFAULT 0.0,
    water REAL NOT NULL DEFAULT 0.0,
    fiber REAL NOT NULL DEFAULT 0.0,
    ash REAL NOT NULL DEFAULT 0.0,
    organic_acids REAL NOT NULL DEFAULT 0.0,
    sugars REAL NOT NULL DEFAULT 0.0,
    starch REAL NOT NULL DEFAULT 0.0,
    sfa REAL NOT NULL DEFAULT 0.0,
    pufa REAL NOT NULL DEFAULT 0.0,
    chol REAL NOT NULL DEFAULT 0.0,
    alcohol REAL NOT NULL DEFAULT 0.0,
    FOREIGN KEY (group_id) REFERENCES food_group (id)
);

CREATE INDEX IF NOT EXISTS idx_product_group ON product(group_id);
CREATE INDEX IF NOT EXISTS idx_product_source ON product(source);

CREATE TABLE IF NOT EXISTS measure (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    grams REAL NOT NULL,
    FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_measure_product ON measure(product_id);

CREATE TABLE IF NOT EXISTS nutrient_value (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL,
    nutrient_code TEXT NOT NULL,
    value REAL NOT NULL,
    FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_nutrient_product ON nutrient_value(product_id);

CREATE TABLE IF NOT EXISTS synonym (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id INTEGER NOT NULL,
    synonym TEXT NOT NULL,
    synonym_norm TEXT NOT NULL,
    FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_synonym_product ON synonym(product_id);
CREATE INDEX IF NOT EXISTS idx_synonym_norm ON synonym(synonym_norm);

CREATE VIRTUAL TABLE IF NOT EXISTS product_fts USING fts5(
    product_id UNINDEXED,
    name,
    name_norm,
    tokenize = 'unicode61 remove_diacritics 2'
);
"""


def init_database(db_path: Path) -> sqlite3.Connection:
    """Initialize SQLite database schema and optimize pragmas."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA page_size = 4096")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.executescript(CREATE_CANONICAL_TABLES_SQL)
    conn.commit()
    return conn


def populate_database(
    db_path: Path,
    categories: list[dict[str, Any]],
    products_data: list[dict[str, Any]],
) -> dict[str, int]:
    """Populate database with validated categories, products, nutrients, measures, and FTS index."""
    if db_path.exists():
        try:
            db_path.unlink()
        except Exception:
            pass

    conn = init_database(db_path)
    cur = conn.cursor()

    logger.info("Inserting %d food groups...", len(categories))
    cur.executemany(
        "INSERT INTO food_group (id, code, name) VALUES (?, ?, ?)",
        [(c["id"], c.get("code", f"USDA_{c['id']}"), c.get("name_ru") or c.get("name")) for c in categories],
    )

    prod_rows = []
    fts_rows = []
    nut_rows = []
    measure_rows = []
    syn_rows = []

    for item in products_data:
        pid = item["id"]
        code = item.get("code") or f"USDA_{pid}"
        name = item["name_ru"]
        name_norm = item["name_norm"]
        group_id = item["group_id"]
        source = item.get("source", "usda")
        page_num = item.get("page_num", 0)
        waste_pct = item.get("waste_pct", 0.0)
        macros = item["macros"]

        prod_rows.append(
            (
                pid,
                code,
                name,
                name_norm,
                group_id,
                source,
                page_num,
                waste_pct,
                macros.get("protein", 0.0),
                macros.get("fat", 0.0),
                macros.get("carbs", 0.0),
                macros.get("kcal", 0.0),
                macros.get("water", 0.0),
                macros.get("fiber", 0.0),
                macros.get("ash", 0.0),
                macros.get("organic_acids", 0.0),
                macros.get("sugars", 0.0),
                macros.get("starch", 0.0),
                macros.get("sfa", 0.0),
                macros.get("pufa", 0.0),
                macros.get("chol", 0.0),
                macros.get("alcohol", 0.0),
            )
        )

        # Synonyms
        synonyms_list = item.get("synonyms", [])
        norm_synonyms = []
        for syn in synonyms_list:
            snorm = item.get("synonyms_norm", {}).get(syn, syn.lower())
            norm_synonyms.append(snorm)
            syn_rows.append((pid, syn, snorm))

        # FTS entry: search by Russian name and synonyms (including English terms)
        fts_search_text = f"{name_norm} {' '.join(norm_synonyms)}"
        fts_rows.append((pid, name, fts_search_text))

        # Micronutrients
        for code_str, val in item.get("all_nutrients", {}).items():
            if val is not None and val > 0.0:
                nut_rows.append((pid, str(code_str), round(float(val), 4)))

        # Measures / portions
        for m in item.get("measures", []):
            measure_rows.append((pid, m.get("name_ru") or m.get("name_en") or "порция", round(float(m["grams"]), 2)))

    logger.info("Inserting %d products...", len(prod_rows))
    cur.executemany(
        """
        INSERT INTO product (
            id, code, name, name_norm, group_id, source, page_num, waste_pct,
            protein, fat, carbs, kcal, water, fiber, ash, organic_acids,
            sugars, starch, sfa, pufa, chol, alcohol
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        prod_rows,
    )

    logger.info("Inserting %d FTS5 index records...", len(fts_rows))
    cur.executemany(
        "INSERT INTO product_fts (rowid, product_id, name, name_norm) VALUES (?, ?, ?, ?)",
        [(r[0], r[0], r[1], r[2]) for r in fts_rows],
    )

    logger.info("Inserting %d nutrient value records...", len(nut_rows))
    cur.executemany(
        "INSERT INTO nutrient_value (product_id, nutrient_code, value) VALUES (?, ?, ?)",
        nut_rows,
    )

    logger.info("Inserting %d measure records...", len(measure_rows))
    cur.executemany(
        "INSERT INTO measure (product_id, name, grams) VALUES (?, ?, ?)",
        measure_rows,
    )

    logger.info("Inserting %d synonym records...", len(syn_rows))
    cur.executemany(
        "INSERT INTO synonym (product_id, synonym, synonym_norm) VALUES (?, ?, ?)",
        syn_rows,
    )

    conn.commit()

    # Query counts
    counts = {
        "groups": cur.execute("SELECT count(*) FROM food_group").fetchone()[0],
        "products": cur.execute("SELECT count(*) FROM product").fetchone()[0],
        "fts_records": cur.execute("SELECT count(*) FROM product_fts").fetchone()[0],
        "nutrients": cur.execute("SELECT count(*) FROM nutrient_value").fetchone()[0],
        "measures": cur.execute("SELECT count(*) FROM measure").fetchone()[0],
        "synonyms": cur.execute("SELECT count(*) FROM synonym").fetchone()[0],
    }

    # Optimize FTS index and database size
    cur.execute("INSERT INTO product_fts(product_fts) VALUES('optimize')")
    conn.commit()
    cur.execute("PRAGMA vacuum")
    conn.close()

    logger.info("Database population complete: %s", counts)
    return counts


def merge_into_reference_db(
    reference_db_path: Path,
    categories: list[dict[str, Any]],
    products_data: list[dict[str, Any]],
) -> dict[str, int]:
    """Merge USDA products and food groups into the unified reference.db."""
    if not reference_db_path.exists():
        logger.info("reference.db not found at %s. Creating new unified database...", reference_db_path)
        return populate_database(reference_db_path, categories, products_data)

    logger.info("Merging USDA products into unified reference database at %s...", reference_db_path)
    conn = sqlite3.connect(str(reference_db_path))
    cur = conn.cursor()

    # Ensure tables exist
    cur.executescript(CREATE_CANONICAL_TABLES_SQL)

    # 1. Clean existing USDA records
    cur.execute("DELETE FROM product_fts WHERE product_id IN (SELECT id FROM product WHERE source = 'usda')")
    cur.execute("DELETE FROM synonym WHERE product_id IN (SELECT id FROM product WHERE source = 'usda')")
    cur.execute("DELETE FROM measure WHERE product_id IN (SELECT id FROM product WHERE source = 'usda')")
    cur.execute("DELETE FROM nutrient_value WHERE product_id IN (SELECT id FROM product WHERE source = 'usda')")
    cur.execute("DELETE FROM product WHERE source = 'usda'")
    cur.execute("DELETE FROM food_group WHERE code LIKE 'USDA_%'")

    # 2. Insert USDA categories
    cur.executemany(
        "INSERT OR IGNORE INTO food_group (id, code, name) VALUES (?, ?, ?)",
        [(c["id"], c.get("code", f"USDA_{c['id']}"), c.get("name_ru") or c.get("name")) for c in categories],
    )

    prod_rows = []
    fts_rows = []
    nut_rows = []
    measure_rows = []
    syn_rows = []

    for item in products_data:
        pid = item["id"]
        code = item.get("code") or f"USDA_{pid}"
        name = item["name_ru"]
        name_norm = item["name_norm"]
        group_id = item["group_id"]
        source = item.get("source", "usda")
        page_num = item.get("page_num", 0)
        waste_pct = item.get("waste_pct", 0.0)
        macros = item["macros"]

        prod_rows.append(
            (
                pid,
                code,
                name,
                name_norm,
                group_id,
                source,
                page_num,
                waste_pct,
                macros.get("protein", 0.0),
                macros.get("fat", 0.0),
                macros.get("carbs", 0.0),
                macros.get("kcal", 0.0),
                macros.get("water", 0.0),
                macros.get("fiber", 0.0),
                macros.get("ash", 0.0),
                macros.get("organic_acids", 0.0),
                macros.get("sugars", 0.0),
                macros.get("starch", 0.0),
                macros.get("sfa", 0.0),
                macros.get("pufa", 0.0),
                macros.get("chol", 0.0),
                macros.get("alcohol", 0.0),
            )
        )

        synonyms_list = item.get("synonyms", [])
        norm_synonyms = []
        for syn in synonyms_list:
            snorm = item.get("synonyms_norm", {}).get(syn, syn.lower())
            norm_synonyms.append(snorm)
            syn_rows.append((pid, syn, snorm))

        fts_search_text = f"{name_norm} {' '.join(norm_synonyms)}"
        fts_rows.append((pid, name, fts_search_text))

        for code_str, val in item.get("all_nutrients", {}).items():
            if val is not None and val > 0.0:
                nut_rows.append((pid, str(code_str), round(float(val), 4)))

        for m in item.get("measures", []):
            measure_rows.append((pid, m.get("name_ru") or m.get("name_en") or "порция", round(float(m["grams"]), 2)))

    cur.executemany(
        """
        INSERT OR REPLACE INTO product (
            id, code, name, name_norm, group_id, source, page_num, waste_pct,
            protein, fat, carbs, kcal, water, fiber, ash, organic_acids,
            sugars, starch, sfa, pufa, chol, alcohol
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        prod_rows,
    )

    cur.execute("DELETE FROM product_fts WHERE product_id IN (SELECT id FROM product WHERE source = 'usda')")
    cur.executemany(
        "INSERT INTO product_fts (rowid, product_id, name, name_norm) VALUES (?, ?, ?, ?)",
        [(r[0], r[0], r[1], r[2]) for r in fts_rows],
    )

    cur.executemany(
        "INSERT INTO nutrient_value (product_id, nutrient_code, value) VALUES (?, ?, ?)",
        nut_rows,
    )

    cur.executemany(
        "INSERT INTO measure (product_id, name, grams) VALUES (?, ?, ?)",
        measure_rows,
    )

    cur.executemany(
        "INSERT INTO synonym (product_id, synonym, synonym_norm) VALUES (?, ?, ?)",
        syn_rows,
    )

    conn.commit()

    counts = {
        "groups": cur.execute("SELECT count(*) FROM food_group").fetchone()[0],
        "products": cur.execute("SELECT count(*) FROM product").fetchone()[0],
        "fts_records": cur.execute("SELECT count(*) FROM product_fts").fetchone()[0],
        "nutrients": cur.execute("SELECT count(*) FROM nutrient_value").fetchone()[0],
        "measures": cur.execute("SELECT count(*) FROM measure").fetchone()[0],
        "synonyms": cur.execute("SELECT count(*) FROM synonym").fetchone()[0],
    }

    cur.execute("INSERT INTO product_fts(product_fts) VALUES('optimize')")
    conn.commit()
    cur.execute("PRAGMA vacuum")
    conn.close()

    logger.info("Unified reference.db updated successfully: %s", counts)
    return counts
