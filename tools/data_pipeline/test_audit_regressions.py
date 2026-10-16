"""Regression checks for the audit migration and culinary translations."""
import unittest, sqlite3, tempfile
from pathlib import Path
from tools.data_pipeline.skurikhin.config import KNOWN_CANONICAL_NAMES, SKURIKHIN_SYNONYMS
from tools.data_pipeline.usda.translator import TranslationEngine, generate_synonyms

class TestAuditRegressions(unittest.TestCase):
    def test_legume_canonical_names(self):
        self.assertEqual(KNOWN_CANONICAL_NAMES['7.1.7'], 'Соя, зерно')
        self.assertEqual(KNOWN_CANONICAL_NAMES['7.1.11'], 'Фасоль, зерно')
        self.assertEqual(KNOWN_CANONICAL_NAMES['7.1.12'], 'Фасоль (стручок)')

    def test_synonyms_map_to_real_foods(self):
        self.assertIn(('6.6.4','гречка'),SKURIKHIN_SYNONYMS)
        self.assertIn(('6.6.4','ядрица'),SKURIKHIN_SYNONYMS)
        self.assertIn(('6.6.3','продел'),SKURIKHIN_SYNONYMS)
        self.assertNotIn(('6.2.2.1','гречка'),SKURIKHIN_SYNONYMS)
        self.assertIn(('8.1.6.6','помидоры'),SKURIKHIN_SYNONYMS)
        self.assertNotIn(('8.1.6.30','помидоры'),SKURIKHIN_SYNONYMS)

    def test_cached_culinary_translations(self):
        with tempfile.TemporaryDirectory() as temp:
            engine=TranslationEngine(cache_file=Path(temp)/'missing.json',db_cache=Path(temp)/'missing.db')
            fixtures=[('Turkey, dark meat','Турция, темное мясо','Индейка, темное мясо'),
                ('Turkey, drumstick','Барабанная палочка турция','Голень индейки'),
                ('Chicken, retail parts','Курица, запчасти для розничной торговли','Курица, кулинарные отрубы/части тушки'),
                ('Fish, drum, raw','Рыба, голень, сырая','Рыба семейства горбылевых (горбыль), сырая')]
            for en,ru,expected in fixtures:
                with self.subTest(en=en):
                    engine.cache[en]=ru
                    self.assertEqual(engine.translate_food_description(en),expected)
                    self.assertEqual(engine.post_process_russian(en,expected),expected)
            synonyms=generate_synonyms('Барабанная палочка турция','Turkey, drumstick')
            self.assertFalse(any('турция' in value.lower() or 'барабанная' in value.lower() for value in synonyms))
            self.assertTrue(any('индейк' in value.lower() for value in synonyms))

    def test_deployed_database(self):
        root=Path(__file__).resolve().parents[2]
        db=root/'tools/data_pipeline/output/reference.db'
        self.assertEqual(db.read_bytes(),(root/'app/assets/db/reference.db').read_bytes())
        conn=sqlite3.connect(db)
        try:
            self.assertEqual(conn.execute('select source,count(*) from product group by source').fetchall(),[('skurikhin',1103),('usda',8180)])
            expected={'7.1.7':('Соя, зерно',34.9,17.3,17.3,364.0),'7.1.11':('Фасоль, зерно',21.0,2.0,47.0,298.0),'7.1.12':('Фасоль (стручок)',2.5,0.3,3.0,23.0)}
            for code,values in expected.items():
                self.assertEqual(conn.execute('select name,protein,fat,carbs,kcal from product where code=?',(code,)).fetchone(),values)
            self.assertEqual(conn.execute('''select p.code,p.name from product_fts f join product p on p.id=cast(f.product_id as integer) where product_fts match '"гречка"*' limit 1''').fetchone(),('6.6.4','Гречиха крупа ядрица'))
            self.assertEqual(conn.execute("select count(*) from product where name like '%Турция%' or name like '%Рыба, голень%'").fetchone()[0],0)
            self.assertEqual(conn.execute('select count(*) from product_fts where rowid!=cast(product_id as integer)').fetchone()[0],0)
            self.assertEqual(conn.execute('pragma integrity_check').fetchone()[0],'ok')
            import re
            banned_rx = re.compile(r'\bтурци\w*|барабанн\w*\s+палоч\w*|бобы,\s*окунь', re.I)
            fts_banned = [row[0] for row in conn.execute('select c2 from product_fts_content').fetchall() if row[0] and banned_rx.search(row[0])]
            self.assertEqual(len(fts_banned), 0, f"Found {len(fts_banned)} banned terms in FTS: {fts_banned[:5]}")
            self.assertEqual(conn.execute('select count(*) from product_fts where product_fts match \'"барабанная палочка"\'').fetchone()[0], 0)
            self.assertGreaterEqual(conn.execute('select count(*) from product_fts where product_fts match \'"голень"*\'').fetchone()[0], 35)
        finally:conn.close()
