"""Integration tests for USDA pipeline end-to-end execution."""

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from tools.data_pipeline.usda.pipeline import run_usda_pipeline


class TestPipelineIntegration(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.out_db = Path(self.temp_dir.name) / "test_usda.db"
        self.manifest = Path(self.temp_dir.name) / "test_manifest.json"
        self.report = Path(self.temp_dir.name) / "test_report.json"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_run_pipeline_with_limit(self):
        result = run_usda_pipeline(
            output_db_path=self.out_db,
            manifest_path=self.manifest,
            report_path=self.report,
            limit=25,
            save_cache=False,
            merge_reference=False,
        )

        self.assertTrue(self.out_db.is_file())
        self.assertTrue(self.manifest.is_file())
        self.assertTrue(self.report.is_file())

        # Inspect manifest
        with self.manifest.open("r", encoding="utf-8") as f:
            manifest_data = json.load(f)
        self.assertIn("statistics", manifest_data)
        self.assertGreater(manifest_data["statistics"]["products"], 20)

        # Inspect canonical database schema
        conn = sqlite3.connect(str(self.out_db))
        cur = conn.cursor()
        prod_count = cur.execute("SELECT count(*) FROM product").fetchone()[0]
        fts_count = cur.execute("SELECT count(*) FROM product_fts").fetchone()[0]
        self.assertEqual(prod_count, fts_count)
        self.assertGreater(prod_count, 20)

        # Check sample item
        first_prod = cur.execute(
            "SELECT name, kcal, protein, fat, carbs FROM product LIMIT 1"
        ).fetchone()
        self.assertTrue(len(first_prod[0]) > 0)
        self.assertGreaterEqual(first_prod[1], 0.0)
        self.assertGreaterEqual(first_prod[2], 0.0)

        # Check synonym table
        syn_count = cur.execute("SELECT count(*) FROM synonym").fetchone()[0]
        self.assertGreater(syn_count, 0)

        conn.close()


if __name__ == "__main__":
    unittest.main()
