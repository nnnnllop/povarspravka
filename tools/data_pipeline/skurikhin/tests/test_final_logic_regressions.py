"""Regression tests for the FINAL_LOGIC audit data fixes (2026-10-21).

Every expectation below cites the printed page of Скурихин (2002) that was read
directly from the PDF.  ``page`` is the printed book page; the PDF page is
``page + 1``.
"""
import sqlite3
import unittest

import pymupdf

from tools.data_pipeline.skurikhin.appendices_parser import (
    find_waste_percentage,
    parse_appendix_1,
)
from tools.data_pipeline.skurikhin.config import DEFAULT_PDF_PATH, PROJECT_ROOT

DB_PATH = PROJECT_ROOT / "app" / "assets" / "db" / "reference.db"


class TestWastePercentages(unittest.TestCase):
    """Appendix 1 (printed p. 202) is the only source of cold-processing waste."""

    @classmethod
    def setUpClass(cls):
        if not DEFAULT_PDF_PATH.exists():
            raise unittest.SkipTest("Skurikhin PDF is not available")
        cls.doc = pymupdf.open(str(DEFAULT_PDF_PATH))
        cls.waste = parse_appendix_1(cls.doc)

    def test_potato_is_28_percent(self):
        # Appendix 1, printed p. 202: "Картофель ... 28".
        self.assertEqual(find_waste_percentage("Картофель", self.waste), 28.0)

    def test_chicken_categories_are_distinct(self):
        # Appendix 1, printed p. 204: "Куры 1 категории 39/25", "Куры II категории 47/30".
        self.assertEqual(find_waste_percentage("Куры I категории", self.waste), 39.0)
        self.assertEqual(find_waste_percentage("Куры II категории", self.waste), 47.0)

    def test_grain_qualifier_is_stripped(self):
        # Appendix 1, printed p. 201: "Соя 2".
        self.assertEqual(find_waste_percentage("Соя, зерно", self.waste), 2.0)

    def test_bean_pod_stays_in_the_map(self):
        # Appendix 1, printed p. 202: "Фасоль (стручок) 10".
        self.assertEqual(find_waste_percentage("Фасоль (стручок)", self.waste), 10.0)

    def test_prepared_dishes_get_no_raw_waste(self):
        for dish in ("Суп картофельный", "Котлеты картофельные", "Масло сливочное",
                     "Сыр Российский", "Картофель отварной",
                     "Консервы рыбные «Тунец натуральный»", "Фасоль консервы",
                     "Шоколад полугорький"):
            self.assertIsNone(find_waste_percentage(dish, self.waste), dish)

    def test_ocr_border_noise_is_stripped(self):
        # Appendix 1, printed p. 205: "[Тунец ... 48" — the leading table border
        # must not hide the row.
        self.assertEqual(find_waste_percentage("Тунец", self.waste), 48.0)

    def test_egg_shell_waste_is_not_lost(self):
        # Appendix 1, printed p. 204: "Яйца куриные I категории 13",
        # "Яйца перепелиные 8".  Product names are singular, so the exact row
        # name never matched and the shell waste silently disappeared.
        self.assertEqual(find_waste_percentage("Яйцо куриное", self.waste), 13.0)
        self.assertEqual(find_waste_percentage("Яйцо перепелиное", self.waste), 8.0)


