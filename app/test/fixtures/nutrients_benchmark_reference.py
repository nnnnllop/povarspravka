"""Независимый эталон расчёта нутриентов после тепловой обработки (задача 2026-11-03).

Роль оракула (A3-TEST-01): независимая Decimal-референс-модель арифметики
движка; скрипт НЕ импортирует и не читает Dart-код. Независимый оракул
первоисточника для 18 подтверждённых троек МР 2.3.0419-26 находится в
`app/test/loss_table_test.dart`. Источники данных здесь:
  * таблица потерь — JSON-блок docs/COEFFICIENT_SOURCES.md;
  * продукты — app/assets/db/reference.db, открытая ТОЛЬКО для чтения (mode=ro);
  * состав блюд, группы продуктов и вес готового блюда — ниже (DISHES),
    группы назначены вручную (тест сверяет их с классификатором).

Округление — как в бланке: нетто HALF-UP 0,1 г; Б/Ж/У сырья и готовые Б/Ж/У строки
HALF-UP 0,01 г; итог = сумма строк; ккал = 4Б + 9Ж + 4У от итогов, HALF-UP 0,1;
«на 100 г» — итог × 100 / вес, HALF-UP 0,01 (ккал 0,1). Десятичная арифметика — Decimal(str(x)).

Запуск (из корня репозитория или откуда угодно):
    python app/test/fixtures/nutrients_benchmark_reference.py
→ перезаписывает app/test/fixtures/nutrients_benchmark.json.
"""
import json
import re
import sqlite3
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent.parent
REPO = APP.parent
DB = APP / 'assets' / 'db' / 'reference.db'
SOURCES = REPO / 'docs' / 'COEFFICIENT_SOURCES.md'
OUT = HERE / 'nutrients_benchmark.json'


def D(x):
    return Decimal(repr(float(x))) if not isinstance(x, Decimal) else x


def hu(x, digits):
    q = Decimal(1).scaleb(-digits)
    return D(x).quantize(q, rounding=ROUND_HALF_UP)


def num(x):
    """Decimal → число JSON без хвостовых нулей."""
    f = float(x)
    return int(f) if f == int(f) else f


def load_loss_table():
    text = SOURCES.read_text(encoding='utf-8')
    m = re.search(r'<!-- LOSS_TABLE_JSON_BEGIN -->\s*```json\s*(.*?)```\s*<!-- LOSS_TABLE_JSON_END -->',
                  text, re.S)
    return json.loads(m.group(1))


# (productId, граммы, брутто?, группа, группа задана вручную?, способ ингредиента|None)
def I(pid, g, gross, group, manual=False, process=None):
    return dict(productId=pid, grams=g, isGross=gross, group=group,
                groupOverride=manual, processOverride=process)


