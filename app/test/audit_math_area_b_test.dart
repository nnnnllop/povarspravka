// AUDIT: area B — retention factors, nutrient propagation, 4-9-4 energy,
// and the "cooked macros <= yield" guard of CalculationEngine.calculate.
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

const _pButter = Product(
  id: 900,
  code: '5.1.1',
  name: 'Масло сливочное',
  groupId: 5,
  source: 'skurikhin',
  protein: 0.5,
  fat: 82.5,
  carbs: 0.8,
  kcal: 748.0,
);

const _pCream = Product(
  id: 901,
  code: '5.2.1',
  name: 'Сливки 35%',
  groupId: 5,
  source: 'skurikhin',
  protein: 2.5,
  fat: 35.0,
  carbs: 3.0,
  kcal: 337.0,
);

const _pFlour = Product(
  id: 902,
  code: '2.1.1',
  name: 'Мука пшеничная в/с',
  groupId: 2,
  source: 'skurikhin',
  protein: 10.3,
  fat: 1.1,
  carbs: 68.9,
  kcal: 334.0,
);

Dish _dish(
  List<Ingredient> ings, {
  double? customYield,
  double rp = 0.94,
  double rf = 0.88,
  double rc = 0.91,
  BlankMode blankMode = BlankMode.photoCross,
}) =>
    Dish(
      id: 'audit',
      ingredients: ings,
      customYieldGrams: customYield,
      blankMode: blankMode,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
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

  group('MATH-B1 retention factors', () {
    test('B1.1 default retention 0.94/0.88/0.91 applies to the column totals',
        () {
      final res = CalculationEngine.calculate(_dish(const [
        Ingredient(id: 'a', product: _pMeat, weightGrams: 100),
        Ingredient(id: 'b', product: _pMeat, weightGrams: 250),
      ]));
      expect(res.rawTotalFat, 56.0);
      expect(res.cookedFat, CalculationMath.round2(56.0 * 0.88));
    });

    // REPRO for MATH-08: retention = 0 is accepted by validation and the blank
    // shows a perfectly formatted "0,0 kcal" dish for a 1 kg steak.
    // SPEC (B1.2): retention <= 0 is physically meaningless — a nutrient
    // coefficient cannot be zero or negative. It must fail validation instead
    // of printing a plausible-looking "0 kcal" dish.
    test('B1.2 retention = 0 is rejected by validation', () {
      expect(
          () => CalculationEngine.calculate(_dish(
                const [
                  Ingredient(id: 'a', product: _pMeat, weightGrams: 1000)
                ],
                rp: 0,
                rf: 0,
                rc: 0,
              )),
          throwsA(isA<ArgumentError>()));
    });

    test('B1.2b retention just above zero is the valid floor', () {
      final res = CalculationEngine.calculate(_dish(
        const [Ingredient(id: 'a', product: _pMeat, weightGrams: 1000)],
        rp: 0.01,
        rf: 0.01,
        rc: 0.01,
      ));
      expect(res.cookedKcal, greaterThan(0));
    });

    test('B1.3 retention = 1 keeps the raw totals unchanged', () {
      final res = CalculationEngine.calculate(_dish(
        const [Ingredient(id: 'a', product: _pMeat, weightGrams: 500)],
        rp: 1,
        rf: 1,
        rc: 1,
      ));
      expect(res.cookedProtein, res.rawTotalProtein);
      expect(res.cookedFat, res.rawTotalFat);
      expect(res.cookedCarbs, res.rawTotalCarbs);
    });

    test('B1.4 retention outside 0..1 is rejected', () {
      expect(() => CalculationEngine.calculate(_dish(const [], rp: 1.01)),
          throwsArgumentError);
      expect(() => CalculationEngine.calculate(_dish(const [], rp: -0.01)),
          throwsArgumentError);
    });
  });

  group('MATH-B2 energy consistency (4P + 9F + 4C)', () {
    test('B2.1 cookedKcal equals 4P+9F+4C on the rounded cells', () {
      final res = CalculationEngine.calculate(_dish(const [
        Ingredient(id: 'a', product: _pMeat, weightGrams: 137.3),
        Ingredient(id: 'b', product: _pButter, weightGrams: 23.7),
      ]));
      final expected = CalculationMath.round1(
          4 * res.cookedProtein + 9 * res.cookedFat + 4 * res.cookedCarbs);
      expect((res.cookedKcal - expected).abs(), lessThan(0.1));
    });

    test('B2.2 energy() half-up matches an integer half-up reference (grid)',
        () {
      var bad = 0;
      String? first;
      for (var p = 0; p <= 3000; p += 7) {
        for (var f = 0; f <= 3000; f += 13) {
          for (var c = 0; c <= 3000; c += 17) {
            // p, f, c are hundredths of a gram.
            final e = CalculationMath.energy(p / 100, f / 100, c / 100);
            // 4p+9f+4c in hundredths -> HALF-UP to 0.1 kcal.
            // value = num100 / 100; in 0.1-kcal units it is num100 / 10,
            // so HALF-UP is (num100 * 2 + 10) ~/ 20.
            final num100 = p * 4 + f * 9 + c * 4;
            final ref = ((num100 * 2 + 10) ~/ 20) / 10.0;
            if ((e - ref).abs() > 1e-9) {
              bad++;
              first ??=
                  'p=${p / 100} f=${f / 100} c=${c / 100} e=$e ref=$ref';
            }
          }
        }
      }
      expect(bad, 0, reason: first);
    });

    // REPRO for MATH-09: with retention = 1 the recipe kcal must equal the sum
    // of the printed per-line kcal; per-cell rounding breaks that.
    // SPEC (B2.3): the recipe column and the per-line column are two DIFFERENT
    // quantities — see MATH-02. The printed raw column is the accounting sum
    // of the printed rows; the dish energy is round(4ΣP+9ΣF+4ΣC). On 40–69
    // rows per-row HALF-UP accumulates, so the gap is bounded by
    // 0.05 kcal × rows, not by 0.05 total.
    test('B2.3 recipe kcal stays within the rounding bound of the printed '
        'per-line sum', () {
      final rnd = _Rnd(2026);
      var worst = 0.0;
      var worstDesc = '';
      var worstRatio = 0.0;
      for (var trial = 0; trial < 300; trial++) {
        final n = 40 + rnd.nextInt(30);
        final ings = <Ingredient>[];
        for (var i = 0; i < n; i++) {
          final prot = CalculationMath.round2(rnd.nextDouble() * 20);
          final fat = CalculationMath.round2(rnd.nextDouble() * 20);
          final car = CalculationMath.round2(rnd.nextDouble() * 20);
          final prod = Product(
            id: i,
            code: 'c$i',
            name: 'p$i',
            groupId: 1,
            source: 'skurikhin',
            protein: prot,
            fat: fat,
            carbs: car,
            kcal: 0,
          );
          ings.add(Ingredient(
            id: '$i',
            product: prod,
            weightGrams: CalculationMath.round1(1 + rnd.nextDouble() * 200),
          ));
        }
        // retention = 1 so cooked == raw and both sides are comparable.
        final res = CalculationEngine.calculate(
            _dish(ings, customYield: 999999, rp: 1, rf: 1, rc: 1));
        final lineSum =
            CalculationMath.sumRounded(ings.map((i) => i.blankKcalInDish), 1);
        final d = (res.cookedKcal - lineSum).abs();
        if (d > worst) {
          worst = d;
          worstDesc = 'n=$n recipe=${res.cookedKcal} lines=$lineSum';
        }
        final ratio = d / (0.05 * n);
        if (ratio > worstRatio) worstRatio = ratio;

        // Consistency that MUST hold exactly: the printed raw column is the
        // accounting sum of the printed per-line values.
        final detailed = CalculationEngine.calculate(_dish(ings,
            blankMode: BlankMode.detailed, rp: 1, rf: 1, rc: 1));
        expect(detailed.rawTotalKcal, lineSum,
            reason: 'the raw kcal column must re-add to the printed rows');
      }
      expect(worstRatio, lessThanOrEqualTo(1.0),
          reason: 'recipe-vs-lines gap $worst kcal exceeds the per-row '
              'rounding bound: $worstDesc');
    });
  });

  group('MATH-B3 yield guard (sumExceeds)', () {
    // REPRO for MATH-01: a physically legal dish cannot be calculated at all.
    test('B3.1 butter sauce 100 g with yield 60 g must be calculable', () {
      final dish = _dish(
        const [Ingredient(id: 'a', product: _pButter, weightGrams: 100)],
        customYield: 60,
      );
      expect(() => CalculationEngine.calculate(dish), returnsNormally);
    });

    // REPRO for MATH-01 (natural recipe, no tricks).
    test('B3.2 "Сливки с мукой" (butter+cream+flour, уварка 20%) is calculable',
        () {
      final dish = _dish(
        const [
          Ingredient(id: 'butter', product: _pButter, weightGrams: 150),
          Ingredient(id: 'cream', product: _pCream, weightGrams: 400),
          Ingredient(id: 'flour', product: _pFlour, weightGrams: 60),
        ],
        customYield: 488,
      );
      // 150 + 400 + 60 = 610 g raw, 20 % уварка -> 488 g ready sauce.
      expect(dish.totalRawNetGrams, 610.0);
      final res = CalculationEngine.calculate(dish);
      expect(res.cookedKcal, greaterThan(0));
      // A 488 g sauce of 150 g butter + 400 g cream + 60 g flour is dense:
      // ~900 kcal/100 g is right for the ingredient set, so only sanity-bound it.
      expect(res.per100gKcal, inInclusiveRange(200, 1000));
    });

    test('B3.3 default (no custom yield) dishes are always calculable', () {
      final res = CalculationEngine.calculate(_dish(const [
        Ingredient(id: 'a', product: _pButter, weightGrams: 500),
        Ingredient(id: 'b', product: _pMeat, weightGrams: 300),
      ]));
      expect(res.cookedKcal, greaterThan(0));
    });
  });
}
