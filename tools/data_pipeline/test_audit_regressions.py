"""Регрессии боевой базы `app/assets/db/reference.db` (Скурихин + BLS 4.0).

Заменяет прежние проверки конвейеров `tools/data_pipeline/skurikhin` и
`tools/data_pipeline/usda`: сами конвейеры удалены, но инварианты, которые они
защищали (канонические названия, кулинарные синонимы, отсутствие мусорных
переводов), теперь проверяются на итоговой базе.
"""
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEPLOYED = ROOT / "app" / "assets" / "db" / "reference.db"
MIRROR = ROOT / "tools" / "data_pipeline" / "output" / "reference.db"

# Продукты, названия которых когда-то ломались разбором («Род. Вид»).
CANONICAL_NAMES = {
    "7.1.7": "Соя, зерно",
    "7.1.11": "Фасоль, зерно",
    "7.1.12": "Фасоль (стручок)",
    "6.6.4": "Крупа гречневая ядрица",
    "6.6.3": "Крупа гречневая продел",
    "8.1.6.6": "Томаты (грунтовые)",
    "8.1.5.12": "Свекла",
    "2.1.1": "Яйцо куриное",
}

# Кулинарные синонимы, которые обязаны находиться поиском.
SYNONYMS = {
    "гречка": "6.6.4",
    "ядрица": "6.6.4",
    "продел": "6.6.3",
    "помидоры": "8.1.6.6",
    "картошка": "8.1.4.1",
    "геркулес": "6.4.5",
}


def connect() -> sqlite3.Connection:
    return sqlite3.connect(f"file:{DEPLOYED}?mode=ro", uri=True)


def search(db: sqlite3.Connection, query: str, limit: int = 10,
           is_dish: bool | None = None):
    """FTS5-поиск ровно тем же ранжированием, что в `ProductRepository`.

    Раньше здесь была своя копия SQL — она разъехалась с боевым запросом и
    тест не ловил дефект H3 («сыр» → «Сырники», «печень» → «Печенье»).
    Теперь вызывается `build_reference_db.search`.

    `is_dish`: `False` — только сырьё (режим калькулятора), `True` — только
    готовые блюда, `None` — все.
    """
    from tools.data_pipeline.build_reference_db import search as _search
    return [(code, name)
            for code, name, _source in _search(DEPLOYED, query, limit, is_dish)]


class TestDeployedDatabase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_mirror_matches_deployed_asset(self):
        self.assertTrue(DEPLOYED.exists(), "нет app/assets/db/reference.db")
        self.assertEqual(MIRROR.read_bytes(), DEPLOYED.read_bytes())

    def test_integrity_and_sources(self):
        self.assertEqual(
            self.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        counts = dict(self.db.execute(
            "SELECT source, COUNT(*) FROM product GROUP BY source").fetchall())
        # `supplement` — приправы и питьевая вода, которых нет ни в книге,
        # ни в BLS, но без которых нельзя собрать рецепт (дефект M5).
        # Этап 6 (дефект D11) добавил пряности, отсутствовавшие в обоих
        # источниках: кориандр (кинза), орегано (душица), паприка, тимьян
        # (чабрец), розмарин, куркума, имбирь молотый. Перец чёрный и сушёный
        # базилик в BLS уже были — им розданы синонимы, дублей не заводим.
        self.assertEqual(counts,
                         {"skurikhin": 1108, "bls": 7140, "supplement": 13})

    def test_id_ranges_and_groups(self):
        """Скурихин 1…1108 (группы 1…12), BLS 10001… (группы 101+)."""
        self.assertEqual(
            self.db.execute("SELECT MIN(id), MAX(id) FROM product "
                            "WHERE source='skurikhin'").fetchone(), (1, 1108))
        self.assertEqual(
            self.db.execute("SELECT MIN(id), MAX(id) FROM product "
                            "WHERE source='bls'").fetchone(), (10001, 17140))
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM product WHERE "
            "(source='skurikhin' AND (group_id < 1 OR group_id > 12)) OR "
            "(source='bls' AND group_id < 101)").fetchone()[0], 0)
        # у продуктов BLS нет страницы книги
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM product WHERE source='bls' "
            "AND page_num IS NOT NULL").fetchone()[0], 0)

    def test_canonical_names(self):
        for code, expected in CANONICAL_NAMES.items():
            with self.subTest(code=code):
                self.assertEqual(self.db.execute(
                    "SELECT name FROM product WHERE code=?", (code,)
                ).fetchone(), (expected,))

    def test_no_technical_section_prefixes(self):
        """Названия не начинаются с технического префикса раздела.

        «Род. Вид» («Корнеплоды. Свекла») — артефакт разбора таблицы.
        Название вида без точки («Кукуруза сырая») — нормальное.
        """
        prefixes = ("Корнеплоды.", "Овощи листовые.", "Овощи луковые.",
                    "Бобовые.", "Орехи.", "Семена масличные.", "Сельдевые.",
                    "Скумбриевые.", "Гречиха.", "Рис.", "Ячмень.",
                    "Кукуруза.", "Кукуруза (в среднем).")
        for prefix in prefixes:
            with self.subTest(prefix=prefix):
                self.assertEqual(self.db.execute(
                    "SELECT COUNT(*) FROM product WHERE name LIKE ?",
                    (prefix + "%",)).fetchone()[0], 0,
                    f"префикс {prefix!r} остался в названиях")

    def test_nutrients_use_food_composition_units(self):
        """У яйца и сметаны значения в тех же единицах, что ждёт Dart-модель."""
        # Яйцо куриное: Na 134 мг, A 250 мкг, β-каротин 60 мкг
        nutrients = dict(self.db.execute(
            "SELECT v.nutrient_code, v.value FROM nutrient_value v "
            "JOIN product p ON p.id = v.product_id WHERE p.code='2.1.1'"
        ).fetchall())
        self.assertEqual(nutrients["NA"], 134.0)
        self.assertEqual(nutrients["RETOL"], 250.0)
        self.assertEqual(nutrients["CARTB"], 60.0)

    def test_measures_for_base_products(self):
        """Яйца: штучные меры; сметаны: стаканы и ложки."""
        def measures(code):
            return dict(self.db.execute(
                "SELECT m.name, m.grams FROM measure m "
                "JOIN product p ON p.id = m.product_id WHERE p.code=?",
                (code,)).fetchall())

        self.assertEqual(measures("2.1.1"),
                         {"1 шт. (1 категория, нетто)": 47.0})
        self.assertEqual(measures("2.5.1"), {"1 шт. (нетто)": 9.0})
        # Канонические подписи мер (дефект L9): без пояснений в скобках
        self.assertEqual(measures("1.3.2.12"), {
            "стакан 250 мл": 250.0,
            "стакан 200 мл": 200.0,
            "столовая ложка": 20.0,
            "чайная ложка": 9.0,
        })

    def test_recipe_dishes_do_not_carry_piece_measures(self):
        """Рецептурным блюдам не приписываются меры «1 шт.» сырья."""
        rows = self.db.execute(
            "SELECT p.code, m.name FROM product p "
            "JOIN measure m ON m.product_id = p.id "
            "WHERE p.name LIKE '%по 1-%' AND m.name LIKE '%шт%'"
        ).fetchall()
        self.assertEqual(rows, [])

    def test_waste_within_percent_domain(self):
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM product WHERE waste_pct < 0 OR "
            "waste_pct > 100").fetchone()[0], 0)
        # «молоко в стакане 250 г» — это мера, а не 250 % отходов
        self.assertEqual(self.db.execute(
            "SELECT waste_pct FROM product WHERE code='10.11.6'").fetchone(),
            (0.0,))

    def test_culinary_synonyms_are_searchable(self):
        for query, code in SYNONYMS.items():
            with self.subTest(query=query):
                hits = [row[0] for row in search(self.db, query, limit=50)]
                self.assertIn(code, hits)

    def test_no_broken_machine_translations(self):
        banned = re.compile(
            r"\bтурци\w*|барабанн\w*\s+палоч\w*|бобы,\s*окунь", re.I)
        rows = self.db.execute("SELECT code, name FROM product").fetchall()
        hits = [(code, name) for code, name in rows if banned.search(name)]
        self.assertEqual(hits, [], f"мусорные названия: {hits[:5]}")

    def test_fts_index_covers_every_product(self):
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM product_fts").fetchone()[0],
            self.db.execute("SELECT COUNT(*) FROM product").fetchone()[0])
        self.assertEqual(self.db.execute(
            "SELECT COUNT(*) FROM product_fts f WHERE NOT EXISTS ("
            "SELECT 1 FROM product p WHERE p.id = CAST(f.product_id AS "
            "INTEGER))").fetchone()[0], 0)


