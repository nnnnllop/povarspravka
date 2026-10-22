"""Comprehensive automated test suite for Skurikhin data pipeline."""
import unittest
import sqlite3
import json
from pathlib import Path
import pymupdf

from tools.data_pipeline.skurikhin.config import (
    DEFAULT_PDF_PATH,
    OUTPUT_DIR
)
from tools.data_pipeline.skurikhin.subject_index_parser import (
    parse_subject_index,
    normalize_code
)
from tools.data_pipeline.skurikhin.appendices_parser import (
    parse_appendix_1,
    parse_appendix_2,
    parse_appendix_3,
    find_waste_percentage,
    get_measures_for_product
)
from tools.data_pipeline.skurikhin.table_extractor import (
    parse_cell_tokens,
    detect_columns_left,
    detect_columns_right,
    determine_food_group,
    extract_all_products
)
from tools.data_pipeline.skurikhin.validator import SkurikhinValidator
from tools.data_pipeline.skurikhin.database_builder import (
    normalize_text,
    export_json,
    export_csv,
    build_sqlite_database
)


class TestSubjectIndexParser(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = pymupdf.open(str(DEFAULT_PDF_PATH))
        cls.products = parse_subject_index(cls.doc)

    def test_extracted_count(self):
        # Must extract over 1000 products from subject index
        self.assertGreaterEqual(len(self.products), 1000)

    def test_code_normalization(self):
        self.assertEqual(normalize_code("1.1.2.2"), "1.1.2.2")
        self.assertEqual(normalize_code("  3.5.2.1  "), "3.5.2.1")
        self.assertEqual(normalize_code("Code: 9.1.1.3"), "9.1.1.3")
        self.assertIsNone(normalize_code(""))

    def test_known_products_exist(self):
        codes = {p["code"]: p["name"] for p in self.products}
        self.assertIn("1.1.1.1", codes)
        self.assertIn("молоко", codes["1.1.1.1"].lower())
        self.assertIn("9.1.1.1", codes)
        self.assertIn("абрикос", codes["9.1.1.1"].lower())


class TestAppendicesParser(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = pymupdf.open(str(DEFAULT_PDF_PATH))
        cls.w_map = parse_appendix_1(cls.doc)
        cls.m_map = parse_appendix_2(cls.doc)
        cls.p_map = parse_appendix_3(cls.doc)

    def test_appendix_counts(self):
        self.assertGreaterEqual(len(self.w_map), 200)
        self.assertGreaterEqual(len(self.m_map), 50)
        self.assertGreaterEqual(len(self.p_map), 30)

    def test_known_waste_percentages(self):
        # Potatoes waste is 28%
        w_pot = find_waste_percentage("Картофель", self.w_map)
        self.assertIsNotNone(w_pot)
        self.assertTrue(19.0 <= w_pot <= 30.0, f"Отходы картофеля вне нормы: {w_pot}")

        # Cabbage waste is 20%
        w_cab = find_waste_percentage("Капуста белокочанная", self.w_map)
        self.assertIsNotNone(w_cab)
        self.assertAlmostEqual(w_cab, 20.0, delta=2.0)

    def test_known_measures(self):
        meas = get_measures_for_product("Картофель", self.m_map, self.p_map)
        # Whole potatoes must not inherit cups from "крахмал картофельный".
        self.assertFalse(any("стакан" in name for name, _ in meas))
        starch = dict(get_measures_for_product(
            "Крахмал картофельный", self.m_map, self.p_map))
        self.assertEqual(starch["стакан (чайный 250 мл)"], 200.0)


class TestTableExtractor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = pymupdf.open(str(DEFAULT_PDF_PATH))

    def test_cell_token_cleaning(self):
        self.assertAlmostEqual(parse_cell_tokens(["1", "4.9"]), 4.9)
        self.assertAlmostEqual(parse_cell_tokens(["!", "91,2"]), 91.2)
        self.assertAlmostEqual(parse_cell_tokens([".90,2"]), 90.2)
        self.assertAlmostEqual(parse_cell_tokens(["-"]), 0.0)
        self.assertAlmostEqual(parse_cell_tokens([]), 0.0)

    def test_columns_detection(self):
        bounds_l = detect_columns_left(self.doc[24])
        self.assertGreaterEqual(len(bounds_l), 8)
        col_names = [b[0] for b in bounds_l]
        self.assertIn("water", col_names)
        self.assertIn("protein", col_names)
        self.assertIn("fat", col_names)
        self.assertIn("carbs", col_names)

        bounds_r = detect_columns_right(self.doc[25])
        self.assertGreaterEqual(len(bounds_r), 10)
        r_col_names = [b[0] for b in bounds_r]
        self.assertIn("na", r_col_names)
        self.assertIn("ca", r_col_names)
        self.assertIn("kcal", r_col_names)

    def test_food_group_determination(self):
        g_id, g_name = determine_food_group("1.1.2.2", 24)
        self.assertEqual(g_id, 1)
        self.assertIn("Молоко", g_name)

        g_id, g_name = determine_food_group("3.1.2", 52)
        self.assertEqual(g_id, 3)
        self.assertIn("Мясо", g_name)


class TestValidator(unittest.TestCase):
    def setUp(self):
        self.validator = SkurikhinValidator()

    def test_valid_product(self):
        prod = {
            "id": 1,
            "code": "1.1.1.1",
            "name": "Молоко пастеризованное нежирное",
            "group_id": 1,
            "protein": 3.0,
            "fat": 0.05,
            "carbs": 4.9,
            "kcal": 32.0,
            "water": 91.2,
            "ash": 0.7,
            "organic_acids": 0.15,
            "waste_pct": None
        }
        is_valid, warns, metrics = self.validator.validate_product(prod)
        self.assertTrue(is_valid)
        self.assertAlmostEqual(metrics["proximate_sum"], 100.0, delta=0.5)
        self.assertAlmostEqual(metrics["energy_diff_pct"], 1.6, delta=0.5)

    def test_invalid_negative_protein(self):
        prod = {
            "id": 2,
            "code": "test.1",
            "name": "Test product",
            "group_id": 1,
            "protein": -5.0,
            "fat": 1.0,
            "carbs": 10.0,
            "kcal": 69.0,
            "water": 80.0,
            "ash": 1.0
        }
        is_valid, warns, metrics = self.validator.validate_product(prod)
        self.assertFalse(is_valid)
        self.assertTrue(any("Negative value for protein" in w for w in warns))


class TestDatabaseBuilder(unittest.TestCase):
    def test_text_normalization(self):
        self.assertEqual(normalize_text("Свёкла варёная!"), "свекла вареная")
        self.assertEqual(normalize_text("Хлеб «Бородинский» 100г"), "хлеб бородинский 100г")

    def test_database_and_fts(self):
        test_products = [
            {
                "id": 1,
                "code": "8.1.5.15",
                "name": "Борщ с картофелем",
                "group_id": 8,
                "source": "skurikhin",
                "protein": 2.5,
                "fat": 3.0,
                "carbs": 7.0,
                "kcal": 65.0,
                "water": 86.0,
                "ash": 1.5,
                "waste_pct": None,
                "measures": [("порция", 250.0)],
                "minerals": {"na": 300.0, "k": 250.0},
                "vitamins": {"c": 8.0}
            },
            {
                "id": 2,
                "code": "1.1.1.1",
                "name": "Молоко пастеризованное нежирное",
                "group_id": 1,
                "source": "skurikhin",
                "protein": 3.0,
                "fat": 0.05,
                "carbs": 4.9,
                "kcal": 32.0,
                "water": 91.2,
                "ash": 0.7,
                "waste_pct": None,
                "measures": [("стакан (чайный 250 мл)", 250.0)],
                "minerals": {"ca": 126.0},
                "vitamins": {"b2": 0.15}
            }
        ]
        test_db = OUTPUT_DIR / "test_ref.db"
        build_sqlite_database(test_products, test_db)
        self.assertTrue(test_db.exists())

        conn = sqlite3.connect(str(test_db))
        c = conn.cursor()
        c.execute("SELECT count(*) FROM product;")
        self.assertEqual(c.fetchone()[0], 2)

        # Test FTS5 search
        c.execute("SELECT product_id FROM product_fts WHERE product_fts MATCH 'борщ*';")
        rows = c.fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][0], 1)

        conn.close()
        test_db.unlink()


if __name__ == "__main__":
    unittest.main()
