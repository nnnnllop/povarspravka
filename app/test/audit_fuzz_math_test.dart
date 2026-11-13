// FUZZ-EDGE / PART 1 — CalculationMath exactness, NaN/Infinity injection.
// Each `test()` either asserts the GOOD contract (and passes) or is named
// `[DEFECT FUZZ-xx]` and asserts the ground truth as it is today, so the
// suite stays red-free while pinning the defect.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product prod({
  double protein = 10,
  double fat = 5,
  double carbs = 20,
  double kcal = 300,
  double wastePct = 0,
  double water = 0,
  double fiber = 0,
  double sfa = 0,
  double pufa = 0,
  double chol = 0,
  double alcohol = 0,
  List<ProductMeasure> measures = const [],
}) =>
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
      wastePct: wastePct,
      water: water,
      fiber: fiber,
      sfa: sfa,
      pufa: pufa,
      chol: chol,
      alcohol: alcohol,
      measures: measures,
    );

Dish dish(List<Ingredient> ings,
        {double? yieldGrams,
        double rp = 1.0,
        double rf = 1.0,
        double rc = 1.0,
        BlankMode mode = BlankMode.detailed}) =>
    Dish(
      id: 'd',
      ingredients: ings,
      customYieldGrams: yieldGrams,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      blankMode: mode,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('CalculationMath.decimal — non-finite input is a CONTROLLED ArgumentError', () {
    // The mandate asked to prove BigInt.parse("NaN") -> FormatException.
    // It does not happen: `decimal()` guards with `!value.isFinite` first.
    for (final entry in <String, double>{
      'NaN': double.nan,
      'Infinity': double.infinity,
      '-Infinity': double.negativeInfinity,
    }.entries) {
      test('decimal(${entry.key}) throws ArgumentError, not FormatException', () {
        expect(
          () => CalculationMath.decimal(entry.value),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => CalculationMath.decimal(entry.value),
          isNot(throwsA(isA<FormatException>())),
        );
      });
      test('round1/round2/productRounded/energy/sumRounded(${entry.key}) all ArgumentError', () {
        final v = entry.value;
        expect(() => CalculationMath.round1(v), throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.round2(v), throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.productRounded(v, 1, 1),
            throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.productRounded(1, v, 1),
            throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.energy(v, 0, 0), throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.sumRounded([1.0, v], 2),
            throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.sumExceeds([v], 100),
            throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.ratioRounded(v, 100, 2),
            throwsA(isA<ArgumentError>()));
        expect(() => CalculationMath.wasteAdjusted(100, v, 1),
            throwsA(isA<ArgumentError>()));
      });
    }
  });

  group('CalculationMath.decimal — exponent notation handling', () {
    test('1e-7 -> (1, 7)', () {
      expect(CalculationMath.decimal(1e-7), (BigInt.one, 7));
    });
    test('1e21 is EXPONENT form in toString ("1e+21") -> parsed as 1e21', () {
      expect(1e21.toString(), '1e+21');
      expect(CalculationMath.decimal(1e21), (BigInt.one, -21));
    });
    test('1.5e-10 -> (15, 11)', () {
      expect(CalculationMath.decimal(1.5e-10), (BigInt.from(15), 11));
    });
    test('no crash for the full finite toString set (exponent > 21 / < -7)', () {
      for (final v in [1e-7, 1.5e-7, 1e21, 1.5e21, 1e300, 1e-300, 4.9e-324]) {
        expect(() => CalculationMath.decimal(v), returnsNormally,
            reason: 'value=$v toString=${v.toString()}');
      }
    });
  });

  group('CalculationMath stays finite on the double extremes', () {
    test('[FUZZ-02] round1(double.maxFinite) stays finite (no BigInt overflow)',
        () {
      // SPEC: the old code did `BigInt.toDouble()` on the rounded value, which
      // overflows to Infinity above ~1.8e308 / 10. The result must stay finite
      // so one absurd row cannot poison the whole blank.
      final r = CalculationMath.round1(double.maxFinite);
      expect(r.isFinite, isTrue);
      expect(r, double.maxFinite);
    });
    test('[FUZZ-02] sumRounded([double.maxFinite]) stays finite', () {
      final r = CalculationMath.sumRounded([double.maxFinite], 1);
      expect(r.isFinite, isTrue);
      expect(r, double.maxFinite);
    });
    test('huge exponent does NOT OOM: decimal(1e-300) is cheap', () {
      final sw = Stopwatch()..start();
      CalculationMath.decimal(4.9e-324);
      CalculationMath.round1(4.9e-324);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
    });
  });

  group('parseInputDouble — verdict table (FUZZ-07, FUZZ-08)', () {
    // input -> expected result. `null` = rejected (good or risk, see verdicts).
    const table = <String, double?>{
      '': null,
      ' ': null,
      '1,5': 1.5,
      '1.5': 1.5,
      '1,5,5': null,
      '1.5.5': null,
      ',5': 0.5,
      '5,': 5.0,
      '1.5e3': 1500.0,
      '1e5': 100000.0,
      '1e-3': 0.001,
      '1e999': null, // parses to +Inf -> rejected by isFinite
      '1e309': null,
      '1e308': 1e308,
      'NaN': null,
      'Infinity': null,
      '-Infinity': null,
      '0x10': null,
      ' 12 ': 12.0,
      '12 г': null,
      '\uFF11\uFF12': null, // fullwidth digits
      '\u0661\u0662': null, // arabic-indic digits
      '\u0663.\u0665': null,
      '1 000': 1000.0, // RU grouping space — ACCEPTED (FUZZ-07 fixed)
      '1_000': null,
      '\u066B': null, // arabic decimal separator alone
      '\u00A012': 12.0, // NBSP is Dart `trim` whitespace -> accepted
      '\u200F12': null, // RLM (RTL mark)
      '\u200B12': null, // zero-width space
      '1\u00002': null,
      '00012': 12.0,
      '.5': 0.5,
      '5.': 5.0,
      '\t12\n': 12.0,
      '-0': null, // FUZZ-08: negatives are rejected outright
      '-3': null, // FUZZ-08: negatives are rejected outright
      '1 00': null, // a malformed group is not a thousands separator
      '1 000 000': 1000000.0, // well-formed grouping
    };
    table.forEach((input, expected) {
      final label = input
          .replaceAll('\u00A0', '<NBSP>')
          .replaceAll('\u200F', '<RLM>')
          .replaceAll('\u200B', '<ZWSP>')
          .replaceAll('\u0000', '<NUL>');
      test('parse("$label") == $expected', () {
        final got = CalculationEngine.parseInputDouble(input);
        if (expected == null) {
          expect(got, isNull);
        } else {
          expect(got, isNotNull);
          expect(got!, closeTo(expected, 1e-12));
        }
      });
    });

    test('lone surrogate does not crash', () {
      final s = String.fromCharCodes([0xD800, 0x31]);
      expect(() => CalculationEngine.parseInputDouble(s), returnsNormally);
      expect(CalculationEngine.parseInputDouble(s), isNull);
    });

    test('[FUZZ-08] negatives are rejected outright', () {
      expect(CalculationEngine.parseInputDouble('-3'), isNull);
      expect(CalculationEngine.parseInputDouble('-0'), isNull);
      expect(CalculationEngine.parseInputDouble('-0,5'), isNull);
    });

    test('[FUZZ-07] RU grouping space is accepted when well formed', () {
      expect(CalculationEngine.parseInputDouble('1 000'), 1000.0);
      expect(CalculationEngine.parseInputDouble('12 345 678'), 12345678.0);
      // …and rejected when it is not a real grouping.
      expect(CalculationEngine.parseInputDouble('1 00'), isNull);
    });
  });

  group('Validation reachability per Product field (FUZZ-01)', () {
    final fieldOf = <String, Product Function(double)>{
      'protein': (v) => prod(protein: v),
      'fat': (v) => prod(fat: v),
      'carbs': (v) => prod(carbs: v),
      'wastePct': (v) => prod(wastePct: v),
      'kcal': (v) => prod(kcal: v),
      'water': (v) => prod(water: v),
      'fiber': (v) => prod(fiber: v),
      'sfa': (v) => prod(sfa: v),
      'pufa': (v) => prod(pufa: v),
      'chol': (v) => prod(chol: v),
      'alcohol': (v) => prod(alcohol: v),
    };
    fieldOf.forEach((name, build) {
      for (final bad in <(String, double)>[
        ('NaN', double.nan),
        ('Infinity', double.infinity),
        ('-Infinity', double.negativeInfinity),
      ]) {
        test('$name=${bad.$1} is rejected', () {
          final d = dish(
              [Ingredient(id: 'i', product: build(bad.$2), weightGrams: 100)]);
          // SPEC (FUZZ-01): every numeric product field is validated, so no
          // non-finite value can reach the arithmetic.
          expect(() => CalculationEngine.calculate(d),
              throwsA(isA<ArgumentError>()));
        });
      }
    });

    test('measures[i].grams NaN/Inf does not reach arithmetic (filtered out)', () {
      for (final v in [double.nan, double.infinity, -double.infinity]) {
        final p = prod(measures: [
          ProductMeasure(id: 1, productId: 1, name: 'шт', grams: v),
        ]);
        expect(p.calculationMeasures, isEmpty);
        expect(
            () => CalculationEngine.calculate(
                dish([Ingredient(id: 'i', product: p, weightGrams: 100)])),
            returnsNormally);
      }
    });

    test('non-GROSS weight with NaN wastePct is still rejected', () {
      // `netGrams` short-circuits, but `netGramsRounded` validates wastePct first.
      expect(
          () => Ingredient(id: 'i', product: prod(wastePct: double.nan), weightGrams: 100)
              .netGramsRounded,
          throwsA(isA<ArgumentError>()));
    });
  });

  group('FUZZ-01 — Infinity kcal passes validation and poisons kcalInDish', () {
    test('[FUZZ-01] product(kcal: Infinity) is rejected', () {
      final p = prod(kcal: double.infinity);
      expect(() => CalculationValidation.product(p),
          throwsA(isA<ArgumentError>()));
      expect(CalculationValidation.isValidProduct(p), isFalse);
      expect(
          () => CalculationEngine.calculate(
              dish([Ingredient(id: 'a', product: p, weightGrams: 100)])),
          throwsA(isA<ArgumentError>()));
    });

    test('[FUZZ-01] product(kcal: NaN) is rejected', () {
      final p = prod(kcal: double.nan);
      expect(() => CalculationValidation.product(p),
          throwsA(isA<ArgumentError>()));
      expect(CalculationValidation.isValidProduct(p), isFalse);
    });

    test('[FUZZ-01] rawTotalKcal never reflects a poisoned kcal', () {
      // SPEC: both inputs are rejected, so the blank can never be poisoned.
      for (final kcal in [double.nan, double.infinity, -100.0]) {
        final d = dish(
            [Ingredient(id: 'a', product: prod(kcal: kcal), weightGrams: 100)]);
        expect(() => CalculationEngine.calculate(d),
            throwsA(isA<ArgumentError>()),
            reason: 'kcal=$kcal');
      }
    });

    test('[DEFECT FUZZ-03] all ingredient kcal=0 -> kcalInDish 0 but rawTotalKcal is the energy formula', () {
      final ing = Ingredient(id: 'a', product: prod(kcal: 0), weightGrams: 100);
      expect(ing.kcalInDish, 0.0);
      final r = CalculationEngine.calculate(dish([ing]));
      expect(r.rawTotalKcal, 165.0, reason: 'blankKcalInDish never reads kcal');
    });

    test('[FUZZ-04] negative kcal is rejected', () {
      final p = prod(kcal: -100);
      expect(() => CalculationValidation.product(p),
          throwsA(isA<ArgumentError>()));
      expect(CalculationValidation.isValidProduct(p), isFalse);
    });
  });

  group('Weight / yield / retention NaN-Infinity table (FUZZ-01, FUZZ-05)', () {
    test('weightGrams NaN/±Inf -> ArgumentError', () {
      for (final v in [double.nan, double.infinity, double.negativeInfinity]) {
        expect(
            () => CalculationEngine.calculate(
                dish([Ingredient(id: 'i', product: prod(), weightGrams: v)])),
            throwsA(isA<ArgumentError>()));
      }
    });

    test('customYieldGrams NaN/±Inf/0.0/0.05/-5 -> ArgumentError', () {
      for (final v in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.0,
        0.05,
        -5.0,
        -0.1,
      ]) {
        expect(
            () => CalculationEngine.calculate(dish(
                [Ingredient(id: 'i', product: prod(), weightGrams: 100)],
                yieldGrams: v)),
            throwsA(isA<ArgumentError>()),
            reason: 'customYieldGrams=$v');
      }
    });

    test('retention -0.1 / 1.1 / NaN / ±Inf -> ArgumentError', () {
      for (final v in [-0.1, 1.1, double.nan, double.infinity, double.negativeInfinity]) {
        expect(
            () => CalculationEngine.calculate(dish(
                [Ingredient(id: 'i', product: prod(), weightGrams: 100)],
                rp: v)),
            throwsA(isA<ArgumentError>()),
            reason: 'retentionProtein=$v');
      }
    });

    test('weightGrams -1 / -0.0001 / 1e7+1 -> ArgumentError', () {
      for (final v in [-1.0, -0.0001, 10000001.0, 1e12]) {
        expect(
            () => CalculationEngine.calculate(
                dish([Ingredient(id: 'i', product: prod(), weightGrams: v)])),
            throwsA(isA<ArgumentError>()),
            reason: 'weightGrams=$v');
      }
    });

    test('[RISK FUZZ-05] weightGrams 0.05 rounds HALF-UP to 0.1 g — 100% mass inflation at the edge', () {
      final ing = Ingredient(id: 'i', product: prod(), weightGrams: 0.05);
      final r = CalculationEngine.calculate(dish([ing]));
      expect(ing.netGramsRounded, 0.1, reason: 'netGramsRounded rounds up, not to 0');
      expect(r.rawTotalWeight, 0.1);
      // The dish is 50 mg of food, yet the blank shows a 100 mg portion.
      expect(r.yieldGrams, 0.1);
    });

    test('[RISK FUZZ-05b] TWO gross ingredients of 0.05 g each: rounded per-ROW, total = 0.2 for 0.1 g of food', () {
      final r = CalculationEngine.calculate(dish([
        Ingredient(id: 'a', product: prod(), weightGrams: 0.05, isGross: true),
        Ingredient(id: 'b', product: prod(), weightGrams: 0.05, isGross: true),
      ]));
      expect(r.rawTotalWeight, 0.2);
    });

    test('weight 0 is accepted and contributes nothing (not an error)', () {
      final r = CalculationEngine.calculate(dish([
        Ingredient(id: 'a', product: prod(), weightGrams: 0),
        Ingredient(id: 'b', product: prod(), weightGrams: 100),
      ]));
      expect(r.rawTotalWeight, 100.0);
      expect(r.rawTotalProtein, 10.0);
    });
  });

  group('Negative values — rejected vs silently clamped vs silently accepted', () {
    test('DishNotifier.addIngredient silently CLAMPS weight 0 / negative (validation inRange)', () {
      // Reachability note: the notifier drops invalid weights instead of throwing,
      // so a negative never reaches the engine through the UI. Covered in part 4.
      expect(CalculationValidation.inRange(-1, .1, 9999999), isFalse);
      expect(CalculationValidation.inRange(0, .1, 9999999), isFalse);
      expect(CalculationValidation.inRange(0.05, .1, 9999999), isFalse);
    });

    test('[FUZZ-04] negative kcal is rejected, never silently absorbed', () {
      // SPEC: a negative energy value is nonsense and fails validation, so it
      // can never be quietly ignored while the blank prints a plausible total.
      expect(
          () => CalculationEngine.calculate(dish([
                Ingredient(id: 'a', product: prod(kcal: -1e9), weightGrams: 100),
              ])),
          throwsA(isA<ArgumentError>()));
    });

    test('[FUZZ-04b] photoCross mode omits the kcal column for valid input', () {
      for (final kcal in [0.0, 900.0]) {
        final r = CalculationEngine.calculate(dish(
            [Ingredient(id: 'a', product: prod(kcal: kcal), weightGrams: 100)],
            mode: BlankMode.photoCross));
        // By design: the photoCross blank prints macros only.
        expect(r.rawTotalKcal, isNull, reason: 'kcal=$kcal');
        expect(r.cookedKcal, 165.0);
      }
      // Non-finite input never reaches the blank at all.
      for (final kcal in [double.nan, double.infinity, -1e9]) {
        expect(
            () => CalculationEngine.calculate(dish([
                  Ingredient(id: 'a', product: prod(kcal: kcal), weightGrams: 100),
                ], mode: BlankMode.photoCross)),
            throwsA(isA<ArgumentError>()),
            reason: 'kcal=$kcal');
      }
    });

    test('kcal is IGNORED by every output — prove with two products differing only in kcal', () {
      final a = CalculationEngine.calculate(
          dish([Ingredient(id: 'a', product: prod(kcal: 0), weightGrams: 100)]));
      final b = CalculationEngine.calculate(
          dish([Ingredient(id: 'a', product: prod(kcal: 900), weightGrams: 100)]));
      expect(a.rawTotalKcal, b.rawTotalKcal);
      expect(a.cookedKcal, b.cookedKcal);
      expect(a.per100gKcal, b.per100gKcal);
    });
  });
}
