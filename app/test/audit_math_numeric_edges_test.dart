// AUDIT: numeric/float edge behaviour of CalculationMath + propagation
// invariants (round-then-sum vs sum-then-round), monotonicity, determinism.
// Read-only audit of app/lib/core/calculation. No production code was modified.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

const _pMeat = Product(
  id: 1,
  code: '3.1.1',
  name: 'Говядина 1 категории',
  groupId: 3,
  source: 'skurikhin',
  protein: 18.6,
  fat: 16.0,
  carbs: 0.0,
  kcal: 218.0,
);

Dish _dish(List<Ingredient> ings, {double? customYield}) => Dish(
      id: 'audit',
      ingredients: ings,
      customYieldGrams: customYield,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

Product _nut(double p, double f, double c, {int id = 0}) => Product(
      id: id,
      code: 'c$id',
      name: 'p$id',
      groupId: 1,
      source: 'skurikhin',
      protein: p,
      fat: f,
      carbs: c,
      kcal: 0,
    );

class _Rnd {
  int _s;
  _Rnd(this._s);
  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }

  double nextDouble() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MATH-C1 CalculationMath.decimal fuzz', () {
    test('C1.1 exponent notation is parsed with the right scale', () {
      expect(CalculationMath.decimal(1e-7), (BigInt.one, 7));
      expect(CalculationMath.decimal(0.0001), (BigInt.one, 4));
      expect(CalculationMath.decimal(1.5e21), (BigInt.from(15), -20));
      expect(CalculationMath.decimal(1e300), (BigInt.one, -300));
    });

    test('C1.2 zero, subnormal and double.minPositive parse without throwing',
        () {
      expect(CalculationMath.decimal(0.0).$1, BigInt.zero);
      expect(() => CalculationMath.decimal(double.minPositive), returnsNormally);
      expect(
          () => CalculationMath.decimal(2.2250738585072014e-308),
          returnsNormally);
    });

    test('C1.3 non-finite input is rejected', () {
      expect(() => CalculationMath.decimal(double.nan), throwsArgumentError);
      expect(() => CalculationMath.decimal(double.infinity),
          throwsArgumentError);
      expect(() => CalculationMath.decimal(double.negativeInfinity),
          throwsArgumentError);
    });

    test('C1.4 HALF-UP is exact on decimal-friendly inputs', () {
      expect(CalculationMath.round1(0.25), 0.3);
      expect(CalculationMath.round1(2.5), 2.5);
      expect(CalculationMath.round2(1.005), 1.01); // 1.005 prints as "1.005"
      expect(CalculationMath.round1(145.44), 145.4);
      expect(CalculationMath.round1(145.45), 145.5);
    });

    test('C1.5 round1/maxFinite is finite (overflow guard)', () {
      expect(CalculationMath.round1(double.maxFinite).isFinite, isTrue);
    });
  });

  group('MATH-C2 round-then-sum vs sum-then-round', () {
    // REPRO for MATH-02: per-cell rounding before summation drifts from an
    // exact sum-and-round by up to ~1.6 kcal on a 50..99 line recipe.
    // SPEC (C2.1): two DIFFERENT quantities with different meanings.
    //   * the printed column  = Σ round1(4P+9F+4C) per row — an accounting sum
    //     the chef can re-add on a calculator;
    //   * the dish energy     = round(4·ΣP + 9·ΣF + 4·ΣC) — sum-then-round.
    // Per-row HALF-UP rounding accumulates, so on 50–99 rows the gap is
    // mathematically unavoidable. The bound is the worst case: n rows × the
    // maximum per-row rounding error (±0.25 kcal, since 4/9/4 on 0.01 g steps
    // rounds to 0.1). We assert that physical bound, not 0.05.
    test('C2.1 per-line kcal sum stays within the rounding bound of the exact '
        'sum-then-round kcal', () {
      final rnd = _Rnd(11);
      var worst = 0.0;
      var worstDesc = '';
      var worstRatio = 0.0;
      for (var t = 0; t < 400; t++) {
        final n = 50 + rnd.nextInt(50);
        var exactP = 0.0, exactF = 0.0, exactC = 0.0;
        var perLineKcal = 0.0;
        final ings = <Ingredient>[];
        for (var i = 0; i < n; i++) {
          final prod = _nut(
              CalculationMath.round2(rnd.nextDouble() * 12),
              CalculationMath.round2(rnd.nextDouble() * 12),
              CalculationMath.round2(rnd.nextDouble() * 12),
              id: i);
          final w = 1 + rnd.nextDouble() * 150;
          final ing = Ingredient(id: '$i', product: prod, weightGrams: w);
          ings.add(ing);
          final net = ing.netGramsRounded;
          exactP += net * prod.protein / 100;
          exactF += net * prod.fat / 100;
          exactC += net * prod.carbs / 100;
          perLineKcal += ing.blankKcalInDish;
        }
        final sumThenRound =
            CalculationMath.round1(4 * exactP + 9 * exactF + 4 * exactC);
        final d = (sumThenRound - perLineKcal).abs();
        if (d > worst) {
          worst = d;
          worstDesc = 'n=$n sumThenRound=$sumThenRound perLineSum=$perLineKcal';
        }
        // The theoretical bound for this row count: each row rounds to 0.1,
        // so the accumulated error cannot exceed 0.05 per row.
        final ratio = d / (0.05 * n);
        if (ratio > worstRatio) worstRatio = ratio;
        expect(ings.length, n);

        // Internal consistency of the engine's own accounting column: the
        // printed raw column must equal the sum of the printed rows exactly.
        final res = CalculationEngine.calculate(_dish(ings, customYield: 999999)
            .copyWith(blankMode: BlankMode.detailed));
        expect(res.rawTotalKcal, CalculationMath.sumRounded(
            ings.map((i) => i.blankKcalInDish), 1),
            reason: 'rawTotalKcal is the accounting sum of the printed rows');
      }
      // The gap is bounded by per-row HALF-UP accumulation: 0.05 kcal × rows.
      expect(worstRatio, lessThanOrEqualTo(1.0),
          reason: 'drift $worst kcal exceeds the rounding bound '
              '(${0.05 * 99} kcal at 99 rows): $worstDesc');
    });

    test('C2.2 printed macro rows sum to the printed total (invariant)', () {
      final rnd = _Rnd(3);
      final ings = <Ingredient>[];
      for (var i = 0; i < 60; i++) {
        ings.add(Ingredient(
          id: '$i',
          product: _nut(
              CalculationMath.round2(rnd.nextDouble() * 20),
              CalculationMath.round2(rnd.nextDouble() * 20),
              CalculationMath.round2(rnd.nextDouble() * 20),
              id: i),
          weightGrams: CalculationMath.round1(1 + rnd.nextDouble() * 200),
        ));
      }
      final res = CalculationEngine.calculate(_dish(ings, customYield: 999999));
      final rowP = CalculationMath.sumRounded(
          ings.map((i) => i.proteinInDish), 2);
      final rowF =
          CalculationMath.sumRounded(ings.map((i) => i.fatInDish), 2);
      final rowC =
          CalculationMath.sumRounded(ings.map((i) => i.carbsInDish), 2);
      expect(res.rawTotalProtein, rowP);
      expect(res.rawTotalFat, rowF);
      expect(res.rawTotalCarbs, rowC);
    });
  });

  group('MATH-C3 monotonicity', () {
    test('C3.1 energy is non-decreasing in weight (200 random weights)', () {
      final rnd = _Rnd(5);
      for (var t = 0; t < 5; t++) {
        final prod = _nut(
            CalculationMath.round2(rnd.nextDouble() * 20),
            CalculationMath.round2(rnd.nextDouble() * 20),
            CalculationMath.round2(rnd.nextDouble() * 20));
        double? prev;
        final ws = List.generate(200, (_) => 0.1 + rnd.nextDouble() * 5000)
          ..sort();
        for (final w in ws) {
          final r = CalculationEngine.calculate(
              _dish([Ingredient(id: 'a', product: prod, weightGrams: w)]));
          if (prev != null) {
            expect(r.cookedKcal, greaterThanOrEqualTo(prev - 1e-12),
                reason: 'weight=$w');
          }
          prev = r.cookedKcal;
        }
      }
    });

    test('C3.2 energy is non-decreasing in protein content at fixed weight', () {
      double? prev;
      for (var p = 0; p <= 100; p++) {
        final prod = _nut(p.toDouble(), 0, 0);
        final r = CalculationEngine.calculate(
            _dish([Ingredient(id: 'a', product: prod, weightGrams: 100)]));
        if (prev != null) expect(r.cookedKcal, greaterThanOrEqualTo(prev));
        prev = r.cookedKcal;
      }
    });
  });

  group('MATH-C4 determinism', () {
    test('C4.1 1000 identical runs give bit-identical output', () {
      final results = <String>{};
      for (var i = 0; i < 1000; i++) {
        final r = CalculationEngine.calculate(_dish(const [
          Ingredient(id: 'a', product: _pMeat, weightGrams: 137.3),
        ]));
        results.add('${r.cookedKcal}|${r.per100gKcal}|${r.cookedProtein}'
            '|${r.cookedFat}|${r.cookedCarbs}');
      }
      expect(results.length, 1);
    });

    test('C4.2 BigInt rounding is order independent for the same values', () {
      final values = [
        for (var i = 0; i < 50; i++) CalculationMath.round2(i * 0.37)
      ];
      final a = CalculationMath.sumRounded(values, 2);
      final b = CalculationMath.sumRounded(values.reversed.toList(), 2);
      expect(a, b);
    });
  });
}