class TestStage5Regressions(unittest.TestCase):
    """Инварианты, закрывающие пункты аудита 7,3/10 (этап 5)."""

    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def _nutrients(self, code: str) -> dict[str, float]:
        return dict(self.db.execute(
            "SELECT v.nutrient_code, v.value FROM nutrient_value v "
            "JOIN product p ON p.id = v.product_id WHERE p.code=?",
            (code,)).fetchall())

    # ---- C1/C2: сдвиг столбцов «C» и «НЭ» на «ЭЦ» ----------------------
    def test_vitamin_c_and_niacin_eq_never_equal_energy(self):
        """C и НЭ не могут совпадать с ЭЦ: это признак сдвига колонок.

        В книге на части страниц 15 значений вместо 16 (столбец «C»
        физически отсутствует), из-за чего прежний разбор приписывал ЭЦ
        витамину C и ниациновому эквиваленту.
        """
        rows = self.db.execute(
            "SELECT p.code, p.name FROM product p "
            "LEFT JOIN nutrient_value c ON c.product_id = p.id "
            "  AND c.nutrient_code = 'VITC' "
            "LEFT JOIN nutrient_value n ON n.product_id = p.id "
            "  AND n.nutrient_code = 'NIAEQ' "
            "WHERE p.source = 'skurikhin' AND p.kcal > 3 AND ("
            "  c.value = p.kcal OR n.value = p.kcal)").fetchall()
        self.assertEqual(rows, [])

    def test_table5_vitamins_are_in_milligram_scale(self):
        """Таблица 5: C ≤ 10 мг, НЭ ≤ 5 мг — иначе это ЭЦ."""
        rows = self.db.execute(
            "SELECT p.code, v.nutrient_code, v.value FROM product p "
            "JOIN nutrient_value v ON v.product_id = p.id "
            "WHERE p.code LIKE '5.%' AND ("
            "  (v.nutrient_code = 'VITC' AND v.value > 10) OR "
            "  (v.nutrient_code = 'NIAEQ' AND v.value > 5))").fetchall()
        self.assertEqual(rows, [])

    # ---- C3: вино ------------------------------------------------------
    def test_dry_wine_row_is_intact(self):
        """«Виноградное сухое»: спирт 8,8 г, ЭЦ 64 ккал (а не 64 г спирта)."""
        row = self.db.execute(
            "SELECT alcohol, kcal FROM product WHERE code='11.2.2.1'").fetchone()
        self.assertAlmostEqual(row[0], 8.8, places=1)
        self.assertAlmostEqual(row[1], 64.0, places=1)

    def test_beverages_have_no_waste(self):
        """У напитков нет отходов: «вино» не чистится и не варится."""
        rows = self.db.execute(
            "SELECT code, waste_pct FROM product WHERE code LIKE '11.%' "
            "AND waste_pct <> 0").fetchall()
        self.assertEqual(rows, [])

    # ---- C4: холестерин и РЭ -------------------------------------------
    def test_liver_cholesterol_and_no_phantom_rae(self):
        """Холестерин хранится в `product.chol`, а не в `nutrient_value`."""
        row = self.db.execute(
            "SELECT chol FROM product WHERE code='5.3.1'").fetchone()
        self.assertAlmostEqual(row[0], 570.0, places=1)
        # РЭ 25000 мкг без ретинола и каротина — артефакт скана
        rae = self.db.execute(
            "SELECT v.value FROM nutrient_value v JOIN product p "
            "ON p.id=v.product_id WHERE p.code='5.3.1' "
            "AND v.nutrient_code='VITA_RAE'").fetchone()
        self.assertIsNone(rae, "у рыбьего жира не должно быть РЭ 25000")

    def test_retinol_equivalent_needs_a_source(self):
        """РЭ без ретинола и каротина — артефакт скана (дефект C4).

        Тождество «РЭ = ретинол + каротин/6» в книге выполняется не строго
        (РЭ включает и другие каротиноиды), поэтому проверяется только одно
        жёсткое условие: если РЭ задан, у продукта должен быть хотя бы один
        из источников — ретинол или β-каротин.

        Дефект D16: ретинол BLS теперь импортируется (`RETOL`), поэтому
        проверка идёт по ОБОИМ источникам. Исключение — 20 официальных строк
        BLS, где витамин A задан только РЭ (крипто-/α-каротин); они
        перечислены в `BLS_VITA_WITHOUT_RETINOL` и здесь же сверяются, чтобы
        список не разошёлся с данными молча.
        """
        from tools.data_pipeline.build_reference_db import (
            BLS_VITA_WITHOUT_RETINOL)

        rows = self.db.execute("""
            SELECT p.source, p.code, p.name
            FROM product p LEFT JOIN nutrient_value v ON v.product_id = p.id
            GROUP BY p.id
            HAVING MAX(CASE WHEN v.nutrient_code='VITA_RAE' THEN v.value END) > 0
               AND COALESCE(MAX(CASE WHEN v.nutrient_code='RETOL'
                                     THEN v.value END), 0) = 0
               AND COALESCE(MAX(CASE WHEN v.nutrient_code='CARTB'
                                     THEN v.value END), 0) = 0""").fetchall()
        skurikhin = [r for r in rows if r[0] == "skurikhin"]
        self.assertEqual(skurikhin, [], f"РЭ без источника: {skurikhin[:5]}")
        bls = {r[1] for r in rows if r[0] == "bls"}
        self.assertEqual(bls, set(BLS_VITA_WITHOUT_RETINOL),
                         "набор BLS-исключений разошёлся с данными")
        # и ретинол BLS действительно импортирован, а не пуст
        self.assertGreater(self.db.execute(
            "SELECT COUNT(*) FROM nutrient_value v JOIN product p "
            "ON p.id = v.product_id WHERE p.source = 'bls' "
            "AND v.nutrient_code = 'RETOL'").fetchone()[0], 4400)

    # ---- L2: шум округления -------------------------------------------
    def test_no_float_noise_in_nutrients(self):
        rows = self.db.execute(
            "SELECT product_id, nutrient_code, value FROM nutrient_value "
            "WHERE value <> 0 AND ABS(value) < 0.005").fetchall()
        self.assertEqual(rows, [], f"шум округления: {rows[:5]}")

    # ---- L4: баланс жирных кислот -------------------------------------
    def test_saturated_plus_polyunsaturated_does_not_exceed_fat(self):
        rows = self.db.execute(
            "SELECT code, name, fat, sfa, pufa FROM product "
            "WHERE fat > 0 AND (sfa + pufa) > fat + 0.01").fetchall()
        self.assertEqual(rows, [], f"НЖК+ПНЖК > жира: {rows[:5]}")

    # ---- C5/C6: энергия порционной строки ------------------------------
    def test_energy_is_never_divided_in_portion_rows(self):
        """ЭЦ на 100 г не превращается в «ЭЦ на порцию» делением."""
        rows = self.db.execute(
            "SELECT p.code, p.kcal FROM product p "
            "WHERE p.source='skurikhin' AND p.kcal > 0 AND p.kcal < 15 "
            "AND (p.protein * 4 + p.fat * 9 + p.carbs * 4) > 40").fetchall()
        self.assertEqual(rows, [], f"ЭЦ рассинхронизирована: {rows[:5]}")

    def test_book_energy_matches_macros(self):
        """ЭЦ согласуется с БЖУ (+ПВ, +ОК, +спирт) в пределах 45 %…220 %."""
        # Аудит №9: проверяем ВСЕ продукты Скурихина (без AND kcal > 0):
        # продукты со значимыми макронутриентами не должны иметь kcal == 0.
        rows = self.db.execute("""
            SELECT code, name, kcal, protein, fat, carbs, fiber,
                   organic_acids, alcohol
            FROM product WHERE source='skurikhin'""").fetchall()
        broken = []
        zero_kcal = []
        for code, name, kcal, p, f, c, fib, oa, alc in rows:
            base = 4 * p + 9 * f + 4 * c + 7 * (alc or 0)
            extended = base + 2 * (fib or 0) + 3 * (oa or 0)
            if base <= 0:
                continue
            if kcal <= 0:
                zero_kcal.append((code, name, round(base, 1)))
            elif not (base * 0.45 <= kcal <= extended * 2.2 + 20):
                broken.append((code, kcal, round(base, 1)))
        self.assertEqual(zero_kcal, [], f"Продукты со значимыми БЖУ с нулевой ЭЦ: {zero_kcal}")
        self.assertEqual(broken, [], f"ЭЦ не сходится с БЖУ: {broken[:5]}")

    # ---- L9: меры ------------------------------------------------------
    def test_milk_and_butter_audit9_features(self):
        """Аудит №9: меры для питьевого молока и поиск сливочного масла 82.5%."""
        # 1. Меры для молока (1.3.1.1 — молоко 3.2%)
        milk_measures = self.db.execute("""
            SELECT m.name, m.grams FROM measure m
            JOIN product p ON p.id = m.product_id
            WHERE p.code = '1.3.1.1'
        """).fetchall()
        names = {name for name, _ in milk_measures}
        for expected in ("стакан 250 мл", "стакан 200 мл", "столовая ложка", "чайная ложка"):
            self.assertIn(expected, names, f"У молока 1.3.1.1 нет меры «{expected}»")

        # 2. Поиск масла с процентами жирности (82.5%, 82.5)
        for q in ("масло 82.5%", "масло 82.5", "масло 82,5"):
            hits = search(self.db, q, limit=3, is_dish=False)
            self.assertTrue(hits, f"Поиск «{q}» ничего не нашел")
            self.assertIn(hits[0][0], ("5.1.1", "5.1.2"), f"Топ-1 для «{q}» должен быть маслом 82.5%: {hits}")

    def test_measure_names_are_canonical(self):
        """Единые подписи мер: без «чайный/граненый» в скобках."""
        rows = self.db.execute(
            "SELECT DISTINCT name FROM measure WHERE "
            "name LIKE '%гранен%' OR name LIKE '%чайный%' OR "
            "name LIKE '%стол.%' OR name LIKE '%ч. ложка%' OR "
            "name LIKE '%ст. ложка%'").fetchall()
        self.assertEqual(rows, [], f"неканонические меры: {rows[:5]}")

    def test_measure_names_unique_per_product(self):
        """UNIQUE(product_id, name): нет двух «стакан 250 мл» у продукта."""
        rows = self.db.execute(
            "SELECT product_id, name, COUNT(*) FROM measure "
            "GROUP BY product_id, name HAVING COUNT(*) > 1").fetchall()
        self.assertEqual(rows, [])

    def test_measure_unique_index_exists(self):
        ddl = self.db.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' "
            "AND name='measure'").fetchone()[0]
        self.assertIn("UNIQUE", ddl.upper())

    def test_base_vegetables_have_waste(self):
        """H1: у базовых овощей/грибов/фруктов восстановлены отходы."""
        expected = {
            "8.1.2.1": 20.0,   # капуста белокочанная
            "8.1.4.1": 28.0,   # картофель
            "8.1.5.1": 20.0,   # морковь
            "8.1.5.12": 20.0,  # свекла
            "8.1.3.4": 16.0,   # лук репчатый
        }
        for code, waste in expected.items():
            with self.subTest(code=code):
                got = self.db.execute(
                    "SELECT waste_pct FROM product WHERE code=?",
                    (code,)).fetchone()[0]
                self.assertAlmostEqual(got, waste, places=1)

    def test_no_piece_measure_for_measured_liquids(self):
        """H2/M2: молоку и маслу не приписана мера «1 шт.».

        Этап 6 (дефект D2): то же правило — для ВСЕХ напитков (группа 11) и
        для фруктовых заготовок в сиропе/соке (11.1.4.*): их отмеряют
        стаканами и ложками, а «1 шт.» там появилась из приложения, где за
        штуку принималась тара. Чашки и ложки при этом сохраняются.
        """
        codes = ("10.11.6", "10.11.13", "9.1.2.8", "9.1.2.3")
        rows = self.db.execute(
            "SELECT p.code, m.name FROM product p "
            "JOIN measure m ON m.product_id = p.id "
            "WHERE p.code IN ('10.11.6','10.11.13','9.1.2.8','9.1.2.3') "
            "AND m.name LIKE '%шт%'").fetchall()
        self.assertEqual(rows, [], f"штучные меры у {codes}: {rows[:5]}")
        # вся группа напитков «11.*» и все «в сиропе»/«в соке»
        bad = self.db.execute(
            "SELECT p.code, p.name, m.name FROM product p "
            "JOIN measure m ON m.product_id = p.id "
            "WHERE (p.code LIKE '11.%' OR p.name LIKE '%в сиропе%' "
            "       OR p.name LIKE '%в соке%') "
            "AND m.name LIKE '%шт%' "
            "ORDER BY p.code").fetchall()
        self.assertEqual(bad, [], f"штучные меры у напитков: {bad[:8]}")

    def test_liquids_keep_cup_and_spoon_measures(self):
        """Дефект D2: сняв «1 шт.», чашки/ложки у напитков не потеряли."""
        for code in ("11.1.1.4", "11.1.1.7", "11.1.1.8", "11.1.1.9",
                     "11.1.4.16"):
            with self.subTest(code=code):
                names = [n for (n,) in self.db.execute(
                    "SELECT m.name FROM product p JOIN measure m "
                    "ON m.product_id = p.id WHERE p.code = ?", (code,))]
                self.assertTrue(names, f"{code}: мер нет вообще")
                self.assertTrue(
                    any("стакан" in n or "ложка" in n for n in names),
                    f"{code}: нет ни стакана, ни ложки — {names}")

    # ---- H4 / M3: названия ---------------------------------------------
    def test_no_mixed_latin_cyrillic(self):
        mixed = re.compile(r"[\u0400-\u04FF][A-Za-z]|[A-Za-z][\u0400-\u04FF]")
        rows = self.db.execute(
            "SELECT code, name FROM product").fetchall()
        bad = [(c, n) for c, n in rows if mixed.search(n)]
        self.assertEqual(bad, [], f"смешанная графика: {bad[:5]}")
        syn = self.db.execute("SELECT synonym FROM synonym").fetchall()
        bad_syn = [s for (s,) in syn if mixed.search(s)]
        self.assertEqual(bad_syn, [], f"смешанная графика в синонимах: "
                                     f"{bad_syn[:5]}")

    def test_product_names_are_unique(self):
        rows = self.db.execute(
            "SELECT name, COUNT(*) FROM product GROUP BY name "
            "HAVING COUNT(*) > 1").fetchall()
        self.assertEqual(rows, [], f"повторяющиеся названия: {rows[:5]}")

    def test_no_bogus_seasoning_synonym(self):
        """Синоним «сельдь под шубой нет, …» — мусор машинного перевода."""
        rows = self.db.execute(
            "SELECT synonym FROM synonym WHERE synonym LIKE '% нет,%' "
            "OR synonym LIKE '% нет %'").fetchall()
        self.assertEqual(rows, [])

    # ---- H3 / M1: ранжирование поиска ---------------------------------
    def test_search_puts_exact_head_noun_first(self):
        """«сыр» → сыр, «печень» → печень, а не «сырники»/«печенье»."""
        cases = {
            "сыр": "сыр",
            "печень": "печень",
            "сырок": "сырки",
            "мука пшеничная": "мука",
        }
        for query, expect in cases.items():
            with self.subTest(query=query):
                hits = search(self.db, query, limit=3)
                self.assertTrue(hits, f"«{query}» ничего не нашёл")
                self.assertIn(expect, hits[0][1].lower(),
                              f"«{query}» → {hits[0][1]!r}")

    def test_culinary_queries_return_results(self):
        for query in ("рибай", "голубика", "лохина", "сода", "корица",
                      "вода питьевая", "перец черный"):
            with self.subTest(query=query):
                self.assertTrue(search(self.db, query, limit=3),
                                f"«{query}» ничего не нашёл")

    # ---- M5: приправы ---------------------------------------------------
    def test_staples_are_in_the_reference(self):
        """Сода, корица, вода и перец есть в справочнике.

        Перец чёрный и сушёный базилик нашлись в самой книге (BLS группа R),
        поэтому для них принимается и код BLS, и дополнение `12.9.*`.
        """
        for query in ("сода", "корица", "вода", "перец черный",
                      "лавровый лист", "гвоздика", "мускатный орех"):
            with self.subTest(query=query):
                codes = [c for c, _ in search(self.db, query, limit=50)]
                self.assertTrue(
                    any(c.startswith(("12.9.", "R")) for c in codes),
                    f"«{query}» не находит приправу: {codes[:5]}")

    def test_herbs_and_spices_find_the_spice_itself(self):
        """Дефект D11: трава/пряность находится, и первой идёт сама специя.

        Раньше «кинза» и «орегано» не находили ничего, «паприка» вела к
        «Колбасе с паприкой», а «базилик» давал два одинаковых названия
        («Базилик сушёный» из книги и из дополнений).
        """
        cases = {
            "кинза": "кориандр", "кориандр": "кориандр",
            "орегано": "орегано", "душица": "орегано",
            "паприка": "паприка",
            "тимьян": "тимьян", "чабрец": "тимьян",
            "розмарин": "розмарин", "куркума": "куркума",
            "базилик": "базилик", "лаврушка": "лавровый",
        }
        for query, expect in cases.items():
            with self.subTest(query=query):
                hits = search(self.db, query, limit=3)
                self.assertTrue(hits, f"«{query}» ничего не нашёл")
                self.assertIn(expect, hits[0][1].lower(),
                              f"«{query}» → {hits[0][1]!r}")

    def test_spices_have_no_duplicate_names(self):
        """Ни одна приправа не заведена дважды (дефект D11)."""
        rows = self.db.execute(
            "SELECT lower(replace(name, 'ё', 'е')), COUNT(*) FROM product "
            "WHERE source IN ('bls', 'supplement') "
            "AND (group_id IN (SELECT id FROM food_group "
            "                  WHERE code IN ('BLS_R', 'BLS_G')) "
            "     OR source = 'supplement') "
            "GROUP BY 1 HAVING COUNT(*) > 1").fetchall()
        self.assertEqual(rows, [])

    def test_beverage_and_staple_labels(self):
        self.assertEqual(
            self.db.execute("SELECT source FROM product "
                            "WHERE code='12.9.1'").fetchone()[0], "supplement")

    # ---- M4: версия схемы ----------------------------------------------
    def test_schema_user_version(self):
        self.assertEqual(
            self.db.execute("PRAGMA user_version").fetchone()[0], 5)


