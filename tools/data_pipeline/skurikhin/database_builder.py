"""Database and Dataset Builder for Skurikhin 2002 dataset.

Generates:
1. SQLite reference database (reference.db) with FTS5 search index
2. JSON dataset (skurikhin_products.json)
3. CSV dataset (skurikhin_products.csv)
4. Validation report (validation_report.json)
"""
from typing import Dict, List, Any
import csv
import json
import sqlite3
import re
from pathlib import Path

from .config import (
    FOOD_GROUPS,
    NUTRIENT_CODES,
    OUTPUT_DIR,
    DB_PATH,
    JSON_PATH,
    CSV_PATH,
    VALIDATION_REPORT_PATH,
    SKURIKHIN_SYNONYMS
)


def normalize_text(text: str) -> str:
    """Normalize text for search indexing: lowercase, ё -> е, strip punctuation."""
    if not text:
        return ""
    norm = text.lower().replace("ё", "е")
    # Replace punctuation with spaces
    norm = re.sub(r'[^\w\s]', ' ', norm)
    # Collapse whitespace
    norm = re.sub(r'\s+', ' ', norm).strip()
    return norm


def export_json(products: List[Dict[str, Any]], output_path: Path = JSON_PATH) -> None:
    """Export products dataset to JSON."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(products, f, ensure_ascii=False, indent=2)


def export_csv(products: List[Dict[str, Any]], output_path: Path = CSV_PATH) -> None:
    """Export products dataset to flat CSV for spreadsheet inspection."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "id", "code", "name", "group_id", "group_name", "source", "page_num",
        "waste_pct", "protein", "fat", "carbs", "kcal", "water", "fiber",
        "ash", "organic_acids", "sugars", "starch", "sfa", "pufa", "chol", "alcohol",
        "na", "k", "ca", "mg", "p", "fe",
        "vit_a", "carotene", "re", "te", "b1", "b2", "pp", "ne", "c"
    ]

    with open(output_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for p in products:
            row = dict(p)
            # Flatten minerals
            minerals = p.get("minerals", {})
            for mk, mv in minerals.items():
                row[mk] = mv
            # Flatten vitamins
            vitamins = p.get("vitamins", {})
            for vk, vv in vitamins.items():
                row[vk] = vv
            writer.writerow(row)


def build_sqlite_database(products: List[Dict[str, Any]], db_path: Path = DB_PATH) -> None:
    """Build production SQLite database conforming to plan.md schema with FTS5 search."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    cursor = conn.cursor()

    # Enable WAL mode and foreign keys
    cursor.execute("PRAGMA journal_mode=WAL;")
    cursor.execute("PRAGMA foreign_keys=ON;")

    # 1. FOOD_GROUP table
    cursor.execute("""
    CREATE TABLE food_group (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL
    );
    """)

    for grp in FOOD_GROUPS:
        cursor.execute("INSERT INTO food_group (id, code, name) VALUES (?, ?, ?);",
                       (grp["id"], grp["code"], grp["name"]))

    # 2. PRODUCT table
    cursor.execute("""
    CREATE TABLE product (
        id INTEGER PRIMARY KEY,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        name_norm TEXT NOT NULL,
        group_id INTEGER NOT NULL,
        source TEXT NOT NULL,
        page_num INTEGER,
        waste_pct REAL,
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
    """)

    # 3. MEASURE table
    cursor.execute("""
    CREATE TABLE measure (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        grams REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
    );
    """)

    # 4. NUTRIENT_VALUE table
    cursor.execute("""
    CREATE TABLE nutrient_value (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        nutrient_code TEXT NOT NULL,
        value REAL NOT NULL,
        FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
    );
    """)

    # 5. SYNONYM table
    cursor.execute("""
    CREATE TABLE synonym (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        synonym TEXT NOT NULL,
        synonym_norm TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES product (id) ON DELETE CASCADE
    );
    """)

    # 6. FTS5 Virtual Table for sub-30ms Cyrillic full-text search
    cursor.execute("""
    CREATE VIRTUAL TABLE product_fts USING fts5(
        product_id UNINDEXED,
        name,
        name_norm,
        tokenize='unicode61 remove_diacritics 2'
    );
    """)

    # Insert products and child records
    for p in products:
        p_id = p["id"]
        code = p["code"]
        name = p["name"]
        name_norm = normalize_text(name)
        grp_id = p["group_id"]
        source = p.get("source", "skurikhin")
        page_num = p.get("page_num", 0)
        waste_pct = p.get("waste_pct")

        cursor.execute("""
        INSERT INTO product (
            id, code, name, name_norm, group_id, source, page_num, waste_pct,
            protein, fat, carbs, kcal, water, fiber, ash, organic_acids,
            sugars, starch, sfa, pufa, chol, alcohol
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (
            p_id, code, name, name_norm, grp_id, source, page_num, waste_pct,
            p.get("protein", 0.0), p.get("fat", 0.0), p.get("carbs", 0.0), p.get("kcal", 0.0),
            p.get("water", 0.0), p.get("fiber", 0.0), p.get("ash", 0.0), p.get("organic_acids", 0.0),
            p.get("sugars", 0.0), p.get("starch", 0.0), p.get("sfa", 0.0), p.get("pufa", 0.0),
            p.get("chol", 0.0), p.get("alcohol", 0.0)
        ))

        # Insert synonyms and construct enriched FTS search text
        prod_synonyms = []
        for syn_code, syn_word in SKURIKHIN_SYNONYMS:
            if code == syn_code or code.startswith(syn_code + "."):
                prod_synonyms.append(syn_word)
                cursor.execute(
                    "INSERT INTO synonym (product_id, synonym, synonym_norm) VALUES (?, ?, ?);",
                    (p_id, syn_word, normalize_text(syn_word))
                )

        fts_name_norm = f"{name_norm} {' '.join(normalize_text(s) for s in prod_synonyms)}"

        # Insert FTS index entry with explicit rowid
        cursor.execute("INSERT INTO product_fts (rowid, product_id, name, name_norm) VALUES (?, ?, ?, ?);",
                       (p_id, p_id, name, fts_name_norm))

        # Insert measures
        for m_name, grams in p.get("measures", []):
            cursor.execute("INSERT INTO measure (product_id, name, grams) VALUES (?, ?, ?);",
                           (p_id, m_name, grams))

        # Insert micronutrients into nutrient_value
        minerals = p.get("minerals", {})
        for mk, mv in minerals.items():
            if mv > 0 and mk in NUTRIENT_CODES:
                n_info = NUTRIENT_CODES[mk]
                cursor.execute("INSERT INTO nutrient_value (product_id, nutrient_code, value) VALUES (?, ?, ?);",
                               (p_id, n_info["code"], mv))

        vitamins = p.get("vitamins", {})
        for vk, vv in vitamins.items():
            if vv > 0 and vk in NUTRIENT_CODES:
                n_info = NUTRIENT_CODES[vk]
                cursor.execute("INSERT INTO nutrient_value (product_id, nutrient_code, value) VALUES (?, ?, ?);",
                               (p_id, n_info["code"], vv))

    # Add indexes for speed
    cursor.execute("CREATE INDEX idx_product_group ON product(group_id);")
    cursor.execute("CREATE INDEX idx_product_source ON product(source);")
    cursor.execute("CREATE INDEX idx_measure_product ON measure(product_id);")
    cursor.execute("CREATE INDEX idx_nutrient_product ON nutrient_value(product_id);")

    conn.commit()
    conn.close()


def save_validation_report(report: Dict[str, Any], output_path: Path = VALIDATION_REPORT_PATH) -> None:
    """Save validation summary report to JSON."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
