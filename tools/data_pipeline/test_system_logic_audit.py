"""Real SQLite FTS5 and source matching regression checks (no network)."""
from pathlib import Path
import re
import sqlite3
import unittest
from tools.data_pipeline.skurikhin.appendices_parser import get_measures_for_product
ROOT = Path(__file__).resolve().parents[2]

class TestSystemLogicAudit(unittest.TestCase):
    def test_compound_dish_does_not_inherit_component_measures(self):
        self.assertEqual(get_measures_for_product('Яйцо под майонезом', {'майонез': {'ложка': 15}}, {}), [])
        self.assertEqual(get_measures_for_product('Мука соевая', {'мука': {'стакан': 160}}, {}), [])
        self.assertEqual(get_measures_for_product('Майонез', {'майонез': {'ложка': 15}}, {}), [('ложка', 15)])

    def test_exact_piece_binding(self):
        self.assertEqual(get_measures_for_product('Бананы', {}, {'бананы': 72}), [('1 шт.', 72)])
        self.assertEqual(get_measures_for_product('Пирог с бананами', {}, {'бананы': 72}), [])

    def test_fts_special_characters_are_literal_tokens(self):
        # Mirrors the Dart normalizer and executes MATCH against the shipped FTS index.
        source = (ROOT/'app/lib/data/repositories/product_repository.dart').read_text(encoding='utf-8')
        self.assertIn("RegExp(r'[^a-zа-я0-9\\s]')", source)
        with sqlite3.connect(f'file:{ROOT / "app/assets/db/reference.db"}?mode=ro', uri=True) as db:
            for query in ['курица -гриль "10%"', '"', '*', '() : -', 'AND OR NOT', 'яйцо*', 'сметана 10%', 'a:b', 'foo"bar']:
                clean = re.sub(r'\s+', ' ', re.sub(r'[^a-zа-я0-9\s]', ' ', query.lower().replace('ё','е'))).strip()
                if not clean:
                    continue
                match = ' '.join(f'"{token}"*' for token in clean.split())
                with self.subTest(query=query):
                    db.execute('SELECT product_id FROM product_fts WHERE product_fts MATCH ? LIMIT 60', (match,)).fetchall()

    def test_shipped_macros_and_waste_are_in_engine_domain(self):
        with sqlite3.connect(f'file:{ROOT / "app/assets/db/reference.db"}?mode=ro', uri=True) as db:
            for column in ['protein','fat','carbs','waste_pct']:
                self.assertEqual(db.execute(f'SELECT COUNT(*) FROM product WHERE "{column}"<0 OR "{column}">100').fetchone()[0], 0)

if __name__ == '__main__': unittest.main()