class TestStage6DishSplit(unittest.TestCase):
    """Этап 6: разделение готовых блюд и сырья (`is_dish`)."""

    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def _dish(self, code: str) -> int:
        row = self.db.execute(
            "SELECT is_dish FROM product WHERE code = ?", (code,)).fetchone()
        self.assertIsNotNone(row, f"нет продукта {code}")
        return row[0]

    def test_is_dish_column_and_index(self):
        cols = [c[1] for c in self.db.execute("PRAGMA table_info(product)")]
        self.assertIn("is_dish", cols)
        idx = [r[1] for r in self.db.execute("PRAGMA index_list(product)")]
        self.assertIn("idx_product_is_dish", idx)
        bad = self.db.execute(
            "SELECT COUNT(*) FROM product WHERE is_dish NOT IN (0, 1)"
        ).fetchone()[0]
        self.assertEqual(bad, 0)

    def test_skurikhin_dishes_by_recipe_reference(self):
        """Блюдо по Сборнику рецептур («по 1-122») — готовое блюдо."""
        for code in ("8.1.5.21",):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)

    def test_skurikhin_industrial_products_stay_raw(self):
        """Паста ацидофильная, простокваша и хлеб — продукты, а не блюда.

        Названия похожи на «приготовленное», но это заводская продукция;
        список исключений `SKURIKHIN_INGREDIENT_NAMES` держит их сырьём.
        """
        for code in ("1.1.3.5", "1.1.2.12", "6.1.3.5.2"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)

    def test_skurikhin_flour_stays_raw(self):
        """Мука из подраздела «Кулинарные изделия» — всё-таки сырьё."""
        for code in ("6.1.3.1", "6.1.3.4", "6.1.3.7"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)

    def test_bls_ready_dishes_are_dishes(self):
        """BLS: отварное, жареное, запечённое — готовые блюда."""
        for code in ("C320032", "U235132"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)

    def test_bls_raw_is_not_dish(self):
        for code in ("U221100", "R258100", "F407100"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)

    def test_supplement_is_never_a_dish(self):
        rows = self.db.execute(
            "SELECT COUNT(*) FROM product "
            "WHERE source = 'supplement' AND is_dish != 0").fetchone()[0]
        self.assertEqual(rows, 0)

    def test_bls_x_and_y_are_all_dishes(self):
        """Группы BLS_X/BLS_Y («Готовые блюда», «Сложные блюда») — целиком."""
        bad = self.db.execute(
            "SELECT p.code, p.name FROM product p "
            "JOIN food_group g ON g.id = p.group_id "
            "WHERE g.code IN ('BLS_X', 'BLS_Y') AND p.is_dish = 0 "
            "LIMIT 5").fetchall()
        self.assertEqual(bad, [], f"сырьё в группах готовых блюд: {bad}")

    def test_search_prefers_raw_without_filter(self):
        """Без фильтра сырьё идёт раньше готовых блюд (порядок в UI)."""
        codes = [c for c, _ in search(self.db, "гречка", limit=5)]
        first = self.db.execute(
            "SELECT is_dish FROM product WHERE code = ?",
            (codes[0],)).fetchone()[0]
        self.assertEqual(first, 0, f"«гречка» → {codes[0]} (блюдо первым)")

    def test_search_is_dish_filter(self):
        from tools.data_pipeline.build_reference_db import search as _search
        only_raw = _search(DEPLOYED, "гречка", limit=10, is_dish=False)
        only_dish = _search(DEPLOYED, "гречка", limit=10, is_dish=True)
        self.assertTrue(only_raw, "фильтр «только продукты» ничего не нашёл")
        self.assertTrue(only_dish, "фильтр «только блюда» ничего не нашёл")