DISHES = [
    dict(name='Картофель отварной', process='boil', yieldGrams=700, ingredients=[
        I(742, 1000, True, 'rootTuber'), I(1089, 10, False, 'other')]),
    dict(name='Пюре картофельное', process='boil', yieldGrams=1000, ingredients=[
        I(742, 1100, True, 'rootTuber'), I(53, 150, False, 'dairy'), I(510, 40, False, 'fatOil')]),
    dict(name='Каша гречневая рассыпчатая', process='boil', yieldGrams=1000, ingredients=[
        I(654, 400, False, 'grainPasta'), I(510, 20, False, 'fatOil'), I(1089, 5, False, 'other')]),
    dict(name='Рис отварной', process='boil', yieldGrams=None, waterBalance=(10322, 10323),
         ingredients=[I(10322, 1000, False, 'grainPasta')]),
    dict(name='Говядина тушёная', process='stew', yieldGrams=None, waterBalance=(13684, 13685),
         ingredients=[I(13684, 1000, False, 'meat')]),
    dict(name='Макароны отварные', process='boil', yieldGrams=1500, ingredients=[
        I(552, 500, False, 'grainPasta')]),
    dict(name='Борщ', process='boil', yieldGrams=2000, ingredients=[
        I(779, 200, True, 'rootTuber'), I(712, 250, True, 'vegetable'), I(742, 200, True, 'rootTuber'),
        I(768, 100, True, 'rootTuber'), I(738, 100, True, 'vegetable', process='fry'),
        I(533, 20, False, 'fatOil', process='fry'), I(818, 30, False, 'vegetable', process='stew'),
        I(98, 100, False, 'dairy', process='cold')]),
    dict(name='Бульон мясной', process='stock', yieldGrams=3000, ingredients=[
        I(174, 1000, False, 'meat'), I(768, 50, True, 'rootTuber'), I(738, 50, True, 'vegetable'),
        I(1089, 10, False, 'other')]),
    dict(name='Куры жареные', process='fry', yieldGrams=700, ingredients=[
        I(192, 1000, False, 'poultry'), I(533, 50, False, 'fatOil')]),
    dict(name='Треска жареная', process='fry', yieldGrams=450, ingredients=[
        I(390, 1000, True, 'fish'), I(609, 50, False, 'flourBread'), I(533, 50, False, 'fatOil')]),
    dict(name='Минтай на пару', process='steam', yieldGrams=800, ingredients=[
        I(383, 1000, False, 'fish')]),
    dict(name='Омлет натуральный', process='bake', yieldGrams=600, ingredients=[
        I(159, 500, True, 'egg'), I(53, 200, False, 'dairy'), I(510, 20, False, 'fatOil')]),
    dict(name='Запеканка творожная', process='bake', yieldGrams=1100, ingredients=[
        I(47, 1000, False, 'dairy'), I(930, 100, False, 'sugarHoney'), I(159, 115, True, 'egg'),
        I(613, 60, False, 'grainPasta'), I(98, 50, False, 'dairy')]),
    dict(name='Сырники', process='fry', yieldGrams=600, ingredients=[
        I(47, 500, False, 'dairy'), I(609, 80, False, 'flourBread'), I(159, 60, True, 'egg'),
        I(930, 50, False, 'sugarHoney'), I(533, 40, False, 'fatOil')]),
    dict(name='Капуста тушёная', process='stew', yieldGrams=1000, ingredients=[
        I(712, 1250, True, 'vegetable'), I(768, 125, True, 'rootTuber'), I(738, 120, True, 'vegetable'),
        I(818, 50, False, 'vegetable'), I(533, 40, False, 'fatOil')]),
    dict(name='Свинина запечённая', process='bake', yieldGrams=650, ingredients=[
        I(183, 1176, True, 'meat'), I(1089, 12, False, 'other')]),
    dict(name='Пюре из гороха', process='boil', yieldGrams=1250, ingredients=[
        I(674, 500, False, 'legumes'), I(533, 30, False, 'fatOil', process='cold')]),
    dict(name='Яблоки печёные', process='bake', yieldGrams=750, ingredients=[
        I(875, 1000, True, 'fruitBerry'), I(930, 100, False, 'sugarHoney'), I(991, 50, False, 'sugarHoney')]),
    dict(name='Винегрет (вес не указан)', process='cold', yieldGrams=None, ingredients=[
        I(779, 300, True, 'rootTuber', process='boil'), I(742, 300, True, 'rootTuber', process='boil'),
        I(768, 150, True, 'rootTuber', process='boil'), I(738, 100, True, 'vegetable'),
        I(533, 50, False, 'fatOil')]),
    dict(name='Каша пшённая молочная', process='boil', yieldGrams=1000, ingredients=[
        I(665, 200, False, 'grainPasta'), I(53, 800, False, 'dairy'), I(930, 20, False, 'sugarHoney'),
        I(510, 20, False, 'fatOil')]),
    dict(name='Блины', process='fry', yieldGrams=1100, ingredients=[
        I(609, 400, False, 'flourBread'), I(53, 800, False, 'dairy'), I(159, 115, True, 'egg'),
        I(930, 30, False, 'sugarHoney'), I(533, 40, False, 'fatOil')]),
    dict(name='Куриная грудка на пару', process='steam', yieldGrams=750, ingredients=[
        I(14369, 1000, False, 'poultry')]),
    dict(name='Макароны запечённые с сыром', process='bake', yieldGrams=900, ingredients=[
        I(552, 300, False, 'grainPasta', process='boil'), I(137, 100, False, 'dairy'),
        I(510, 30, False, 'fatOil')]),
    dict(name='Картофель жареный со шпиком', process='fry', yieldGrams=600, ingredients=[
        I(742, 1000, True, 'rootTuber'), I(182, 100, True, 'fatOil', manual=True)]),
    dict(name='Говядина тушёная (старый расчёт)', process='legacy', yieldGrams=None, ingredients=[
        I(174, 1000, False, 'meat'), I(738, 100, True, 'vegetable')]),
]

# Валидация по готовому продукту справочника (±10 % ккал/100 г).
TOLERANCE_PCT = 10


