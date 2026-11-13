// Задача 2026-11-03: эталон нутриентов после тепловой обработки.
//
// Роль оракула (A3-TEST-01): `test/fixtures/nutrients_benchmark.json` и
// `test/fixtures/nutrients_benchmark_reference.py` задают независимый
// арифметический Decimal-оракул движка поверх `LOSS_TABLE_JSON` из
// docs/COEFFICIENT_SOURCES.md и продуктов `reference.db` (`mode=ro`).
// Независимость самих коэффициентов потерь от `COEFFICIENT_SOURCES.md`
// проверяется отдельно в `loss_table_test.dart` (18 троек МР 2.3.0419-26)
// и в сверке с готовыми блюдами BLS ниже (±10 % ккал на 100 г).
//
// Дополнительно: «Рис отварной» и «Говядина тушёная» сверяются с готовыми
// продуктами справочника (BLS) — ±10 % ккал на 100 г.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

import 'support/reference_db.dart';

const _fixture = 'test/fixtures/nutrients_benchmark.json';

double? _d(Object? v) => (v as num?)?.toDouble();

void main() {
  late Map<String, dynamic> bench;
  late Map<int, Product> products;

  setUpAll(() async {
    bench = jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
    products = {for (final p in await loadAllReferenceProducts()) p.id: p};
  });

  Dish buildDish(Map<String, dynamic> d) {
    final process = HeatProcess.fromJsonName(d['process']);
    final ings = <Ingredient>[];
    var i = 0;
    for (final raw in (d['ingredients'] as List).cast<Map<String, dynamic>>()) {
      final product = products[raw['productId'] as int]!;
      ings.add(Ingredient(
        id: 'i${i++}',
        product: product,
        weightGrams: _d(raw['grams'])!,
        isGross: raw['isGross'] as bool,
        groupOverride: raw['groupOverride'] == true
            ? LossGroup.fromJsonName(raw['group'])
            : null,
        processOverride:
            HeatProcess.ingredientFromJsonName(raw['processOverride']),
      ));
    }
    final created = DateTime.utc(2026, 11, 3);
    return Dish(
      id: d['name'] as String,
      title: d['name'] as String,
      ingredients: ings,
      customYieldGrams: _d(d['yieldGrams']),
      process: process,
      createdAt: created,
      updatedAt: created,
    );
  }

  test('эталон содержит ≥ 20 блюд и две сверки с готовыми продуктами', () {
    final dishes = bench['dishes'] as List;
    expect(dishes.length, greaterThanOrEqualTo(20));
    final names = dishes.map((d) => (d as Map)['name']).toSet();
    expect(names, containsAll(['Рис отварной', 'Говядина тушёная']));
    final processes = dishes.map((d) => (d as Map)['process']).toSet();
    expect(processes,
        containsAll(['cold', 'boil', 'stew', 'fry', 'bake', 'steam', 'stock', 'legacy']));
    expect((bench['referenceChecks'] as List).length, 2);
  });

  test('снимок продуктов совпадает со справочником, группы — с классификатором',
      () {
    for (final d in (bench['dishes'] as List).cast<Map<String, dynamic>>()) {
      for (final raw in (d['ingredients'] as List).cast<Map<String, dynamic>>()) {
        final p = products[raw['productId'] as int];
        final where = '${d['name']} / ${raw['name']}';
        expect(p, isNotNull, reason: where);
        final snap = raw['snapshot'] as Map<String, dynamic>;
        expect(p!.code, raw['code'], reason: where);
        expect(p.protein, _d(snap['protein']), reason: where);
        expect(p.fat, _d(snap['fat']), reason: where);
        expect(p.carbs, _d(snap['carbs']), reason: where);
        expect(p.wastePct, _d(snap['wastePct']) ?? 0.0, reason: where);
        expect(p.isDishOnly, snap['isDish'], reason: where);
        if (raw['groupOverride'] != true) {
          expect(FoodClassifier.classify(p).name, raw['group'],
              reason: '$where: группа технолога ≠ классификатор');
        }
      }
    }
  });

  test('движок = независимый эталон (построчно и итоги)', () {
    for (final d in (bench['dishes'] as List).cast<Map<String, dynamic>>()) {
      final name = d['name'] as String;
      final res = CalculationEngine.calculate(buildDish(d));
      final e = d['expected'] as Map<String, dynamic>;
      expect(res.rawTotalProtein, _d(e['rawProtein']), reason: '$name: Б сырья');
      expect(res.rawTotalFat, _d(e['rawFat']), reason: '$name: Ж сырья');
      expect(res.rawTotalCarbs, _d(e['rawCarbs']), reason: '$name: У сырья');
      expect(res.cookedProtein, _d(e['cookedProtein']), reason: '$name: Б');
      expect(res.cookedFat, _d(e['cookedFat']), reason: '$name: Ж');
      expect(res.cookedCarbs, _d(e['cookedCarbs']), reason: '$name: У');
      expect(res.cookedKcal, _d(e['cookedKcal']), reason: '$name: ккал');
      expect(res.yieldGrams, _d(e['yieldGrams']), reason: '$name: выход');
      final per100 = _d(e['per100gKcal']);
      if (per100 == null) {
        // Вес не указан: итог на всё блюдо, «на 100 г» не считается.
        expect(res.yieldGrams, 0.0, reason: name);
        expect(res.per100gKcal, 0.0, reason: name);
      } else {
        expect(res.per100gProtein, _d(e['per100gProtein']), reason: '$name: Б/100');
        expect(res.per100gFat, _d(e['per100gFat']), reason: '$name: Ж/100');
        expect(res.per100gCarbs, _d(e['per100gCarbs']), reason: '$name: У/100');
        expect(res.per100gKcal, per100, reason: '$name: ккал/100');
      }

      final ings = (d['ingredients'] as List).cast<Map<String, dynamic>>();
      if (d['process'] == 'legacy') {
        expect(res.lines, isEmpty, reason: '$name: legacy — тройка блюда');
        continue;
      }
      expect(res.lines.length, ings.length, reason: name);
      for (var i = 0; i < ings.length; i++) {
        final le = ings[i]['expected'] as Map<String, dynamic>;
        final line = res.lines[i];
        final where = '$name / ${ings[i]['name']}';
        expect(line.process.name, le['process'], reason: where);
        expect(line.rawProtein, _d(le['rawProtein']), reason: where);
        expect(line.rawFat, _d(le['rawFat']), reason: where);
        expect(line.rawCarbs, _d(le['rawCarbs']), reason: where);
        expect(line.loss.protein, _d(le['lossProtein']), reason: where);
        expect(line.loss.fat, _d(le['lossFat']), reason: where);
        expect(line.loss.carbs, _d(le['lossCarbs']), reason: where);
        expect(line.cookedProtein, _d(le['cookedProtein']), reason: where);
        expect(line.cookedFat, _d(le['cookedFat']), reason: where);
        expect(line.cookedCarbs, _d(le['cookedCarbs']), reason: where);
      }
    }
  });

  test('Рис отварной и Говядина тушёная: ±10 % ккал/100 г к готовому продукту', () {
    final dishes = {
      for (final d in (bench['dishes'] as List).cast<Map<String, dynamic>>())
        d['name'] as String: d
    };
    for (final c in (bench['referenceChecks'] as List).cast<Map<String, dynamic>>()) {
      final name = c['dish'] as String;
      final res = CalculationEngine.calculate(buildDish(dishes[name]!));
      final cooked = products[c['cookedProductId'] as int]!;
      expect(cooked.isDishOnly, isTrue, reason: '$name: эталон — готовый продукт');
      expect(cooked.kcal, _d(c['referenceKcalPer100g']), reason: name);
      final deviation = (res.per100gKcal - cooked.kcal) / cooked.kcal * 100;
      expect(deviation.abs(), lessThanOrEqualTo(_d(c['tolerancePct'])!),
          reason: '$name: ${res.per100gKcal} ккал/100 г против ${cooked.kcal}');
      expect(res.per100gKcal, _d(c['modelKcalPer100g']), reason: name);
    }
  });
}