class TestStage6Defects(unittest.TestCase):
    """Этап 6: закрытие дефектов D1–D13 в данных."""

    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def _row(self, code: str):
        row = self.db.execute(
            "SELECT protein, fat, carbs, fiber, organic_acids, alcohol, kcal "
            "FROM product WHERE code = ?", (code,)).fetchone()
        self.assertIsNotNone(row, f"нет продукта {code}")
        return row

    def _calc_kcal(self, code: str) -> float:
        b, f, c, pv, oa, alc, _ = self._row(code)
        return 4 * b + 9 * f + 4 * c + 2 * pv + 3 * oa + 7 * alc

    def test_d1_ukrainian_borscht_energy(self):
        """D1: у «Борща украинского» ЭЦ была витамином C (4 ккал)."""
        b, f, c, pv = (1.1, 2.2, 6.5, 0.8)
        expect = 4 * b + 9 * f + 4 * c + 2 * pv
        kcal = self._row("8.1.5.21")[6]
        self.assertAlmostEqual(kcal, expect, places=1)
        self.assertLess(kcal, 60.0, "ЭЦ борща снова ~95 ккал")

    def test_d5_energy_matches_macros(self):
        """D5: у этих строк книжная ЭЦ была взята из строки порции 50 г."""
        # Только коды, где формула книги воспроизводит ЭЦ точно. У
        # `4.1.6.6`, `6.1.3.5.2`, `1.1.3.5`, `1.1.2.12` книга считает
        # органические кислоты иначе — там проверяется лишь порядок
        # величины (см. `test_d5_energy_is_not_a_portion_row`).
        for code in ("4.1.6.5", "3.6.4.2", "8.1.5.21"):
            with self.subTest(code=code):
                expect = self._calc_kcal(code)
                self.assertAlmostEqual(self._row(code)[6], expect, delta=0.6)

    def test_d5_energy_is_not_a_portion_row(self):
        """D5: ЭЦ не должна равняться энергии порции 20–50 г."""
        for code in ("4.1.6.6", "6.1.3.5.2", "1.1.3.5", "1.1.2.12"):
            with self.subTest(code=code):
                kcal = self._row(code)[6]
                expect = self._calc_kcal(code)
                # Книжная ЭЦ не ниже расчётной по составу и не «порционная».
                self.assertGreater(kcal, expect * 0.8)
                self.assertLess(kcal, expect * 1.2)

    def test_d6_yo_duplicates_disambiguated(self):
        """D6: «сушеный»/«сушёный» больше не дают двух одинаковых названий."""
        rows = self.db.execute(
            "SELECT lower(replace(name, 'ё', 'е')), COUNT(*) FROM product "
            "GROUP BY 1 HAVING COUNT(*) > 1").fetchall()
        self.assertEqual(rows, [], f"дубли «е»/«ё»: {rows[:5]}")
        names = {r[0] for r in self.db.execute(
            "SELECT name FROM product WHERE code IN ('F203400', 'F505400')")}
        self.assertEqual(names, {"Персик сушёный (BLS)", "Инжир сушёный (BLS)"})

    def test_d7_supplements_balance_to_100_grams(self):
        """D7: у пряностей углеводы были общими, вместе с клетчаткой."""
        rows = self.db.execute(
            "SELECT code, name, water + protein + fat + carbs + fiber + ash "
            "+ organic_acids FROM product WHERE source = 'supplement'"
        ).fetchall()
        self.assertTrue(rows)
        bad = [(c, n, round(m, 2)) for c, n, m in rows if abs(m - 100.0) > 0.05]
        self.assertEqual(bad, [], f"масса != 100 г: {bad}")

    def test_d7_water_never_exceeds_100(self):
        """D7: у минеральных вод было 100,5 г воды на 100 г."""
        bad = self.db.execute(
            "SELECT code, name, water FROM product WHERE water > 100.0"
        ).fetchall()
        self.assertEqual(bad, [], f"вода > 100 г: {bad[:5]}")

    def test_d9_no_negative_or_oversized_components(self):
        cols = ("water", "protein", "fat", "carbs", "fiber", "ash",
                "organic_acids", "alcohol")
        for col in cols:
            with self.subTest(column=col):
                bad = self.db.execute(
                    f"SELECT code, {col} FROM product "
                    f"WHERE {col} < 0 OR {col} > 100").fetchall()
                self.assertEqual(bad, [], f"{col} вне 0…100: {bad[:5]}")

    def test_d9_potash_is_not_a_salt_substitute(self):
        """D9: R421300 — поташ (K₂CO₃), а не диетическая калиевая соль."""
        row = self.db.execute(
            "SELECT name FROM product WHERE code = 'R421300'").fetchone()
        self.assertIsNotNone(row)
        self.assertIn("поташ", row[0].lower())
        self.assertNotIn("калиевая соль", row[0].lower())

    def test_d10_short_prefix_does_not_match_long_words(self):
        """D10: «морс» не должен вести к «морскому окуню»."""
        first = search(self.db, "морс", limit=3)[0][1].lower()
        self.assertNotIn("морск", first)
        self.assertIn("морс", first.replace("клюквенный", "морс"))

    def test_d10_grechka_finds_raw_groats(self):
        """D10: «гречка» → крупа, а не варёная каша."""
        code = search(self.db, "гречка", limit=1)[0][0]
        is_dish = self.db.execute(
            "SELECT is_dish FROM product WHERE code = ?", (code,)).fetchone()[0]
        self.assertEqual(is_dish, 0)

    def test_d10_ribeye_finds_raw_beef(self):
        first = search(self.db, "рибай", limit=1)[0][1].lower()
        self.assertIn("сырая", first)

    def test_d11_herbs_and_spices_searchable(self):
        """D11: кинза, орегано, чабрец и паприка находят специю."""
        for query, expect in {
            "кинза": "кориандр", "орегано": "орегано", "душица": "орегано",
            "чабрец": "тимьян", "паприка": "паприка", "куркума": "куркума",
        }.items():
            with self.subTest(query=query):
                hits = search(self.db, query, limit=3)
                self.assertTrue(hits, f"«{query}» ничего не нашёл")
                self.assertIn(expect, hits[0][1].lower())

    def test_d13_bakery_flour_is_the_bread_grade(self):
        """D13: в пекарском рецепте была мука для макаронных изделий."""
        self.assertEqual(
            self.db.execute(
                "SELECT code FROM product WHERE id = 561").fetchone()[0],
            "6.1.3.1")
        b, f, c, _, _, _, kcal = self._row("6.1.3.1")
        self.assertEqual((b, f, c, kcal), (10.3, 1.1, 70.6, 334.0))

    def test_d13_masters_recipes_match_reference_db(self):
        """D13: все 28 ингредиентов MastersRecipesCatalog должны совпадать с БД по id, БЖУ, ккал и waste_pct."""
        dart_path = ROOT / "app" / "lib" / "data" / "masters_recipes.dart"
        dart = dart_path.read_text(encoding="utf-8")
        pattern = re.compile(
            r"MasterIngredientItem\(\s*(?://[^\n]*\n\s*)*"
            r"productId:\s*(\d+),\s*"
            r"name:\s*'([^']+)',\s*"
            r"weightGrams:\s*[\d.]+,\s*"
            r"isGross:\s*(?:true|false),\s*"
            r"wastePct:\s*([\d.]+),\s*"
            r"protein:\s*([\d.]+),\s*"
            r"fat:\s*([\d.]+),\s*"
            r"carbs:\s*([\d.]+),\s*"
            r"kcal:\s*([\d.]+),\s*"
            r"source:\s*'([^']+)'"
        )
        items = pattern.findall(dart)
        self.assertEqual(len(items), 28)
        for pid, name, waste, p, f, c, kcal, src in items:
            row = self.db.execute(
                "SELECT name, waste_pct, protein, fat, carbs, kcal, source "
                "FROM product WHERE id = ?", (int(pid),)).fetchone()
            self.assertIsNotNone(row, f"productId={pid} ({name}) не найден в БД")
            db_name, db_w, db_p, db_f, db_c, db_k, db_src = row
            self.assertEqual(name, db_name, f"productId={pid}: ожидали точное совпадение «{db_name}», в Dart «{name}»")
            self.assertAlmostEqual(float(waste), db_w, places=2)
            self.assertAlmostEqual(float(p), db_p, places=2)
            self.assertAlmostEqual(float(f), db_f, places=2)
            self.assertAlmostEqual(float(c), db_c, places=2)
            self.assertAlmostEqual(float(kcal), db_k, places=1)
            self.assertEqual(src, db_src)


