"""Unit tests for USDA translation and search normalization engine."""

import unittest
from tools.data_pipeline.usda.translator import (
    TranslationEngine,
    generate_synonyms,
    normalize_for_search,
)


class TestTranslator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = TranslationEngine()

    def test_normalize_for_search(self):
        self.assertEqual(normalize_for_search("Мёд натуральный, 100%!"), "мед натуральный 100")
        self.assertEqual(normalize_for_search("  Картофель--фри...  "), "картофель фри")
        self.assertEqual(normalize_for_search("Milk 3.2%"), "milk 3 2")
        self.assertEqual(normalize_for_search(""), "")

    def test_translate_category(self):
        self.assertEqual(self.engine.translate_category("Apples"), "Яблоки")
        self.assertEqual(self.engine.translate_category("Ground beef"), "Говяжий фарш")
        self.assertEqual(self.engine.translate_category("Milk, whole"), "Молоко цельное (3.2-3.5%)")

    def test_translate_segment(self):
        self.assertEqual(self.engine.translate_segment("cooked"), "вареный / готовый")
        self.assertEqual(self.engine.translate_segment("raw"), "сырой")
        self.assertEqual(self.engine.translate_segment("baked"), "запеченный")
        self.assertEqual(self.engine.translate_segment("NFS"), "не уточнено")
        self.assertEqual(self.engine.translate_segment("without salt"), "без соли")

    def test_translate_food_description(self):
        beef_trans = self.engine.translate_food_description("Beef, ground, 80% lean meat / 20% fat, raw")
        self.assertIn("Говяжий фарш", beef_trans)

        chicken_trans = self.engine.translate_food_description("Chicken, breast, meat only, cooked, roasted")
        self.assertTrue("Курица" in chicken_trans or "Куриная" in chicken_trans)
        self.assertIn("грудка", chicken_trans)

        potato_trans = self.engine.translate_food_description("Potatoes, baked, flesh and skin, without salt")
        self.assertIn("Картофель", potato_trans)
        self.assertIn("без соли", potato_trans)

    def test_generate_synonyms(self):
        syns = generate_synonyms("Картофель запеченный", "Potatoes, baked", "Белый картофель")
        # Check original English is included
        self.assertIn("Potatoes, baked", syns)
        # Check Russian culinary colloquialisms
        self.assertTrue(any("картошка" in s.lower() for s in syns))
        # Check category is included
        self.assertIn("Белый картофель", syns)

    def test_translate_measure_description(self):
        self.assertEqual(self.engine.translate_measure_description("1 cup"), "1 стакан")
        self.assertEqual(self.engine.translate_measure_description("1 slice"), "1 ломтик")
        self.assertEqual(
            self.engine.translate_measure_description("Quantity not specified"),
            "Стандартная порция",
        )


if __name__ == "__main__":
    unittest.main()