class TestDatabaseMatchesBook(unittest.TestCase):
    """The shipped catalogue must carry the values printed in the book."""

    @classmethod
    def setUpClass(cls):
        if not DB_PATH.exists():
            raise unittest.SkipTest("reference.db is not built")
        cls.con = sqlite3.connect(str(DB_PATH))
        cls.con.row_factory = sqlite3.Row

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    def row(self, code):
        return self.con.execute(
            "SELECT * FROM product WHERE source='skurikhin' AND code=?", (code,)
        ).fetchone()

    def test_potato_row(self):
        # Table 8, printed p. 134: 2.0 / 0.4 / 16.3; Appendix 1: 28 %.
        p = self.row("8.1.4.1")
        self.assertEqual((p["protein"], p["fat"], p["carbs"], p["kcal"]),
                         (2.0, 0.4, 16.3, 77.0))
        self.assertEqual(p["waste_pct"], 28.0)

    def test_energy_matches_printed_value(self):
        # (code, printed ЭЦ) read from Table 2 of the book.
        expected = {
            "1.4.3.5": 345.0, "1.4.3.6": 319.0, "1.6.1.1": 315.0,
            "3.3.12": 220.0, "3.3.13": 275.0, "3.3.14": 301.0,
            "3.5.6.1": 261.0, "3.5.6.2": 281.0,
            "3.6.1.8": 240.0, "3.6.1.9": 302.0, "3.6.1.10": 277.0,
            "3.6.1.11": 234.0, "3.6.1.12": 308.0, "3.6.1.13": 216.0,
            "3.6.1.14": 187.0, "3.6.2.1": 215.0, "3.6.2.3": 322.0,
            "3.6.3.1": 226.0, "3.6.3.2": 261.0, "3.6.3.4": 234.0,
            "6.1.3.5.15": 396.0,
        }
        for code, kcal in expected.items():
            p = self.row(code)
            self.assertIsNotNone(p, code)
            self.assertEqual(p["kcal"], kcal, code)

    def test_chicken_categories(self):
        self.assertEqual(self.row("3.1.15.7")["waste_pct"], 39.0)
        self.assertEqual(self.row("3.1.15.8")["waste_pct"], 47.0)

    def test_egg_protein_and_waste_match_printed_page(self):
        # Table 2, printed p. 50: "Яйцо целое 12,7 / 11,5 / 0,7, 157 ккал";
        # Appendix 1, p. 204: shell waste 13 %.  The OCR text layer reads
        # "12./" and used to yield 12.0.
        egg = self.row("2.1.1")
        self.assertEqual((egg["protein"], egg["fat"], egg["carbs"], egg["kcal"]),
                         (12.7, 11.5, 0.7, 157.0))
        self.assertEqual(egg["waste_pct"], 13.0)
        boiled = self.row("2.1.2")
        self.assertEqual(boiled["protein"], 12.7)
        self.assertEqual(self.row("2.5.1")["waste_pct"], 8.0)
        # A prepared egg salad must not inherit the raw "Салат" 20 %.
        self.assertIsNone(self.row("2.1.5")["waste_pct"])

    def test_ocr_digit_loss_is_corrected(self):
        # Printed p. 128: "Салат" 1,5 % protein (OCR: 5.0).
        self.assertEqual(self.row("8.1.1.4")["protein"], 1.5)
        # Printed p. 144/145: 0,9 protein, 66 kcal.
        self.assertEqual(self.row("8.1.6.9")["protein"], 0.9)
        self.assertEqual(self.row("8.1.6.9")["kcal"], 66.0)
        # Printed p. 184/185: 0,5 fat, 7 kcal.
        self.assertEqual(self.row("11.1.8.2")["fat"], 0.5)
        self.assertEqual(self.row("11.1.8.2")["kcal"], 7.0)

    def test_kilka_fish_and_dish_are_distinct(self):
        # Printed p. 80: 4.1.1.1 is the raw fish; 4.1.1.5 is a prepared dish.
        fish = self.row("4.1.1.1")
        dish = self.row("4.1.1.5")
        self.assertEqual(fish["name"], "Килька балтийская")
        self.assertEqual(fish["waste_pct"], 46.0)
        self.assertEqual(dish["name"],
                         "Килька соленая с картофелем и маслом по 1-100")
        self.assertIsNone(dish["waste_pct"])

    def test_usda_half_is_intact(self):
        counts = dict(self.con.execute(
            "SELECT source, count(*) FROM product GROUP BY source").fetchall())
        self.assertEqual(counts, {"skurikhin": 1103, "usda": 8180})
        self.assertEqual(
            self.con.execute("PRAGMA integrity_check").fetchone()[0], "ok")

    def test_search_still_finds_potato(self):
        hit = self.con.execute(
            """SELECT p.code FROM product_fts f JOIN product p
               ON p.id=cast(f.product_id as integer)
               WHERE product_fts MATCH '"картошка"*' LIMIT 1""").fetchone()
        self.assertEqual(hit[0], "8.1.4.1")


if __name__ == "__main__":
    unittest.main()