class TestStage65Defects(unittest.TestCase):
    """Этап 6.5: закрытие дефектов D15–D17 Мега-Аудита №4."""

    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def _dish(self, code: str) -> int:
        row = self.db.execute(
            "SELECT is_dish FROM product WHERE code = ?", (code,)).fetchone()
        self.assertIsNotNone(row, f"нет продукта {code}")
        return row[0]

    def _raw_first(self, query: str, prefer: tuple[str, ...] = ()) -> tuple:
        """Топ-1 в режиме калькулятора (`is_dish = False`)."""
        hits = search(self.db, query, limit=5, is_dish=False)
        self.assertTrue(hits, f"«{query}» с is_dish=False ничего не нашёл")
        for code, name in hits:
            if not prefer or any(word in name.lower() for word in prefer):
                return code, name
        self.fail(f"«{query}» → нет подходящего топ-1 среди {hits[:3]}")

    # ---- D15: is_dish -------------------------------------------------
    def test_d15_raw_liver_is_not_a_dish(self):
        """«печень» ≠ «печёный»: корень `печен` больше не ловит печень."""
        for code in ("V531100", "V532100", "V533100", "V634100", "V535100"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)
        # а причастие «печёный» по-прежнему блюдо
        for code in ("D079062", "C341162"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)
        # и «печенье» в кондитерской группе — тоже блюдо
        self.assertEqual(self._dish("D701600"), 1)

    def test_d15_raw_meat_fish_poultry_offal_is_not_a_dish(self):
        """«сырой/свежий» без термической готовки — сырьё."""
        rows = self.db.execute("""
            SELECT p.code, p.name FROM product p
            JOIN food_group g ON g.id = p.group_id
            WHERE p.source = 'bls' AND g.code NOT IN ('BLS_X', 'BLS_Y')
              AND p.is_dish = 1
              AND (p.name_norm LIKE '% сырой' OR p.name_norm LIKE '% сырая'
                   OR p.name_norm LIKE '% сырое' OR p.name_norm LIKE '% сырые'
                   OR p.name_norm LIKE '% свежий' OR p.name_norm LIKE '% свежая'
                   OR p.name_norm LIKE '% заморожен%')
              AND p.name_norm NOT LIKE '%варен%'
              AND p.name_norm NOT LIKE '%жарен%'
              AND p.name_norm NOT LIKE '%тушен%'
              AND p.name_norm NOT LIKE '%запеч%'
              AND p.name_norm NOT LIKE '%отвар%'
              AND p.name_norm NOT LIKE '%обжарен%'
              AND p.name_norm NOT LIKE '%припущен%'
              AND p.name_norm NOT LIKE '%грил%'
              AND p.name_norm NOT LIKE '%на пару%'
              AND p.name_norm NOT LIKE '%заморожен%, варен%'
        """).fetchall()
        self.assertEqual(rows, [], f"сырьё осталось блюдом: {rows[:5]}")

    def test_d15_leafy_salad_is_a_plant_not_a_dish(self):
        """«Салат листовой» — растение; салат по рецептуре — блюдо."""
        self.assertEqual(self._dish("8.1.1.4"), 0)
        for code in ("G104100", "G103100", "G105100", "G108100", "G280100",
                     "G101100"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)
        # салаты по Сборнику рецептур остаются блюдами
        for code in ("8.1.1.5", "8.1.2.1.1", "3.5.2.23"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)
        # салат с заправкой / картофельный салат — блюдо
        self.assertEqual(self._dish("X1A2020"), 1)

    def test_d15_gastronomy_and_smoked_are_ingredients(self):
        """Колбасы, ветчина и копчёности без вторичной готовки — ингредиенты."""
        for code in ("W424032", "W115200", "W411300", "T410600", "U111700"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)
        # Готовые кулинарные изделия из гастрономии (запечённые, пироги в тесте)
        for code in ("W812000", "W981100", "W234082"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)

    def test_b2_grill_and_pork_neck(self):
        """Гриль и готовое мясо — блюда; сырая шея — сырьё и Топ-1 в калькуляторе."""
        for code in ("U632072", "U632172", "U632272", "T410072", "V4A6172"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 1)
        self.assertEqual(self._dish("U632100"), 0)
        hits = search(self.db, "свиная шея", limit=3, is_dish=False)
        self.assertTrue(hits)
        self.assertEqual(hits[0][0], "U632100", f"Топ-1 должен быть U632100: {hits}")

    def test_d15_gnocchi_and_dough(self):
        """Сырые/замороженные ньокки, равиоли и паста — сырьё."""
        for code in ("K270000", "K271000", "E401000", "E606000"):
            with self.subTest(code=code):
                self.assertEqual(self._dish(code), 0)

    def test_d15_search_liver_prefers_raw_over_biscuit(self):
        """«печень» в калькуляторе → сырая печень, а НЕ овсяное печенье."""
        hits = [n.lower() for _, n in search(self.db, "печень", limit=10,
                                             is_dish=False)]
        self.assertTrue(hits, "«печень» ничего не нашёл")
        self.assertTrue(any("печень" in n for n in hits),
                        f"нет печени среди {hits[:5]}")
        self.assertFalse(any("печенье" in n for n in hits),
                         "в сырье попало печенье")
        self.assertFalse(any("овсяное" in n for n in hits))
        code, name = self._raw_first("печень")

    def test_d15_skurikhin_leafy_salad_raw(self):
        code, name = self._raw_first("салат листовой", prefer=("салат",))
        self.assertIn("салат", name.lower())
        stages = self.db.execute(
            "SELECT is_dish FROM product WHERE code IN ('8.1.1.4', 'G108100')"
        ).fetchall()
        self.assertEqual([r[0] for r in stages], [0, 0])

    # ---- D16: ретинол --------------------------------------------------
    def test_d16_bls_retinol_is_imported(self):
        count = self.db.execute(
            "SELECT COUNT(*) FROM nutrient_value v JOIN product p "
            "ON p.id = v.product_id WHERE p.source = 'bls' "
            "AND v.nutrient_code = 'RETOL'").fetchone()[0]
        self.assertGreater(count, 4400, f"RETOL BLS: {count}")
        # мкг, а не мг: у куриной печени ~7000 мкг ретинола на 100 г
        value = self.db.execute(
            "SELECT v.value FROM nutrient_value v JOIN product p "
            "ON p.id = v.product_id WHERE p.code = 'V634100' "
            "AND v.nutrient_code = 'RETOL'").fetchone()
        self.assertIsNotNone(value)
        self.assertGreater(value[0], 1000.0)
        self.assertLess(value[0], 20000.0)

    def test_d16_no_duplicate_nutrient_rows(self):
        rows = self.db.execute(
            "SELECT product_id, nutrient_code, COUNT(*) FROM nutrient_value "
            "GROUP BY 1, 2 HAVING COUNT(*) > 1 LIMIT 5").fetchall()
        self.assertEqual(rows, [], f"дубли nutrient_value: {rows}")

    def test_d16_bls_products_json_has_retinol(self):
        import json
        payload = json.loads(
            (ROOT / "data" / "bls_v4" / "bls_products.json")
            .read_text(encoding="utf-8"))
        with_retinol = [p for p in payload["products"]
                        if (p["nutrients"].get("retinol") or {})
                        .get("value", 0) > 0]
        self.assertGreater(len(with_retinol), 4400)
        liver = next(p for p in payload["products"] if p["code"] == "V634100")
        self.assertEqual(liver["nutrients"]["retinol"]["unit"], "µg")

    # ---- D17: кулинарные синонимы --------------------------------------
    def test_d17_culinary_queries_have_relevant_top(self):
        expect = {
            "печень куриная": ("курин", "печен"),
            "салат листовой": ("салат",),
            "спагетти": ("макарон", "спагетт", "паста"),
            "сало": ("шпик", "сало"),
            "ньокки": ("ньокки",),
        }
        for query, words in expect.items():
            with self.subTest(query=query):
                _code, name = self._raw_first(query)
                self.assertTrue(any(w in name.lower() for w in words),
                                f"«{query}» → {name}")

    def test_d17_synonyms_point_to_the_right_products(self):
        expect = {
            "спагетти": {"6.1.2.1.1", "6.1.2.1.2", "E401000", "E510000"},
            "макароны": {"6.1.2.1.1", "6.1.2.1.2", "6.1.2.2.1"},
            "сало": {"5.2.5", "5.2.6", "U605700"},
            "шпик": {"5.2.5", "5.2.6"},
            "бешамель": {"X320243", "R911000"},
            "ньокки": {"K270000", "K271000"},
        }
        for synonym, codes in expect.items():
            with self.subTest(synonym=synonym):
                found = {r[0] for r in self.db.execute(
                    "SELECT p.code FROM synonym s JOIN product p "
                    "ON p.id = s.product_id WHERE s.synonym_norm = ?",
                    (synonym,))}
                self.assertTrue(codes & found,
                                f"«{synonym}» не привязан ни к одному из "
                                f"{sorted(codes)} (есть: {sorted(found)[:5]})")

    def test_d17_salo_top1_is_lard(self):
        """«сало» сразу отдаёт свиной шпик, а не копчёную грудинку."""
        code, name = search(self.db, "сало", limit=1, is_dish=False)[0]
        self.assertIn(code, {"5.2.5", "5.2.6", "U605700"}, name)

    # ---- D16 (этап 6.6): ретинол не превышает РЭ ------------------------
    def test_d16_retinol_never_exceeds_vita_rae(self):
        """Д16: `RETOL <= VITA_RAE` и `RETOL + CARTB/12 <= VITA_RAE + 0,01`.

        BLS округляет столбец `VITA` (РЭ) до ЦЕЛЫХ мкг, а `RETOL` задан с
        десятыми долями, поэтому до этапа 6.6 в базе было 22 строки с
        ретинолом больше РЭ (`W255700` 1530,1 против 1530,0; `W110000` 8,1
        против 8,0; `S581900` 0,7 против 0) и 311 строк BLS, где сумма
        `RETOL + CARTB/12` превышала РЭ на 0,08…0,33 мкг. Физически это
        невозможно: РЭ и ЕСТЬ ретинол плюс каротиноиды в пересчёте.

        Сверка выполняется в сборке (`reconcile_vitamin_a`), а здесь
        проверяется ИТОГОВАЯ база — во всех 8 261 продуктах.
        """
        # 1. RETOL <= VITA_RAE — во всей базе, без исключений по источнику.
        over = self.db.execute(
            "SELECT p.source, p.code, p.name, r.value, "
            "COALESCE(v.value, 0) FROM product p "
            "JOIN nutrient_value r ON r.product_id = p.id "
            "AND r.nutrient_code = 'RETOL' "
            "LEFT JOIN nutrient_value v ON v.product_id = p.id "
            "AND v.nutrient_code = 'VITA_RAE' "
            "WHERE r.value > COALESCE(v.value, 0) + 1e-9 "
            "ORDER BY p.code").fetchall()
        self.assertEqual(over, [], f"RETOL > VITA_RAE: {over[:5]}")
        # 2. формула BLS: РЭ = ретинол + β-каротин/12 (допуск 0,01 мкг).
        over_bls = self.db.execute(
            "SELECT p.code, p.name, "
            "COALESCE(r.value, 0) + COALESCE(b.value, 0) / 12.0, "
            "COALESCE(v.value, 0) FROM product p "
            "LEFT JOIN nutrient_value r ON r.product_id = p.id "
            "AND r.nutrient_code = 'RETOL' "
            "LEFT JOIN nutrient_value b ON b.product_id = p.id "
            "AND b.nutrient_code = 'CARTB' "
            "LEFT JOIN nutrient_value v ON v.product_id = p.id "
            "AND v.nutrient_code = 'VITA_RAE' "
            "WHERE p.source = 'bls' AND "
            "COALESCE(r.value, 0) + COALESCE(b.value, 0) / 12.0 "
            "> COALESCE(v.value, 0) + 0.01 "
            "ORDER BY p.code").fetchall()
        self.assertEqual(over_bls, [],
                         f"BLS RETOL + CARTB/12 > VITA_RAE + 0,01: "
                         f"{over_bls[:5]}")
        # 3. сверка не «съела» данные: РЭ по-прежнему есть у обоих источников.
        counts = dict(self.db.execute(
            "SELECT p.source, COUNT(DISTINCT p.id) FROM product p "
            "JOIN nutrient_value v ON v.product_id = p.id "
            "AND v.nutrient_code = 'VITA_RAE' GROUP BY p.source").fetchall())
        self.assertGreater(counts.get("bls", 0), 4000, counts)
        self.assertGreater(counts.get("skurikhin", 0), 500, counts)

    def test_d16_retinol_rounding_case_is_repaired(self):
        """Точная строка из аудита: W255700 — 1530,1 мкг ретинола.

        До этапа 6.6 РЭ была 1530,0 и ретинол «висел» над ней на 0,1 мкг.
        Теперь РЭ не меньше ретинола, а остальные значения не сдвинуты.
        """
        rows = dict(self.db.execute(
            "SELECT v.nutrient_code, v.value FROM nutrient_value v "
            "JOIN product p ON p.id = v.product_id "
            "WHERE p.code = 'W255700' "
            "AND v.nutrient_code IN ('RETOL', 'VITA_RAE')").fetchall())
        self.assertAlmostEqual(rows["RETOL"], 1530.1, places=3)
        self.assertGreaterEqual(rows["VITA_RAE"] + 1e-9, rows["RETOL"])

    # ---- этап 6.6: стемминг прилагательных ------------------------------
    def test_d18_adjective_stemming_matches_all_genders(self):
        """«куриный»/«говяжий»/«свиная» сходятся к основе другого рода.

        Раньше отсекался ОДИН последний символ: «куриный» → «курины» (в базе
        только «куриная»/«куриное»), «говяжий» → «говяжи» (в базе «говяжья»),
        «свиная» → «свина» (в базе «свиной»), и запрос «окорочок куриный»
        отдавал ПУСТО. Теперь основа общая: «курин», «говяж», «свин».
        """
        from tools.data_pipeline.build_reference_db import _fts_tokens
        cases = {
            "куриный": {"куриная", "куриное"},
            "говяжий": {"говяжья", "говяжье"},
            "свиной": {"свиная", "свиное"},
            "индейки": {"индейка"},
        }
        for word, forms in cases.items():
            with self.subTest(word=word):
                base = _fts_tokens(word)[0]
                for form in forms:
                    self.assertEqual(
                        base, _fts_tokens(form)[0],
                        f"«{word}» и «{form}» дают разные основы")
        # короткие токены не режутся ниже 3 букв (иначе «сыр» = «сырок»)
        self.assertEqual(_fts_tokens("сыр"), ["сыр"])
        # и основа никогда не становится короче 3 букв
        self.assertEqual(_fts_tokens("яйцо"), ["яйц"])

    def test_d18_broiler_leg_query_finds_chicken_leg(self):
        """«окорочок куриный» → куриная ножка, а не пустой ответ.

        Эталон промпта: во втором проходе ищется `"окорочк"* "курин"*`.
        """
        hits = search(self.db, "окорочок куриный", limit=3, is_dish=False)
        self.assertTrue(hits, "«окорочок куриный» ничего не нашёл")
        codes = {code for code, _name in hits}
        self.assertTrue(codes & {"V435100", "V435200"}, hits)
        # порядок слов в запросе не важен
        reverse = {code for code, _name
                   in search(self.db, "куриный окорочок", limit=3,
                             is_dish=False)}
        self.assertTrue(reverse & {"V435100", "V435200"}, reverse)

    def test_d18_turkey_fillet_query_finds_turkey_breast(self):
        """«филе индейки» → грудка индейки без кожи, сырая."""
        hits = search(self.db, "филе индейки", limit=3, is_dish=False)
        self.assertTrue(hits, "«филе индейки» ничего не нашёл")
        self.assertIn("V486100", {code for code, _name in hits}, hits)

    def test_d18_poultry_synonyms_point_to_the_right_products(self):
        """Синонимы окорочка и индейки привязаны к СЫРЫМ позициям BLS."""
        expect = {
            # голый «окорочок» — только курица (иначе в калькулятор первой
            # шла индейка); у индейки — лишь с уточнением «индейки»
            "окорочок": {"V435100", "V435200"},
            "окорочок индейки": {"V485100"},
            "окорочок куриный": {"V435100", "V435200"},
            "куриный окорочок": {"V435100", "V435200"},
            "филе индейки": {"V486100"},
            "индейка филе": {"V486100"},
            "грудка индейки": {"V486100"},
        }
        for synonym, codes in expect.items():
            with self.subTest(synonym=synonym):
                found = {r[0] for r in self.db.execute(
                    "SELECT p.code FROM synonym s JOIN product p "
                    "ON p.id = s.product_id WHERE s.synonym_norm = ?",
                    (synonym,))}
                self.assertTrue(codes <= found,
                                f"«{synonym}»: ожидали {sorted(codes)}, "
                                f"есть {sorted(found)}")

    def test_d18_v435100_is_raw_chicken_leg(self):
        """V435100/…200 — сырая куриная ножка/окорочок, а не блюдо.

        В промпте эталон назван «сырой окорочок курицы (V435100)», а в BLS
        4.0 этот код — «Ножка суповой курицы с кожей, сырая»: та же
        анатомическая позиция (бедро + голень), поэтому синоним корректен;
        главное — позиция остаётся СЫРЬЁМ калькулятора.
        """
        for code in ("V435100", "V435200"):
            with self.subTest(code=code):
                row = self.db.execute(
                    "SELECT is_dish, name FROM product WHERE code = ?",
                    (code,)).fetchone()
                self.assertIsNotNone(row, f"нет продукта {code}")
                self.assertEqual(row[0], 0, f"{code} — блюдо: {row[1]}")
                self.assertIn("куриц", row[1].lower())


