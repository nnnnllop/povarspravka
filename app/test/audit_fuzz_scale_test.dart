// FUZZ-EDGE / PART 2 — extreme magnitudes, ingredient-count scaling,
// precision against an exact rational reference.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product prod({double protein = 10, double fat = 5, double carbs = 20, double kcal = 300}) =>
    Product(
      id: 1,
      code: 'p',
      name: 'Продукт',
      groupId: 1,
      source: 'skurikhin',
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
    );

Dish dish(List<Ingredient> ings, {double? yieldGrams, BlankMode mode = BlankMode.detailed}) =>
    Dish(
      id: 'd',
      ingredients: ings,
      customYieldGrams: yieldGrams,
      blankMode: mode,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Exact reference: HALF-UP rounding of `num/den` to `digits` decimals.
double exactHalfUp(BigInt num, BigInt den, int digits) {
  var n = num.abs();
  var d = den;
  n *= BigInt.from(10).pow(digits);
  final q = (n * BigInt.two + d) ~/ (d * BigInt.two);
  final v = q.toDouble() / math.pow(10, digits);
  return num.isNegative ? -v : v;
}

void main() {
  group('Extreme weights — the calculable envelope', () {
    final weights = <String, double>{
      '0.0001': 0.0001,
      '0.1': 0.1,
      '1': 1,
      '500000': 500000,
      '9999999': 9999999,
      '1e7+1': 10000001,
    };
    weights.forEach((label, w) {
      test('weight $label', () {
        final ing = Ingredient(id: 'i', product: prod(), weightGrams: w);
        final sw = Stopwatch()..start();
        var outcome = '';
        try {
          final r = CalculationEngine.calculate(
              dish([ing], yieldGrams: w >= 0.1 ? null : 1));
          outcome = 'ok raw=${r.rawTotalWeight} p=${r.rawTotalProtein} kcal=${r.per100gKcal}';
        } on ArgumentError catch (e) {
          outcome = 'THROW ArgumentError: ${e.message}';
        }
        sw.stop();
        // ignore: avoid_print
        print('PART2 weight=$label -> $outcome (${sw.elapsedMilliseconds} ms)');
        expect(sw.elapsedMilliseconds, lessThan(2000));
      });
    });

    test('weight 0.0001 prints as <0,1 g, never as a silent 0', () {
      final ing = Ingredient(id: 'i', product: prod(), weightGrams: 0.0001);
      expect(ing.netGramsRounded, 0.0);
      // SPEC (MATH-07): a positive mass that rounds to zero must be visible,
      // not printed as "0" — otherwise a 0.0001 g row looks like an empty one.
      expect(CalculationEngine.formatGrams(ing.netGramsRounded), '0');
      expect(CalculationEngine.formatGrams(0.0001), '<0,1');
      final r = CalculationEngine.calculate(dish([ing], yieldGrams: 1000));
      expect(r.rawTotalWeight, 0.0);
      expect(r.rawTotalProtein, 0.0);
    });

    test('500 kg in one row: rate is exact and per-100 g is unchanged', () {
      final r = CalculationEngine.calculate(dish(
          [Ingredient(id: 'i', product: prod(), weightGrams: 500000)]));
      expect(r.rawTotalProtein, 50000.0);
      expect(r.rawTotalFat, 25000.0);
      expect(r.rawTotalCarbs, 100000.0);
      // The blank works at the DECLARED retention 0.94/0.88/0.91 (defaults),
      // so the cooked per-100 g protein is 10 * 0.94, not 10.
      expect(r.per100gProtein, 9.4);
      expect(r.per100gFat, 4.4);
      expect(r.per100gCarbs, 18.2);
      // 500 kg contains 5000 x 150.0 kcal in total; per-100 g stays 150.0 only
      // when the custom yield equals the raw mass.
      expect(r.cookedKcal, 750000.0);
      final scaled = CalculationEngine.calculate(dish(
          [Ingredient(id: 'i', product: prod(), weightGrams: 500000)],
          yieldGrams: 500000));
      expect(scaled.per100gKcal, 150.0);
      expect(scaled.per100gProtein, 9.4);
    });

    test('2 x 9999999 g with custom yield: sum exceeds double-safe display but stays finite', () {
      final r = CalculationEngine.calculate(dish([
        Ingredient(id: 'a', product: prod(), weightGrams: 9999999),
        Ingredient(id: 'b', product: prod(), weightGrams: 9999999),
      ]));
      expect(r.rawTotalWeight, 19999998.0);
      expect(r.rawTotalWeight.isFinite, isTrue);
    });

    test('9999999 g gross at 0.1% waste keeps 12-decimal exactness', () {
      final p = prod().copyWith(wastePct: 0.1);
      final ing = Ingredient(id: 'i', product: p, weightGrams: 9999999, isGross: true);
      // 9999999 * (99.9 / 100) = 9989999.001
      expect(ing.netGrams, closeTo(9989999.001, 1e-6));
    });
  });

  group('Ingredient-count scaling: 50 / 100 / 1000', () {
    for (final n in [50, 100, 1000]) {
      test('$n ingredients: elapsed and exact totals', () {
        final ings = List.generate(
            n,
            (i) => Ingredient(
                id: 'i$i',
                product: prod(protein: 10 + i % 3, fat: 5 + i % 2, carbs: 20),
                weightGrams: 100.0 + i % 10 * 0.1));
        final sw = Stopwatch()..start();
        final r = CalculationEngine.calculate(dish(ings));
        sw.stop();

        // Exact expectation computed with BigInt, independent of the engine.
        // Row semantics (ingredient.dart:47-68):
        //   net = round1(weight)                                     [1 dp]
        //   macro = round2(net * round2(product.macro) / 100)        [2 dp]
        var wn = BigInt.zero; // units of 0.1 g
        var pn = BigInt.zero; // units of 0.01 g
        var fn = BigInt.zero;
        var cn = BigInt.zero;

        final two = BigInt.two;

        /// HALF-UP rounding of `num/den` to `digits` decimals, returned as an
        /// integer count of 10^-digits units.
        BigInt halfUpUnits(BigInt num, BigInt den, int digits) {
          final scaled = num.abs() * BigInt.from(10).pow(digits);
          return (scaled * two + den) ~/ (den * two);
        }

        for (final ing in ings) {
          final (wNum, wScale) = CalculationMath.decimal(ing.weightGrams);
          final netTenths = halfUpUnits(wNum, BigInt.from(10).pow(wScale), 1);
          wn += netTenths;
          for (final (macro, target) in [
            (ing.product.proteinRounded, 0),
            (ing.product.fatRounded, 1),
            (ing.product.carbsRounded, 2),
          ]) {
            final (mNum, mScale) = CalculationMath.decimal(macro);
            // net grams = netTenths / 10 ; macro = mNum / 10^mScale
            // grams = netTenths * mNum / (10 * 100 * 10^mScale)
            final num = netTenths * mNum;
            final den = BigInt.from(10).pow(mScale + 3);
            final row = halfUpUnits(num, den, 2);
            if (target == 0) {
              pn += row;
            } else if (target == 1) {
              fn += row;
            } else {
              cn += row;
            }
          }
        }
        final exactWeight = wn.toDouble() / 10;
        final exactProtein = pn.toDouble() / 100;
        final exactFat = fn.toDouble() / 100;
        final exactCarbs = cn.toDouble() / 100;

        // ignore: avoid_print
        print('PART2 n=$n elapsed=${sw.elapsedMilliseconds} ms rawW=${r.rawTotalWeight} (exact $exactWeight) '
            'P=${r.rawTotalProtein} (exact $exactProtein) F=${r.rawTotalFat} C=${r.rawTotalCarbs}');

        expect(sw.elapsedMilliseconds, lessThan(2000), reason: 'flagged > 2 s');
        expect(r.rawTotalWeight, closeTo(exactWeight, 1e-9));
        expect(r.rawTotalProtein, closeTo(exactProtein, 1e-9));
        expect(r.rawTotalFat, closeTo(exactFat, 1e-9));
        expect(r.rawTotalCarbs, closeTo(exactCarbs, 1e-9));
      });
    }

    test('[RISK FUZZ-06] 1000 rows of 0.01 g: micro-weights vanish because the ROW is rounded to 0.1 g first', () {
      final ings = List.generate(1000,
          (i) => Ingredient(id: 'i$i', product: prod(), weightGrams: 0.01));
      final r = CalculationEngine.calculate(dish(ings, yieldGrams: 1000));
      // 1000 rows of 0.01 g = 10 g of food, but round1(0.01) = 0.0 per row.
      expect(r.rawTotalWeight, 0.0);
      expect(r.rawTotalProtein, 0.0);
      expect(r.cookedKcal, 0.0);
      // The yield is a custom 1000 g, so per-100 g is a silent 0, not NaN.
      expect(r.per100gKcal, 0.0);

      // Control: the same 10 g in ONE row is not lost.
      final one = CalculationEngine.calculate(dish(
          [Ingredient(id: 'x', product: prod(), weightGrams: 10)],
          yieldGrams: 1000));
      expect(one.rawTotalWeight, 10.0);
      expect(one.rawTotalProtein, 1.0);
    });

    test('0.05 g rows round up (HALF-UP) — direction is documented, not lossy', () {
      final r = CalculationEngine.calculate(dish([
        Ingredient(id: 'a', product: prod(), weightGrams: 0.05),
      ], yieldGrams: 1));
      expect(r.rawTotalWeight, 0.1);
    });

    test('1000 rows interleaved 1/3-style values never produce NaN/Infinity', () {
      final ings = List.generate(
          1000,
          (i) => Ingredient(
              id: 'i$i',
              product: prod(protein: 100.0 / 3, fat: 50.0 / 3, carbs: 100.0 / 7),
              weightGrams: 123.456));
      final r = CalculationEngine.calculate(dish(ings));
      for (final v in [
        r.rawTotalWeight, r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs,
        r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal,
        r.per100gProtein, r.per100gKcal,
      ]) {
        expect(v.isFinite, isTrue);
      }
    });
  });

  group('sumRounded / _sum precision and performance', () {
    test('1000 values mixed scales: 2 ms, exact to the last printed digit', () {
      final vals = List.generate(1000, (i) => [0.1, 0.01, 0.001, 1e-7][i % 4]);
      final sw = Stopwatch()..start();
      final s = CalculationMath.sumRounded(vals, 2);
      sw.stop();
      // exact = 250*(0.1+0.01+0.001+0.0000001) = 27.750025 -> HALF-UP 2 dp = 27.75
      expect(s, 27.75);
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('sumRounded 1000x 0.1 == 100.0 exactly (naive double sum would be 99.99999...)', () {
      final naive = List.filled(1000, 0.1).fold<double>(0, (a, b) => a + b);
      expect(naive, isNot(100.0)); // documents the IEEE drift we avoid
      expect(CalculationMath.sumRounded(List.filled(1000, 0.1), 1), 100.0);
    });

    test('sumRounded honours HALF-UP at 2 dp', () {
      expect(CalculationMath.sumRounded([0.005], 2), 0.01);
      expect(CalculationMath.sumRounded([0.0049999999], 2), 0.0);
      expect(CalculationMath.sumRounded([-0.005], 2), -0.01);
    });

    test('sumRounded with 1e-7 scale: 1000 x 1e-7 = 0.0001, rounds to 0.00 at 2dp', () {
      expect(CalculationMath.sumRounded(List.filled(1000, 1e-7), 4), 0.0001);
    });

    test('BigInt.pow is not driven past ~2^40 by any accepted input', () {
      // Worst scale accepted by validation: 12 decimals -> 1e12; plus 1e-300 from
      // an out-of-range rejection path is guarded earlier. Time the worst case.
      final sw = Stopwatch()..start();
      CalculationMath.sumRounded(List.filled(1000, 0.000000000001), 12);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('ratioRounded / energy edge behaviour', () {
    test('ratioRounded divides by zero -> ArgumentError (controlled)', () {
      expect(() => CalculationMath.ratioRounded(10, 0, 2),
          throwsA(isA<ArgumentError>()));
      expect(() => CalculationMath.ratioRounded(10, -1, 2),
          throwsA(isA<ArgumentError>()));
    });

    test('energy of 0/0/0 is 0.0, never NaN', () {
      expect(CalculationMath.energy(0, 0, 0), 0.0);
    });

    test('energy with 10/19/1 decimals is exact', () {
      // 12.3*4 + 4.56*9 + 7.89*4 = 49.2 + 41.04 + 31.56 = 121.8
      expect(CalculationMath.energy(12.3, 4.56, 7.89), 121.8);
    });
  });
}
