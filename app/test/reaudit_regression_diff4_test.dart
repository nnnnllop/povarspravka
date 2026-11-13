// DIFFERENTIAL / REGRESSION HARNESS — part 4: effectiveYieldGrams for
// NON-legacy dishes and the customYieldGrams validation gap.
//
// 2026-11-03: the yield-physics branch (`yield_physics.dart`) was removed.
// A non-legacy dish without an entered weight has NO yield (0: totals for
// the whole dish, «укажите вес готового блюда»); legacy keeps «sum of net».
// Process names of the removed model map to the new ones: soup/grain →
// boil, fryMain → fry.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

import 'reaudit_regression_old_lib.dart';

Product p_(String name, {double pr = 1, double fa = 1, double ca = 1}) =>
    Product(
        id: 1,
        code: '1',
        name: name,
        groupId: 0,
        source: 'skurikhin',
        protein: pr,
        fat: fa,
        carbs: ca,
        kcal: 50);

Dish d_(List<Ingredient> ings,
        {double? y, HeatProcess process = HeatProcess.boil}) =>
    Dish(
      id: 'x',
      ingredients: ings,
      customYieldGrams: y,
      process: process,
      retentionProtein: process == HeatProcess.legacy ? .94 : 1.0,
      retentionFat: process == HeatProcess.legacy ? .88 : 1.0,
      retentionCarbs: process == HeatProcess.legacy ? .91 : 1.0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  test('yield differential: no guessed yield for non-legacy dishes', () {
    print('\n=== [17] effectiveYieldGrams: old (sum net / custom) vs new '
        '(entered weight only for non-legacy) ===');
    final cases = <String, Dish>{
      'boil (ex-soup), 500 g water only': d_([
        Ingredient(
            id: 'w',
            product: p_('Вода питьевая', pr: 0, fa: 0, ca: 0),
            weightGrams: 500)
      ]),
      'stock, 800 g water + 300 g meat': d_(
          [
            Ingredient(id: 'w', product: p_('Вода питьевая', pr: 0, fa: 0, ca: 0), weightGrams: 800),
            Ingredient(id: 'm', product: p_('Говядина 1 кат.', pr: 18.6, fa: 16), weightGrams: 300),
          ],
          process: HeatProcess.stock),
      'boil (ex-grain), 60 g buckwheat + 10 g butter': d_(
          [
            Ingredient(id: 'g', product: p_('Крупа гречневая ядрица', pr: 12.6, fa: 3.3, ca: 57.1), weightGrams: 60),
            Ingredient(id: 'b', product: p_('Масло сливочное', pr: 0.8, fa: 72.5, ca: 1.3), weightGrams: 10),
          ],
          process: HeatProcess.fromJsonName('grain')),
      'water + горошек зелёный (Water-pea containing)': d_(
          [
            Ingredient(id: '1', product: p_('Вода питьевая', pr: 0, fa: 0, ca: 0), weightGrams: 200),
            Ingredient(id: '2', product: p_('Горошек зелёный консервированный', pr: 3.6, fa: 0.2, ca: 6.8), weightGrams: 150),
          ],
          process: HeatProcess.fromJsonName('soup')),
      'fry (ex-fryMain), 300 g potatoes + 30 g oil': d_(
          [
            Ingredient(id: 'p', product: p_('Картофель', pr: 2, fa: 0.4, ca: 16.3), weightGrams: 300),
            Ingredient(id: 'o', product: p_('Масло подсолнечное', pr: 0, fa: 99.9, ca: 0), weightGrams: 30),
          ],
          process: HeatProcess.fromJsonName('fryMain')),
    };
    for (final e in cases.entries) {
      final d = e.value;
      print('  ${e.key}');
      print('    old effectiveYield = ${oldEffectiveYield(d)}');
      print('    new effectiveYield = ${d.effectiveYieldGrams} '
          '(process=${d.process.name}, rawNet=${d.totalRawNetGrams})');
      final oldR = OldEngine.calculate(d);
      final newR = CalculationEngine.calculate(d);
      print('    old kcal=${oldR.cookedKcal} per100g=${oldR.per100gKcal}');
      print('    new kcal=${newR.cookedKcal} per100g=${newR.per100gKcal}');
      expect(d.process.isLegacy, isFalse, reason: e.key);
      expect(d.effectiveYieldGrams, 0,
          reason: '${e.key}: weight is not guessed');
      expect(newR.hasYield, isFalse, reason: e.key);
      expect(newR.per100gKcal, 0, reason: e.key);
      // The cook enters the weight — it is used as is.
      expect(d.copyWith(customYieldGrams: 250).effectiveYieldGrams, 250,
          reason: e.key);
    }

    print('\n=== [18] customYieldGrams gap: Dish accepts >= 0.1, validator >= 1.0 ===');
    for (final y in <double>[0.09, 0.1, 0.3, 0.5, 0.99, 1.0]) {
      final d = d_([Ingredient(id: 'i', product: p_('Морковь'), weightGrams: 100)], y: y);
      final oldV = () {
        try {
          OldValidation.dish(d);
          return 'valid';
        } catch (e) {
          return 'invalid';
        }
      }();
      final eff = d.effectiveYieldGrams;
      String calc;
      try {
        final r = CalculationEngine.calculate(d);
        calc = 'ok per100gKcal=${r.per100gKcal}';
      } catch (e) {
        calc = 'THROWS ${e.runtimeType}';
      }
      print('  y=$y: oldValidator=$oldV newEffectiveYield=$eff calculate=$calc');
      // RA-23: one threshold — below it the weight counts as «not entered».
      expect(eff, y >= CalculationValidation.minCustomYieldGrams ? y : 0,
          reason: 'y=$y');
    }
    print('  constants: minCustomYieldGrams='
        '${CalculationValidation.minCustomYieldGrams}, '
        'CalculationResult.portion() lower bound = .1');

    print('\n=== [19] water + sugar, boil without weight: nothing is guessed ===');
    final w = d_([
      Ingredient(id: 'w', product: p_('Вода питьевая', pr: 0, fa: 0, ca: 0), weightGrams: 500),
      Ingredient(id: 's', product: p_('Сахар-песок', pr: 0, fa: 0, ca: 99.8), weightGrams: 20),
    ]);
    final r = CalculationEngine.calculate(w);
    print('  500 g water + 20 g sugar, boil: yield=${r.yieldGrams} '
        'carbs=${r.cookedCarbs} per100gCarbs=${r.per100gCarbs} '
        'per100gKcal=${r.per100gKcal}');
    print('  (old yield would be ${oldEffectiveYield(w)}; '
        'with the weighed 520 g → ${(r.cookedCarbs * 100 / 520).toStringAsFixed(2)} g/100 g)');
    expect(r.yieldGrams, 0);
    expect(r.cookedCarbs, greaterThan(0),
        reason: 'totals for the whole dish are still computed');
    final weighed = CalculationEngine.calculate(w.copyWith(customYieldGrams: 520));
    expect(weighed.per100gCarbs,
        closeTo(weighed.cookedCarbs * 100 / 520, 0.01));
  });
}