class TestD17SourceLabelSinglePoint(unittest.TestCase):
    """D17: подпись источника задаётся в одном месте (`SourceLabel`)."""

    def setUp(self):
        app = ROOT / "app" / "lib"
        self.modal = (app / "presentation" / "screens"
                      / "search_product_modal.dart").read_text(encoding="utf-8")
        self.table = (app / "core" / "calculation" / "models"
                      / "source_label.dart").read_text(encoding="utf-8")

    def test_product_and_badge_share_one_table(self):
        app = ROOT / "app" / "lib"
        model = (app / "core" / "calculation" / "models" / "product.dart"
                 ).read_text(encoding="utf-8")
        badge = (app / "presentation" / "widgets" / "source_badge.dart"
                 ).read_text(encoding="utf-8")
        self.assertIn("SourceLabel.of(", model)
        self.assertIn("SourceLabel.of(", badge)
        # подписи живут только в таблице — не копируются в модель и виджет
        for literal in ("'Скурихин'", "'Дополнено'"):
            with self.subTest(literal=literal):
                self.assertIn(literal, self.table)
                self.assertNotIn(literal, badge,
                                 "подпись продублирована в SourceBadge")
                self.assertNotIn(literal, model,
                                 "подпись продублирована в Product")

    def test_search_modal_uses_the_single_table(self):
        """Этап 6.6: модалка поиска берёт подписи из `SourceLabel`.

        Раньше третьим источником («Дополнено» — приправы и вода) значок
        `SourceBadge` подписывал верно, а модалка показывала сырой код или
        «BLS». Теперь и карточка продукта, и фильтр источника идут через
        таблицу, а литералы подписей в модалке не встречаются вовсе.
        """
        self.assertIn("import '../../core/calculation/models/source_label.dart'",
                      self.modal)
        # карточка продукта и раскрывающаяся панель берут подпись из модели
        # (`product.sourceLabel`), которая сама делегирует в таблицу.
        self.assertEqual(self.modal.count("product.sourceLabel"), 2,
                         "карточка и панель должны подписываться из модели")
        # фильтр источника — напрямую из таблицы, а не строками
        self.assertEqual(self.modal.count("SourceLabel.of("), 2,
                         "ожидались 2 подписи фильтра источника")
        for literal in ("'Скурихин'", "'BLS'", "'Дополнено'"):
            with self.subTest(literal=literal):
                self.assertNotIn(literal, self.modal,
                                 f"подпись {literal} продублирована в модалке")
        # каждый источник БД подписан: иначе в карточке будет пусто
        for source in ("skurikhin", "bls", "supplement", "usda"):
            with self.subTest(source=source):
                self.assertIn(f"'{source}':", self.table)


