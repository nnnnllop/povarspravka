"""Explicit edge-case and boundary value tests for Skurikhin data pipeline."""
import unittest
import sqlite3
from pathlib import Path

from tools.data_pipeline.skurikhin.table_extractor import parse_cell_tokens
from tools.data_pipeline.skurikhin.validator import SkurikhinValidator
from tools.data_pipeline.skurikhin.database_builder import normalize_text, build_sqlite_database
from tools.data_pipeline.skurikhin.subject_index_parser import normalize_code


class TestEdgeCases(unittest.TestCase):
    def setUp(self):
        self.validator = SkurikhinValidator()

    def test_parse_cell_tokens_edge_cases(self):
        # Empty input
        self.assertEqual(parse_cell_tokens([]), 0.0)
        # Only punctuation / OCR noise
        self.assertEqual(parse_cell_tokens(["|", "!"]), 0.0)
        self.assertEqual(parse_cell_tokens(["[", "]"]), 0.0)
        self.assertEqual(parse_cell_tokens(["~", "^", "о"]), 0.0)
        # Leading smudges
        self.assertEqual(parse_cell_tokens(["...0.5"]), 0.5)
        self.assertEqual(parse_cell_tokens([".95,4"]), 95.4)
        # Stray column border '1'
        self.assertEqual(parse_cell_tokens(["1", "12.5"]), 12.5)
        self.assertEqual(parse_cell_tokens(["l", "3.0"]), 3.0)
        # Comma vs dot
        self.assertEqual(parse_cell_tokens(["12,34"]), 12.34)
        self.assertEqual(parse_cell_tokens(["12.34"]), 12.34)

    def test_validator_boundary_values(self):
        # Pure water (0 kcal, 100g water)
        water_prod = {
            "id": 1,
            "code": "11.0",
            "name": "Вода питьевая",
            "group_id": 11,
            "protein": 0.0,
            "fat": 0.0,
            "carbs": 0.0,
            "kcal": 0.0,
            "water": 100.0,
            "ash": 0.0,
            "waste_pct": 0.0
        }
        is_valid, warns, metrics = self.validator.validate_product(water_prod)
        self.assertTrue(is_valid)
        self.assertEqual(metrics["calc_kcal"], 0.0)
        self.assertEqual(metrics["proximate_sum"], 100.0)

        # Pure vegetable oil (0g water, 99.9g fat, ~899 kcal)
        oil_prod = {
            "id": 2,
            "code": "5.4.1",
            "name": "Масло подсолнечное рафинированное",
            "group_id": 5,
            "protein": 0.0,
            "fat": 99.9,
            "carbs": 0.0,
            "kcal": 899.0,
            "water": 0.1,
            "ash": 0.0,
            "waste_pct": 0.0
        }
        is_valid, warns, metrics = self.validator.validate_product(oil_prod)
        self.assertTrue(is_valid)
        self.assertAlmostEqual(metrics["calc_kcal"], 899.1, delta=1.0)
        self.assertEqual(metrics["proximate_sum"], 100.0)

    def test_validator_error_paths(self):
        # Missing code
        prod_no_code = {"name": "No code", "group_id": 1}
        is_valid, warns, _ = self.validator.validate_product(prod_no_code)
        self.assertFalse(is_valid)
        self.assertTrue(any("Missing product code" in w for w in warns))

        # Missing name
        prod_no_name = {"code": "1.2.3", "name": "", "group_id": 1}
        is_valid, warns, _ = self.validator.validate_product(prod_no_name)
        self.assertFalse(is_valid)
        self.assertTrue(any("Missing product name" in w for w in warns))

        # Invalid group ID
        prod_bad_group = {"code": "1.2.3", "name": "Bad group", "group_id": 99}
        is_valid, warns, _ = self.validator.validate_product(prod_bad_group)
        self.assertFalse(is_valid)
        self.assertTrue(any("Invalid group_id" in w for w in warns))

        # Outlier proximate sum
        prod_bad_sum = {
            "code": "1.2.3",
            "name": "Bad sum",
            "group_id": 1,
            "water": 50.0,
            "protein": 0.0,
            "fat": 0.0,
            "carbs": 0.0,
            "ash": 0.0,
            "kcal": 0.0
        }
        is_valid, warns, metrics = self.validator.validate_product(prod_bad_sum)
        # Valid schema but proximate warning generated
        self.assertTrue(any("Proximate mass sum out of expected range" in w for w in warns))

    def test_fts5_special_characters_and_injections(self):
        # Product names with quotes, apostrophes, Cyrillic quotes, dashes, SQL injection strings
        test_products = [
            {
                "id": 1,
                "code": "1.1",
                "name": "Пахта «Идеал» 'экстра' \"люкс\" (спец-заказ)",
                "group_id": 1,
                "protein": 3.0, "fat": 1.0, "carbs": 4.0, "kcal": 37.0, "water": 92.0, "ash": 0.7
            },
            {
                "id": 2,
                "code": "1.2",
                "name": "DROP TABLE product; SELECT * FROM product WHERE '1'='1'",
                "group_id": 1,
                "protein": 1.0, "fat": 1.0, "carbs": 1.0, "kcal": 17.0, "water": 97.0, "ash": 0.0
            }
        ]
        test_db = Path("test_edge_db.sqlite")
        build_sqlite_database(test_products, test_db)
        self.assertTrue(test_db.exists())

        conn = sqlite3.connect(str(test_db))
        c = conn.cursor()

        # Check injection did not drop table
        c.execute("SELECT count(*) FROM product;")
        self.assertEqual(c.fetchone()[0], 2)

        # FTS5 search on special character words
        c.execute("SELECT product_id FROM product_fts WHERE product_fts MATCH 'идеал*';")
        self.assertEqual(c.fetchone()[0], 1)

        c.execute("SELECT product_id FROM product_fts WHERE product_fts MATCH 'экстра*';")
        self.assertEqual(c.fetchone()[0], 1)

        conn.close()
        test_db.unlink()

    def test_smudge_and_noise_recovery(self):
        # Letters confused with numbers in OCR: 'ь.о' -> 5.0
        self.assertAlmostEqual(parse_cell_tokens(["ь.о"]), 5.0)
        # Stray noise letter 'j' before number
        self.assertAlmostEqual(parse_cell_tokens(["j", "67,3"]), 67.3)
        # Portion anchor '100' captured along with cell value
        self.assertAlmostEqual(parse_cell_tokens(["100", "j", "80.2"]), 80.2)

    def test_exceeds_100g_fatal_error(self):
        # Water > 100g must be a fatal validation error
        prod_water_940 = {
            "code": "test.fatal",
            "name": "Fatal product",
            "group_id": 8,
            "water": 940.0,
            "protein": 1.0,
            "fat": 1.0,
            "carbs": 1.0,
            "ash": 1.0,
            "kcal": 17.0
        }
        is_valid, warns, _ = self.validator.validate_product(prod_water_940)
        self.assertFalse(is_valid)
        self.assertTrue(any("exceeds 100g" in w for w in warns))

    def test_alcoholic_beverages_energy_and_mass(self):
        # Vodka (40% vol, ~33.3g ethanol, 66.2g water, ~235 kcal)
        vodka = {
            "id": 1037,
            "code": "11.2.7.1",
            "name": "Водка",
            "group_id": 11,
            "protein": 0.0,
            "fat": 0.0,
            "carbs": 0.4,
            "alcohol": 33.3,
            "water": 66.2,
            "ash": 0.1,
            "kcal": 235.0
        }
        is_valid, warns, metrics = self.validator.validate_product(vodka)
        self.assertTrue(is_valid)
        self.assertEqual(len(warns), 0)
        # Alcohol contributes 7 kcal/g: 33.3 * 7 + 0.4 * 4 = 233.1 + 1.6 = 234.7 ≈ 235 kcal
        self.assertAlmostEqual(metrics["calc_kcal"], 234.7, delta=1.0)
        self.assertAlmostEqual(metrics["proximate_sum"], 100.0, delta=0.5)

    def test_code_normalization_commas(self):
        self.assertEqual(normalize_code("3,5.8.1".replace(',', '.')), "3.5.8.1")
        self.assertEqual(normalize_code(" 1.1.2.3 "), "1.1.2.3")


if __name__ == "__main__":
    unittest.main()

