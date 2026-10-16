"""Unit tests for USDA macronutrient validation engine."""

import unittest
from tools.data_pipeline.usda.validator import DatasetValidator, validate_food_item


class TestValidator(unittest.TestCase):
    def setUp(self):
        self.valid_food = {
            "fdcId": 12345,
            "description": "Chicken breast, cooked",
            "foodNutrients": [
                {"nutrient": {"number": "203", "name": "Protein"}, "amount": 31.0},
                {"nutrient": {"number": "204", "name": "Total lipid"}, "amount": 3.6},
                {"nutrient": {"number": "205", "name": "Carbohydrate"}, "amount": 0.0},
                {"nutrient": {"number": "208", "name": "Energy"}, "amount": 165.0},
                {"nutrient": {"number": "255", "name": "Water"}, "amount": 65.0},
                {"nutrient": {"number": "291", "name": "Fiber"}, "amount": 0.0},
            ],
        }

    def test_valid_item_passes(self):
        result = validate_food_item(self.valid_food)
        self.assertTrue(result.is_valid)
        self.assertEqual(len(result.errors), 0)
        self.assertEqual(result.macros["protein"], 31.0)
        self.assertEqual(result.macros["fat"], 3.6)
        self.assertEqual(result.macros["carbs"], 0.0)
        self.assertEqual(result.macros["kcal"], 165.0)

    def test_missing_fdc_id(self):
        food = dict(self.valid_food)
        del food["fdcId"]
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertIn("Missing fdcId", result.errors[0])

    def test_empty_description(self):
        food = dict(self.valid_food)
        food["description"] = "   "
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertIn("Empty description", result.errors[0])

    def test_missing_core_macronutrient(self):
        food = dict(self.valid_food)
        # remove protein
        food["foodNutrients"] = [
            n for n in self.valid_food["foodNutrients"]
            if n["nutrient"]["number"] != "203"
        ]
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertTrue(any("protein" in err.lower() for err in result.errors))

    def test_out_of_bounds_macro(self):
        food = dict(self.valid_food)
        food["foodNutrients"] = [
            {"nutrient": {"number": "203"}, "amount": 105.0},  # > 100g
            {"nutrient": {"number": "204"}, "amount": 5.0},
            {"nutrient": {"number": "205"}, "amount": 0.0},
            {"nutrient": {"number": "208"}, "amount": 200.0},
        ]
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertTrue(any("Protein value out of bounds" in err for err in result.errors))

    def test_out_of_bounds_energy(self):
        food = dict(self.valid_food)
        food["foodNutrients"] = [
            {"nutrient": {"number": "203"}, "amount": 10.0},
            {"nutrient": {"number": "204"}, "amount": 10.0},
            {"nutrient": {"number": "205"}, "amount": 10.0},
            {"nutrient": {"number": "208"}, "amount": 999.0},  # > 950 kcal
        ]
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertTrue(any("Energy value out of bounds" in err for err in result.errors))

    def test_macro_sum_exceeds_maximum(self):
        food = dict(self.valid_food)
        food["foodNutrients"] = [
            {"nutrient": {"number": "203"}, "amount": 40.0},
            {"nutrient": {"number": "204"}, "amount": 40.0},
            {"nutrient": {"number": "205"}, "amount": 40.0},  # sum = 120g > 105g
            {"nutrient": {"number": "208"}, "amount": 680.0},
        ]
        result = validate_food_item(food)
        self.assertFalse(result.is_valid)
        self.assertTrue(any("Macro sum exceeds" in err for err in result.errors))

    def test_dataset_validator_summary(self):
        validator = DatasetValidator()
        validator.validate(self.valid_food)

        bad_food = dict(self.valid_food)
        bad_food["description"] = ""
        validator.validate(bad_food)

        summary = validator.summary()
        self.assertEqual(summary["total_evaluated"], 2)
        self.assertEqual(summary["passed"], 1)
        self.assertEqual(summary["rejected"], 1)
        self.assertEqual(summary["pass_rate_pct"], 50.0)

    def test_banned_translations_gate(self):
        import sqlite3, re, os
        db_path = os.path.join("app", "assets", "db", "reference.db")
        if os.path.exists(db_path):
            with sqlite3.connect(db_path) as c:
                for table, sql in [
                    ("product", "SELECT id, code, name FROM product WHERE source='usda'"),
                    ("synonym", "SELECT s.id, p.code, s.synonym FROM synonym s JOIN product p ON p.id=s.product_id WHERE p.source='usda'")
                ]:
                    for ident, code, text in c.execute(sql):
                        self.assertFalse(
                            bool(re.search(r'\bтурци\w*|барабанн\w*\s+палоч\w*|бобы,\s*окунь', text.casefold())),
                            f"Banned translation in {table} ({code}): {text}"
                        )


if __name__ == "__main__":
    unittest.main()