CHEF_101_BENCHMARK: tuple[tuple[str, tuple[str, ...]], ...] = (
    # 1. Мясо и птица (15)
    ("говядина", ("говядин",)),
    ("говяжья вырезка", ("говяж", "вырезк")),
    ("толстый край", ("спинн", "толст", "ростбиф")),
    ("рибай", ("спинн", "рибай", "ростбиф")),
    ("свинина", ("свинин", "свин")),
    ("баранина", ("баранин", "баран")),
    ("телятина", ("телятин", "теляч")),
    ("курица", ("куриц", "цыпл")),
    ("филе куриное", ("курин", "грудк", "филе")),
    ("окорочок куриный", ("куриц", "ножк", "окороч")),
    ("куриный окорочок", ("куриц", "ножк", "окороч")),
    ("индейка", ("индейк",)),
    ("филе индейки", ("индейк", "грудк")),
    ("грудка индейки", ("индейк", "грудк")),
    ("утка", ("утк", "утин")),
    # 2. Субпродукты и гастрономия (10)
    ("печень", ("печень",)),
    ("печень куриная", ("курин", "печень")),
    ("печень говяжья", ("говяж", "печень")),
    ("сердце", ("сердц",)),
    ("говяжий язык", ("язык",)),
    ("лёгкие", ("легк",)),
    ("ветчина", ("ветчин",)),
    ("колбаса вареная", ("колбас",)),
    ("сосиски", ("сосиск",)),
    ("сало", ("шпик", "сало")),
    # 3. Рыба и морепродукты (10)
    ("треска", ("треск",)),
    ("лосось", ("лосос", "семг")),
    ("семга", ("лосос", "семг")),
    ("горбуша", ("горбуш",)),
    ("сельдь", ("сельд",)),
    ("скумбрия", ("скумбр",)),
    ("минтай", ("минтай",)),
    ("судак", ("судак",)),
    ("креветки", ("креветк",)),
    ("кальмар", ("кальмар",)),
    # 4. Молоко, сыры, яйца (13)
    ("молоко", ("молок",)),
    ("молоко 3.2", ("молок", "3,2")),
    ("сливки", ("сливк",)),
    ("сметана", ("сметан",)),
    ("сметана 10", ("сметан", "10")),
    ("сметана 20", ("сметан", "20")),
    ("творог", ("творог",)),
    ("творог 9", ("творог", "9")),
    ("кефир", ("кефир",)),
    ("сыр", ("сыр",)),
    ("сыр российский", ("российск", "сыр")),
    ("яйцо", ("яйц",)),
    ("яйцо перепелиное", ("перепелин", "яйц")),
    # 5. Масла и жиры (5)
    ("масло сливочное", ("масло", "сливочн")),
    ("масло подсолнечное", ("подсолнечн", "масло")),
    ("масло оливковое", ("оливков", "масло")),
    ("маргарин", ("маргарин",)),
    ("шпик", ("шпик",)),
    # 6. Крупы, мука, макароны, хлеб (14)
    ("мука", ("мука",)),
    ("мука пшеничная", ("мука",)),
    ("гречка", ("гречк", "гречнев")),
    ("крупа гречневая", ("гречнев", "круп")),
    ("рис", ("рис",)),
    ("овсянка", ("овсян", "геркулес")),
    ("геркулес", ("геркулес", "хлопья")),
    ("пшено", ("пшен",)),
    ("перловка", ("перлов",)),
    ("манка", ("манн",)),
    ("макароны", ("макарон",)),
    ("спагетти", ("макарон", "спагетт")),
    ("ньокки", ("ньокки",)),
    ("хлеб пшеничный", ("хлеб", "пшеничн")),
    # 7. Овощи, зелень, грибы, бобовые (16)
    ("картошка", ("картофел",)),
    ("морковь", ("морков",)),
    ("свекла", ("свекл",)),
    ("лук репчатый", ("лук", "репчат")),
    ("чеснок", ("чеснок",)),
    ("капуста белокочанная", ("капуст", "белокочан")),
    ("помидоры", ("томат", "помидор")),
    ("огурцы", ("огурц",)),
    ("перец сладкий", ("перец", "сладк")),
    ("баклажан", ("баклажан",)),
    ("кабачки", ("кабачк", "цуккин")),
    ("салат листовой", ("салат",)),
    ("шампиньоны", ("шампиньон",)),
    ("горох", ("горох", "горошек")),
    ("фасоль", ("фасол",)),
    ("чечевица", ("чечевиц",)),
    # 8. Фрукты, орехи, кондитерка, бакалея, специи (18)
    ("яблоки", ("яблок",)),
    ("лимон", ("лимон",)),
    ("бананы", ("банан",)),
    ("черника", ("черник",)),
    ("грецкий орех", ("грецк", "орех")),
    ("миндаль", ("миндал",)),
    ("сахар", ("сахар",)),
    ("мёд", ("мед",)),
    ("шоколад", ("шоколад",)),
    ("какао", ("какао",)),
    ("соль", ("соль",)),
    ("вода", ("вода",)),
    ("сода", ("сода",)),
    ("уксус", ("уксус",)),
    ("желатин", ("желатин",)),
    ("томатная паста", ("томатн", "паст")),
    ("майонез", ("майонез",)),
    ("горчица", ("горчиц",)),
)


class TestChef101QueriesBenchmark(unittest.TestCase):
    """Канонический воспроизводимый бенчмарк из 101 кулинарного запроса."""

    @classmethod
    def setUpClass(cls):
        cls.db = connect()

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_chef_101_queries_are_unique(self):
        self.assertEqual(len(CHEF_101_BENCHMARK), 101)
        self.assertEqual(len({q for q, _ in CHEF_101_BENCHMARK}), 101)

    def test_chef_101_queries_100_percent_relevance(self):
        for is_dish in (False, None):
            with self.subTest(is_dish=is_dish):
                failures = []
                for query, expected_roots in CHEF_101_BENCHMARK:
                    hits = search(self.db, query, limit=3, is_dish=is_dish)
                    if not hits:
                        failures.append((query, "EMPTY"))
                        continue
                    top_code, top_name = hits[0]
                    norm = top_name.lower().replace("ё", "е")
                    if not any(root in norm for root in expected_roots):
                        failures.append((query, f"{top_code} {top_name!r}"))
                self.assertEqual(
                    failures, [],
                    f"is_dish={is_dish}: {len(failures)}/101 промахов: {failures[:5]}")


if __name__ == "__main__":
    unittest.main()
