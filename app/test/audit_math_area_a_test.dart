// AUDIT: area A (gross -> net -> yield) numeric edge behaviour.
// Read-only audit of app/lib/core/calculation. No production code was modified.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
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

Product _wasted(String name, double waste) => Product(
      id: 10,
      code: 'w',
      name: name,
      groupId: 1,
      source: 'skurikhin',
      wastePct: waste,
      protein: 2.0,
      fat: 0.4,
      carbs: 16.3,
      kcal: 77.0,
    );

Dish _dish(List<Ingredient> ings, {double? customYield}) => Dish(
      id: 'audit',
      ingredients: ings,
      customYieldGrams: customYield,
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

  group('MATH-A1 netGrams waste boundaries', () {
    test('A1.1 waste = 0 returns gross unchanged', () {
      expect(Ingredient.netFromGross(1000.0, 0), 1000.0);
    });

    test('A1.2 waste = 0.1 subtracts 1 g from 1000 g gross', () {
      expect(CalculationMath.round1(Ingredient.netFromGross(1000.0, 0.1)),
          999.0);
    });

    test('A1.3 waste = 50 halves the gross mass', () {
      expect(Ingredient.netFromGross(200.0, 50), 100.0);
    });

    test('A1.4 waste = 99.9 keeps 0.1 percent of gross', () {
      expect(CalculationMath.round1(Ingredient.netFromGross(1000.0, 99.9)),
          1.0);
    });

    // SPEC (MATH-03, standardised): waste >= 100 % is rejected by validation.
    // A product without an edible part cannot enter a recipe, so it must fail
    // at the boundary rather than silently becoming a 0 g row.
    test('A1.5 waste = 100 is rejected by validation', () {
      expect(() => Ingredient.netFromGross(500.0, 100), throwsArgumentError);
    });

    test('A1.6 waste > 100 is rejected by validation', () {
      expect(() => Ingredient.netFromGross(500.0, 100.1), throwsArgumentError);
    });

    test('A1.7 waste = 100 gross ingredient is rejected, no silent 0 g row', () {
      expect(
        () => Ingredient(
          id: 'a',
          product: _wasted('Картофель отварной', 100),
          weightGrams: 200,
          isGross: true,
        ).netGramsRounded,
        throwsArgumentError,
      );
    });

    test('A1.8 dish made only of a 100 % waste product cannot be calculated',
        () {
      expect(
        () => CalculationEngine.calculate(_dish([
          Ingredient(
            id: 'a',
            product: _wasted('Отходы', 100),
            weightGrams: 200,
            isGross: true,
          ),
        ])),
        throwsArgumentError,
      );
    });
  });

  group('MATH-A2 grossFromNet round trip', () {
    test('A2.1 exact round trip gross->net->gross is idempotent (grid)', () {
      var checked = 0;
      for (var w = 0; w <= 999; w++) {
        final waste = w / 10;
        for (final g in const [
          0.1, 0.3, 1.0, 7.0, 12.5, 100.0, 333.3, 1000.0, 12345.6, 500000.0
        ]) {
          final net = Ingredient.netFromGross(g, waste);
          final back = Ingredient.grossFromNet(net, waste);
          expect(back, isNotNull, reason: 'g=$g waste=$waste');
          expect((back! - g).abs() < 1e-9, isTrue,
              reason: 'g=$g waste=$waste net=$net back=$back');
          checked++;
        }
      }
      expect(checked, 10000);
    });

    test('A2.2 exact round trip is idempotent on 20 000 random pairs', () {
      final rnd = _Rnd(42);
      for (var i = 0; i < 20000; i++) {
        final waste = rnd.nextInt(999) / 10;
        final g = 0.1 + rnd.nextDouble() * 499999.9;
        final net = Ingredient.netFromGross(g, waste);
        final back = Ingredient.grossFromNet(net, waste)!;
        expect((back - g).abs() < 1e-9, isTrue,
            reason: 'g=$g waste=$waste net=$net back=$back');
      }
    });

    // SPEC (MATH-03, standardised): 100 % waste is rejected, so there is no
    // inverse to compute — the call must fail at validation.
    test('A2.3 waste = 100 is rejected (no edible part, no inverse)', () {
      expect(() => Ingredient.grossFromNet(10, 100), throwsArgumentError);
      expect(() => Ingredient.grossFromNet(0, 100), throwsArgumentError);
    });

    // SPEC (MATH-A2.4, standardised): at 0.1 g print quantum the gross value
    // scales by 1/(1-waste/100) = x500 at 99.8 % waste, so a *printed* net can
    // never round-trip below 50 g. The invariant therefore applies to the
    // model's FULL-double round trip, which must be exact.
    test('A2.4 full-double round trip at 99.8 % waste is exact', () {
      const waste = 99.8;
      const gross = 245074.0;
      final netExact = Ingredient.netFromGross(gross, waste);
      final back = Ingredient.grossFromNet(netExact, waste)!;
      final drift = (back - gross).abs();
      expect(drift, lessThan(1e-6),
          reason: 'gross=$gross waste=$waste net=$netExact '
              'back=$back drift=$drift g');
    });

    test('A2.4b the physical print quantum at 99.8 % waste is x500, not a bug',
        () {
      const waste = 99.8;
      const gross = 245074.0;
      final netShown = CalculationMath.round1(Ingredient.netFromGross(gross, waste));
      final back = Ingredient.grossFromNet(netShown, waste)!;
      // Half a print step of net (0.05 g) maps to 25 g of gross; a full step
      // to 50 g. Anything within one step is expected, not a defect.
      expect((back - gross).abs(), lessThanOrEqualTo(50.0));
    });
  });

  group('MATH-A3 yield and per-100 g', () {
    test('A3.1 effectiveYieldGrams honours the 1.0 g minimum', () {
      final dish = _dish(
        [const Ingredient(id: 'a', product: _pMeat, weightGrams: 1000)],
        customYield: 1.0,
      );
      expect(dish.effectiveYieldGrams, 1.0);
    });

    test('A3.2 1 kg dish with 1.0 g custom yield has finite per-100 g values',
        () {
      final dish = _dish(
        [const Ingredient(id: 'a', product: _pMeat, weightGrams: 1000)],
        customYield: 1.0,
      );
      final res = CalculationEngine.calculate(dish);
      for (final v in [
        res.per100gProtein,
        res.per100gFat,
        res.per100gCarbs,
        res.per100gKcal,
      ]) {
        expect(v.isFinite, isTrue);
        expect(v.isNaN, isFalse);
      }
      expect(CalculationEngine.formatKcal(res.per100gKcal), isNotEmpty);
    });

    // Confirms MATH-05: a 0.1 g yield is accepted by the engine/UI range, and
    // produces a physically absurd 5 000 000 kcal / 100 g label.
    test('A3.3 0.1 g yield is rejected by validation (expects a throw)', () {
      final dish = _dish(
        [const Ingredient(id: 'a', product: _pMeat, weightGrams: 1000)],
        customYield: 0.1,
      );
      expect(() => CalculationEngine.calculate(dish), throwsArgumentError);
    });

    test('A3.4 portion() rejects grams below 0.1 and above 9 999 999', () {
      final res = CalculationEngine.calculate(
          _dish([const Ingredient(id: 'a', product: _pMeat, weightGrams: 500)]));
      expect(() => res.portion(0.05), throwsArgumentError);
      expect(() => res.portion(1e7), throwsArgumentError);
      final p = res.portion(9999999);
      expect(p.kcal.isFinite, isTrue);
    });

    test('A3.5 portion() with extreme grams stays finite', () {
      final res = CalculationEngine.calculate(
          _dish([const Ingredient(id: 'a', product: _pMeat, weightGrams: 500)]));
      final p = res.portion(123456.7);
      expect(p.protein.isFinite && p.fat.isFinite && p.kcal.isFinite, isTrue);
    });
  });

  group('MATH-A4 formatting', () {
    test('A4.1 formatGrams renders finite values with a comma', () {
      expect(CalculationEngine.formatGrams(145.44), '145,4');
      expect(CalculationEngine.formatGrams(100.0), '100');
    });

    // REPRO for MATH-06: round1() of a huge finite double overflows BigInt
    // .toDouble() into Infinity at computation_engine.dart:96-97
    // (rounded.roundToDouble() == rounded is true for infinity, then toInt()).
    test('A4.2 formatGrams(1.5e21) must print the number, not a clamp', () {
      expect(CalculationEngine.formatGrams(1.5e21), '1500000000000000000000');
    });

    // REPRO for MATH-07: axis input "1e-7" (parseInputDouble accepts
    // exponent notation) is printed as "0", silently dropping the line.
    test('A4.3 formatGrams of a tiny positive weight is not "0"', () {
      expect(CalculationEngine.parseInputDouble('1e-7'), isNotNull);
      expect(CalculationEngine.formatGrams(1e-7), isNot('0'));
    });
  });
}
