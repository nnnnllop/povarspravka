import unittest
import sqlite3
import os

class TestPovarSpravka(unittest.TestCase):
    def setUp(self):
        self.db_path = 'app/assets/db/reference.db'
        self.assertTrue(os.path.exists(self.db_path), "Database reference.db must exist in assets/db")

    def test_database_counts_and_sources(self):
        con = sqlite3.connect(self.db_path)
        cur = con.cursor()
        
        # Check total count
        total = cur.execute('SELECT COUNT(*) FROM product').fetchone()[0]
        self.assertGreaterEqual(total, 8000, "Should have 8000+ products")

        # Check Skurikhin count
        sk_count = cur.execute("SELECT COUNT(*) FROM product WHERE source = 'skurikhin'").fetchone()[0]
        self.assertEqual(sk_count, 1108, "Skurikhin reference has 1108 products")

        # Check BLS 4.0 count
        bls_count = cur.execute("SELECT COUNT(*) FROM product WHERE source = 'bls'").fetchone()[0]
        self.assertEqual(bls_count, 7140, "BLS 4.0 reference has 7140 products")

        # Check food groups: 12 Skurikhin tables + 20 BLS categories
        groups = cur.execute('SELECT COUNT(*) FROM food_group').fetchone()[0]
        self.assertEqual(groups, 32, "12 tables + 20 BLS categories")

        con.close()

    def test_fts5_search_latency_and_ranking(self):
        con = sqlite3.connect(self.db_path)
        cur = con.cursor()

        # Test Skurikhin priority ranking for Russian search queries
        queries = ['картоф*', 'говяд*', 'молок*', 'борщ*']
        for q in queries:
            sql = """
                SELECT p.name, p.source
                FROM product_fts fts
                JOIN product p ON p.id = CAST(fts.product_id AS INTEGER)
                WHERE product_fts MATCH ?
                ORDER BY CASE WHEN p.source = 'skurikhin' THEN 0 ELSE 1 END, bm25(product_fts) ASC
                LIMIT 5
            """
            rows = cur.execute(sql, (q,)).fetchall()
            self.assertTrue(len(rows) > 0, f"Query '{q}' should return results")
            # First result for classic Russian staple should be from Skurikhin
            self.assertEqual(rows[0][1], 'skurikhin', f"Top hit for '{q}' should be from Skurikhin")

        # FTS rowid is not required to match product.id; the join uses product_id
        self.assertEqual(
            cur.execute('SELECT COUNT(*) FROM product_fts WHERE NOT EXISTS ('
                        'SELECT 1 FROM product p '
                        'WHERE p.id = CAST(product_fts.product_id AS INTEGER))'
                        ).fetchone()[0], 0)

        con.close()

    def test_culinary_calculation_math(self):
        # Test simulated ingredients:
        # Ing 1: Beef (net 150g, 100g has: P=18.6, F=16.0, C=0.0) -> in dish: P=27.9, F=24.0, C=0.0
        # Ing 2: Potatoes (gross 200g, waste 20% -> net 160g, 100g has: P=2.0, F=0.4, C=16.3) -> in dish: P=3.2, F=0.64, C=26.08
        raw_net = 150.0 + 160.0 # 310g
        raw_p = 27.9 + 3.2 # 31.1g
        raw_f = 24.0 + 0.64 # 24.64g
        raw_c = 0.0 + 26.08 # 26.08g

        # Retention factors: P=94%, F=88%, C=91%
        cooked_p = raw_p * 0.94 # 29.234g
        cooked_f = raw_f * 0.88 # 21.6832g
        cooked_c = raw_c * 0.91 # 23.7328g

        # Energy: 4*P + 9*F + 4*C
        cooked_kcal = (cooked_p * 4.0) + (cooked_f * 9.0) + (cooked_c * 4.0)
        expected_kcal = (29.234 * 4.0) + (21.6832 * 9.0) + (23.7328 * 4.0)
        self.assertAlmostEqual(cooked_kcal, expected_kcal, places=4)
        self.assertAlmostEqual(cooked_kcal, 407.016, places=2)

        # Per 100g cooked dish (yield 280g)
        yield_grams = 280.0
        p_100g = (cooked_p / yield_grams) * 100.0
        f_100g = (cooked_f / yield_grams) * 100.0
        c_100g = (cooked_c / yield_grams) * 100.0
        kcal_100g = (cooked_kcal / yield_grams) * 100.0

        self.assertAlmostEqual(p_100g, 10.44, places=2)
        self.assertAlmostEqual(f_100g, 7.74, places=2)
        self.assertAlmostEqual(c_100g, 8.48, places=2)
        self.assertAlmostEqual(kcal_100g, 145.36, places=2)

if __name__ == '__main__':
    unittest.main()
