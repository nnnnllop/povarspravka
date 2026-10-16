"""Unit tests for USDA database builder and canonical schema with FTS5 search."""

import tempfile
import unittest
from pathlib import Path
import sqlite3

from tools.data_pipeline.usda.db_builder import merge_into_reference_db, populate_database


class TestDatabaseBuilder(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "test_products.db"
        self.ref_db_path = Path(self.temp_dir.name) / "test_reference.db"

        self.categories = [
            {"id": 101, "code": "USDA_0100", "name": "Dairy and Egg Products", "name_ru": "Молочные продукты и яйца"},
            {"id": 105, "code": "USDA_0500", "name": "Poultry Products", "name_ru": "Птица и продукты из птицы"},
        ]

        self.products = [
            {
                "id": 167512,
                "code": "USDA_167512",
                "name_ru": "Картофель, запеченный, с кожурой, без соли",
                "name_en": "Potatoes, baked, flesh and skin, without salt",
                "name_norm": "картофель запеченный с кожурой без соли",
                "group_id": 101,
                "source": "usda",
                "waste_pct": 0.0,
                "macros": {"protein": 2.5, "fat": 0.1, "carbs": 21.1, "kcal": 93.0, "water": 75.0, "fiber": 2.2},
                "all_nutrients": {"PROCNT": 2.5, "FAT": 0.1, "CHOCDF": 21.1, "ENERC_KCAL": 93.0, "CA": 15.0},
                "measures": [{"name_en": "1 medium", "name_ru": "1 шт (средний)", "grams": 173.0}],
                "synonyms": ["картошка печеная", "Potatoes, baked, flesh and skin, without salt"],
                "synonyms_norm": {
                    "картошка печеная": "картошка печеная",
                    "Potatoes, baked, flesh and skin, without salt": "potatoes baked flesh and skin without salt",
                },
            },
            {
                "id": 167513,
                "code": "USDA_167513",
                "name_ru": "Куриная грудка (филе), запеченная",
                "name_en": "Chicken breast, baked",
                "name_norm": "куриная грудка филе запеченная",
                "group_id": 105,
                "source": "usda",
                "waste_pct": 0.0,
                "macros": {"protein": 31.0, "fat": 3.6, "carbs": 0.0, "kcal": 165.0, "water": 65.0, "fiber": 0.0},
                "all_nutrients": {"PROCNT": 31.0, "FAT": 3.6, "CHOCDF": 0.0, "ENERC_KCAL": 165.0},
                "measures": [{"name_en": "1 fillet", "name_ru": "1 филе", "grams": 120.0}],
                "synonyms": ["курочка филе", "цыпленок", "Chicken breast, baked"],
                "synonyms_norm": {
                    "курочка филе": "курочка филе",
                    "цыпленок": "цыпленок",
                    "Chicken breast, baked": "chicken breast baked",
                },
            },
        ]

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_populate_canonical_tables_and_fts_queries(self):
        stats = populate_database(self.db_path, self.categories, self.products)
        self.assertEqual(stats["groups"], 2)
        self.assertEqual(stats["products"], 2)
        self.assertEqual(stats["fts_records"], 2)
        self.assertEqual(stats["measures"], 2)
        self.assertEqual(stats["synonyms"], 5)

        conn = sqlite3.connect(str(self.db_path))
        cur = conn.cursor()

        # Check canonical table names exist
        tables = [r[0] for r in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
        self.assertIn("food_group", tables)
        self.assertIn("product", tables)
        self.assertIn("measure", tables)
        self.assertIn("nutrient_value", tables)
        self.assertIn("synonym", tables)
        self.assertIn("product_fts", tables)

        # 1. Search by Russian name prefix
        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'картоф*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 167512)

        # 2. Search by Russian synonym
        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'картошк*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 167512)

        # 3. Search by English original name
        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'chicken*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 167513)

        # 4. Search by another Russian synonym
        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'цыпленок*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 167513)

        conn.close()

    def test_merge_into_reference_db(self):
        # Create an existing reference.db with 1 skurikhin product
        conn = sqlite3.connect(str(self.ref_db_path))
        conn.execute("""
        CREATE TABLE food_group (id INTEGER PRIMARY KEY, code TEXT NOT NULL, name TEXT NOT NULL);
        """)
        conn.execute("INSERT INTO food_group VALUES (1, '1', 'Молоко и молочные продукты')")
        conn.execute("""
        CREATE TABLE product (
            id INTEGER PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
            name_norm TEXT NOT NULL, group_id INTEGER NOT NULL, source TEXT NOT NULL,
            page_num INTEGER, waste_pct REAL, protein REAL, fat REAL, carbs REAL, kcal REAL,
            water REAL, fiber REAL, ash REAL, organic_acids REAL, sugars REAL, starch REAL,
            sfa REAL, pufa REAL, chol REAL, alcohol REAL
        );
        """)
        conn.execute("""
        INSERT INTO product VALUES (1, '1.1.1', 'Молоко пастеризованное', 'молоко пастеризованное', 1, 'skurikhin', 25, 0.0, 2.8, 3.2, 4.7, 58.0, 88.0, 0.0, 0.7, 0.15, 4.7, 0.0, 1.9, 0.1, 10.0, 0.0);
        """)
        conn.execute("CREATE TABLE measure (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, name TEXT, grams REAL);")
        conn.execute("CREATE TABLE nutrient_value (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, nutrient_code TEXT, value REAL);")
        conn.execute("CREATE TABLE synonym (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, synonym TEXT, synonym_norm TEXT);")
        conn.execute("CREATE VIRTUAL TABLE product_fts USING fts5(product_id UNINDEXED, name, name_norm);")
        conn.execute("INSERT INTO product_fts VALUES (1, 'Молоко пастеризованное', 'молоко пастеризованное');")
        conn.commit()
        conn.close()

        # Merge USDA into it
        stats = merge_into_reference_db(self.ref_db_path, self.categories, self.products)
        self.assertEqual(stats["products"], 3)  # 1 skurikhin + 2 usda
        self.assertEqual(stats["groups"], 3)    # 1 skurikhin + 2 usda

        conn = sqlite3.connect(str(self.ref_db_path))
        cur = conn.cursor()

        skurikhin_count = cur.execute("SELECT count(*) FROM product WHERE source = 'skurikhin'").fetchone()[0]
        usda_count = cur.execute("SELECT count(*) FROM product WHERE source = 'usda'").fetchone()[0]
        self.assertEqual(skurikhin_count, 1)
        self.assertEqual(usda_count, 2)

        # FTS search on merged db
        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'пастеризованное*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 1)

        cur.execute("SELECT product_id, name FROM product_fts WHERE product_fts MATCH 'chicken*'")
        hits = cur.fetchall()
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0][0], 167513)

        conn.close()


if __name__ == "__main__":
    unittest.main()