def main():
    loss = load_loss_table()
    db = sqlite3.connect(f'file:{DB.as_posix()}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row

    def product(pid):
        r = db.execute('SELECT id, code, name, waste_pct, protein, fat, carbs, kcal, water, is_dish '
                       'FROM product WHERE id = ?', (pid,)).fetchone()
        assert r is not None, pid
        return dict(r)

    out = []
    checks = []
    for dish in DISHES:
        proc = dish['process']
        y = dish['yieldGrams']
        if 'waterBalance' in dish:
            raw_id, cooked_id = dish['waterBalance']
            raw, cooked = product(raw_id), product(cooked_id)
            mass = D(dish['ingredients'][0]['grams'])
            # Вес «измеренный поваром» для сверки — баланс сухих веществ по воде
            # справочника: масса × (100 − вода_сырое) / (100 − вода_готовое).
            y = hu(mass * (100 - D(raw['water'])) / (100 - D(cooked['water'])), 1)
        lines = []
        for ing in dish['ingredients']:
            p = product(ing['productId'])
            waste = D(p['waste_pct'] or 0)
            g = D(ing['grams'])
            net = hu(g * (100 - waste) / 100, 1) if ing['isGross'] else hu(g, 1)
            raw = [hu(net * hu(p[k], 2) / 100, 2) for k in ('protein', 'fat', 'carbs')]
            if proc == 'legacy':
                ip, lp = 'legacy', None
            else:
                ip = ing['processOverride'] or ('cold' if p['is_dish'] else proc)
                lp = loss['cold'] if ip == 'cold' else loss['table'][ip][ing['group']]
            cooked = None if lp is None else [
                hu(r * (100 - D(lp[k])) / 100, 2) for r, k in zip(raw, ('p', 'f', 'c'))]
            lines.append(dict(
                productId=p['id'], code=p['code'], name=p['name'],
                grams=num(g), isGross=ing['isGross'], group=ing['group'],
                groupOverride=ing['groupOverride'], processOverride=ing['processOverride'],
                snapshot=dict(protein=p['protein'], fat=p['fat'], carbs=p['carbs'],
                              wastePct=p['waste_pct'], isDish=bool(p['is_dish'])),
                expected=dict(
                    process=ip, net=num(net),
                    rawProtein=num(raw[0]), rawFat=num(raw[1]), rawCarbs=num(raw[2]),
                    **({} if cooked is None else dict(
                        lossProtein=lp['p'], lossFat=lp['f'], lossCarbs=lp['c'],
                        cookedProtein=num(cooked[0]), cookedFat=num(cooked[1]),
                        cookedCarbs=num(cooked[2]))))))
        raw_tot = [sum((D(l['expected'][k]) for l in lines), Decimal(0))
                   for k in ('rawProtein', 'rawFat', 'rawCarbs')]
        if proc == 'legacy':
            ret = [Decimal('94'), Decimal('88'), Decimal('91')]  # 0,94 / 0,88 / 0,91 (S2, S5)
            ck = [hu(t * r / 100, 2) for t, r in zip(raw_tot, ret)]
            yy = hu(y, 1) if y else hu(sum((D(l['expected']['net']) for l in lines), Decimal(0)), 1)
        else:
            ck = [sum((D(l['expected'][k]) for l in lines), Decimal(0))
                  for k in ('cookedProtein', 'cookedFat', 'cookedCarbs')]
            yy = hu(y, 1) if y else Decimal(0)
        kcal = hu(4 * ck[0] + 9 * ck[1] + 4 * ck[2], 1)
        exp = dict(rawProtein=num(raw_tot[0]), rawFat=num(raw_tot[1]), rawCarbs=num(raw_tot[2]),
                   cookedProtein=num(ck[0]), cookedFat=num(ck[1]), cookedCarbs=num(ck[2]),
                   cookedKcal=num(kcal), yieldGrams=num(yy))
        if yy > 0:
            exp.update(per100gProtein=num(hu(ck[0] * 100 / yy, 2)), per100gFat=num(hu(ck[1] * 100 / yy, 2)),
                       per100gCarbs=num(hu(ck[2] * 100 / yy, 2)), per100gKcal=num(hu(kcal * 100 / yy, 1)))
        else:
            exp.update(per100gProtein=None, per100gFat=None, per100gCarbs=None, per100gKcal=None)
        out.append(dict(name=dish['name'], process=proc,
                        yieldGrams=None if not yy or (proc == 'legacy' and not y) else num(yy),
                        ingredients=lines, expected=exp))
        if 'waterBalance' in dish:
            cooked = product(dish['waterBalance'][1])
            ref = D(cooked['kcal'])
            got = hu(kcal * 100 / yy, 1)
            dev = hu((got - ref) * 100 / ref, 1)
            checks.append(dict(dish=dish['name'], rawProductId=dish['waterBalance'][0],
                               cookedProductId=cooked['id'], cookedProductName=cooked['name'],
                               referenceKcalPer100g=num(ref), modelKcalPer100g=num(got),
                               deviationPct=num(dev), tolerancePct=TOLERANCE_PCT,
                               yieldMethod='масса × (100 − вода сырого) / (100 − вода готового)'))
            assert abs(dev) <= TOLERANCE_PCT, (dish['name'], dev)
    doc = dict(
        description='Эталон нутриентов после тепловой обработки (задача 2026-11-03). '
                    'Ожидания посчитаны независимым скриптом без Dart-кода.',
        generator='app/test/fixtures/nutrients_benchmark_reference.py',
        lossTable='docs/COEFFICIENT_SOURCES.md (LOSS_TABLE_JSON)',
        dishes=out, referenceChecks=checks)
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + '\n', encoding='utf-8', newline='\n')
    for c in checks:
        print(c['dish'], c['modelKcalPer100g'], 'vs', c['referenceKcalPer100g'], c['deviationPct'], '%')
    print('dishes', len(out))


if __name__ == '__main__':
    main()
