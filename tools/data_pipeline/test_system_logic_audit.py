"""Логика поиска и домены значений на боевой базе (без сети).

Проверка `get_measures_for_product` удалена вместе с конвейером
`tools/data_pipeline/skurikhin`: правило «составное блюдо не наследует меры
компонента» теперь обеспечивается на этапе сборки данных и проверяется в
`test_audit_regressions.TestDeployedDatabase
.test_recipe_dishes_do_not_carry_piece_measures`.
"""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "app" / "assets" / "db" / "reference.db"


def connect() -> sqlite3.Connection:
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True)


# Причины, по которым книга даёт ЭЦ без соответствующего БЖУ.
ENERGY_EXEMPT = {
    # 3 % уксусной кислоты: в таблице нет ни БЖУ, ни спирта, 9 ккал — за счёт
    # органических кислот, которые не входят ни в «У», ни в «Алкоголь»
    "12.1.3",
}


class TestSystemLogicAudit(unittest.TestCase):
    def test_dart_normalizer_contract(self):
        """Python-нормализация повторяет `_normalizeQuery` в репозитории."""
        source = (ROOT / "app/lib/data/repositories/product_repository.dart"
                  ).read_text(encoding="utf-8")
        self.assertIn("RegExp(r'[^a-zа-я0-9\\s]')", source)

    def test_fts_special_characters_are_literal_tokens(self):
        # Mirrors the Dart normalizer and executes MATCH against the shipped FTS index.
        with connect() as db:
            for query in ['курица -гриль "10%"', '"', '*', '() : -',
                          'AND OR NOT', 'яйцо*', 'сметана 10%', 'a:b',
                          'foo"bar', 'молоко 3.2']:
                clean = re.sub(
                    r'\s+', ' ',
                    re.sub(r'[^a-zа-я0-9\s]', ' ',
                           query.lower().replace('ё', 'е'))).strip()
                if not clean:
                    continue
                match = ' '.join(f'"{token}"*' for token in clean.split())
                with self.subTest(query=query):
                    db.execute('SELECT product_id FROM product_fts '
                               'WHERE product_fts MATCH ? LIMIT 60',
                               (match,)).fetchall()

    def test_shipped_macros_and_waste_are_in_engine_domain(self):
        with connect() as db:
            for column in ['protein', 'fat', 'carbs', 'waste_pct']:
                self.assertEqual(db.execute(
                    f'SELECT COUNT(*) FROM product WHERE "{column}"<0 OR '
                    f'"{column}">100').fetchone()[0], 0)

    def test_energy_is_consistent_with_macros(self):
        """ЭЦ книги согласуется с БЖУ (с учётом спирта и пищевых волокон).

        Классическая формула 4/9/4::

            ЭЦ = 4·Б + 9·Ж + 4·У

        В книге для алкогольных напитков учитывается ещё и этанол
        (7 ккал/г), а для продуктов, богатых полиолами и РПВ
        («Пектин (в т.ч. РПВ – 69,9)»), ЭЦ считается по этим
        дополнительным углеводам — их в таблице нет среди У.
        Отдельные точки с расширенной формулой::

            ЭЦ = 4·Б + 9·Ж + 4·У + 7·спирт + 4·РПВ

        Порционные строки правой страницы (см. `polish_products`) уже
        приведены к 100 г, поэтому расхождение должно оставаться
        умеренным.
        """
        with connect() as db:
            rows = db.execute(
                "SELECT code, name, protein, fat, carbs, kcal, alcohol, fiber "
                "FROM product WHERE source='skurikhin' AND kcal > 0"
            ).fetchall()
        outliers = []
        for code, name, protein, fat, carbs, kcal, alcohol, fiber in rows:
            if code in ENERGY_EXEMPT:
                continue
            base = 4.0 * protein + 9.0 * fat + 4.0 * carbs
            extended = base + 7.0 * (alcohol or 0.0) + 4.0 * (fiber or 0.0)
            if base <= 0 and extended <= 0:
                continue
            ok = any(0.45 <= kcal / value <= 2.2
                     for value in (base, extended) if value > 0)
            if not ok:
                outliers.append((code, name,
                                 round(kcal / max(base, 1e-9), 2)))
        self.assertEqual(outliers, [], f"расхождение ЭЦ: {outliers[:8]}")

    def test_skurikhin_priority_in_search(self):
        """Классические русские продукты находятся из Скурихина."""
        with connect() as db:
            for query in ['говядина', 'молоко', 'борщ', 'картофель']:
                clean = re.sub(r'[^a-zа-я0-9\s]', ' ',
                               query.lower().replace('ё', 'е')).strip()
                match = ' '.join(f'"{token}"*' for token in clean.split())
                row = db.execute(
                    "SELECT p.source FROM product_fts f "
                    "JOIN product p ON p.id = CAST(f.product_id AS INTEGER) "
                    "WHERE product_fts MATCH ? "
                    "ORDER BY CASE WHEN p.source='skurikhin' THEN 0 ELSE 1 END, "
                    "bm25(product_fts), LENGTH(p.name) LIMIT 1",
                    (match,)).fetchone()
                with self.subTest(query=query):
                    self.assertIsNotNone(row)
                    self.assertEqual(row[0], 'skurikhin')


if __name__ == '__main__':
    unittest.main()
