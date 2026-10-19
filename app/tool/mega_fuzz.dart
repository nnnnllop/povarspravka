import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../lib/core/calculation/calculation_engine.dart';
import '../lib/core/calculation/calculation_validation.dart';
import '../lib/core/calculation/models/dish.dart';
import '../lib/core/calculation/models/ingredient.dart';
import '../lib/core/calculation/models/product.dart';
import '../lib/core/calculation/models/blank_mode.dart';

void check(bool ok, Object detail) {
  if (!ok) throw StateError('$detail');
}

int roundDiv(int a, int b) => (2 * a + b) ~/ (2 * b);
void main(List<String> args) {
  final strictYieldDomain = !args.contains('--extended-auto-yield');
  final out = Directory('../audit_artifacts/mega');
  out.createSync(recursive: true);
  final rows =
      (jsonDecode(File('${out.path}/catalog.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
  final anomalies = <Map<String, dynamic>>[];
  var measures = 0, shownMeasures = 0;
  for (final row in rows) {
    final p = Product.fromJson(row);
    measures += p.measures.length;
    for (final m in p.measures) {
      check(m.grams.isFinite && m.grams > 0, 'bad measure ${m.id}');
    }
    for (final m in p.calculationMeasures) {
      shownMeasures++;
      check(m.grams.isFinite && m.grams > 0, 'bad selectable ${m.id}');
    }
    try {
      CalculationValidation.product(p);
    } on ArgumentError catch (e) {
      anomalies.add({'id': p.id, 'error': '$e'});
    }
  }
  File('${out.path}/catalog_result.json').writeAsStringSync(jsonEncode({
    'products': rows.length,
    'measures': measures,
    'selectableMeasures': shownMeasures,
    'anomalies': anomalies
  }));
  const seed = 20261017;
  final rng = Random(seed);
  var accepted = 0, rejected = 0, ingredientCount = 0, comparisons = 0;
  final counts = <int>{};
  final seenWaste = <int>{};
  final seenRet = <int>{};
  final failures = <Map<String, dynamic>>[];
  final now = DateTime.utc(2026, 10, 17);
  final timer = Stopwatch()..start();
  for (var caseId = 0; caseId < 100000; caseId++) {
    final count = caseId < 101 ? caseId : rng.nextInt(101);
    counts.add(count);
    final ingredients = <Ingredient>[];
    final sums = [0, 0, 0, 0, 0];
    for (var j = 0; j < count; j++) {
      final waste = rng.nextInt(100001);
      seenWaste.add(waste);
      final weight = caseId % 499 == 0
          ? 1
          : caseId % 499 == 1
              ? 100000000
              : 1 + rng.nextInt(100000000);
      final pc = rng.nextInt(10001),
          fc = rng.nextInt(10001 - pc),
          cc = rng.nextInt(10001 - pc - fc);
      final gross = rng.nextBool();
      final netTenths = gross
          ? roundDiv(weight * (100000 - waste), 10000000)
          : roundDiv(weight, 100);
      final p = roundDiv(netTenths * pc, 1000),
          f = roundDiv(netTenths * fc, 1000),
          c = roundDiv(netTenths * cc, 1000);
      sums[0] += netTenths;
      sums[1] += p;
      sums[2] += f;
      sums[3] += c;
      sums[4] += roundDiv(4 * p + 9 * f + 4 * c, 10);
      ingredients.add(Ingredient(
          id: '$caseId-$j',
          weightGrams: weight / 1000,
          isGross: gross,
          product: Product(
              id: j,
              code: '$j',
              name: 'fuzz',
              groupId: 1,
              source: 'usda',
              protein: pc / 100,
              fat: fc / 100,
              carbs: cc / 100,
              kcal: 0,
              wastePct: waste / 1000)));
    }
    ingredientCount += count;
    final ret = List.generate(3, (_) => rng.nextInt(1001));
    seenRet.addAll(ret);
    final cooked =
        List.generate(3, (k) => roundDiv(sums[k + 1] * ret[k], 1000));
    final y = caseId % 5 == 0
        ? (strictYieldDomain ? max(1, min(2000000, sums[0])) : null)
        : caseId % 5 == 1
            ? 1
            : caseId % 5 == 2
                ? 2000000
                : caseId % 5 == 3
                    ? max(1, min(2000000, roundDiv(sums[0], 100)))
                    : 1 + rng.nextInt(2000000);
    final effective = y ?? sums[0];
    final invalid = cooked.reduce((a, b) => a + b) > effective * 10;
    final d = Dish(
        id: 'fuzz-$caseId',
        ingredients: ingredients,
        customYieldGrams: y == null ? null : y / 10,
        retentionProtein: ret[0] / 1000,
        retentionFat: ret[1] / 1000,
        retentionCarbs: ret[2] / 1000,
        blankMode: BlankMode.detailed,
        createdAt: now,
        updatedAt: now);
    try {
      final r = CalculationEngine.calculate(d);
      accepted++;
      check(!invalid, 'accepted impossible mass');
      final actual = [
        r.rawTotalWeight,
        r.rawTotalProtein,
        r.rawTotalFat,
        r.rawTotalCarbs,
        r.rawTotalKcal!,
        r.cookedProtein,
        r.cookedFat,
        r.cookedCarbs,
        r.cookedKcal,
        r.yieldGrams,
        r.per100gProtein,
        r.per100gFat,
        r.per100gCarbs,
        r.per100gKcal
      ];
      final expected = [
        sums[0] / 10,
        sums[1] / 100,
        sums[2] / 100,
        sums[3] / 100,
        sums[4] / 10,
        cooked[0] / 100,
        cooked[1] / 100,
        cooked[2] / 100,
        roundDiv(4 * cooked[0] + 9 * cooked[1] + 4 * cooked[2], 10) / 10,
        effective / 10,
        ...List.generate(
            3,
            (k) => effective > 0
                ? roundDiv(cooked[k] * 1000, effective) / 100
                : 0.0),
        effective > 0
            ? roundDiv(
                    roundDiv(
                            4 * cooked[0] + 9 * cooked[1] + 4 * cooked[2], 10) *
                        1000,
                    effective) /
                10
            : 0.0
      ];
      for (var k = 0; k < actual.length; k++) {
        check(actual[k].isFinite && actual[k] >= 0, 'nonfinite/negative $k');
        check(actual[k] == expected[k],
            'oracle $k actual=${actual[k]} expected=${expected[k]}');
        comparisons++;
      }
    } on ArgumentError catch (e) {
      rejected++;
      if (!invalid)
        failures.add({'case': caseId, 'error': 'unexpected rejection: $e'});
    } catch (e) {
      failures.add({'case': caseId, 'error': '$e'});
    }
    if (caseId % 10000 == 9999) {
      print(
          'cases=${caseId + 1} accepted=$accepted rejected=$rejected failures=${failures.length} ms=${timer.elapsedMilliseconds}');
      File('${out.path}/fuzz_progress.json').writeAsStringSync(jsonEncode({
        'completed': caseId + 1,
        'accepted': accepted,
        'rejected': rejected,
        'failures': failures.take(20).toList()
      }));
    }
  }
  final result = {
    'seed': seed,
    'yieldDomain': strictYieldDomain ? 'all recipes 0.1..200000 g' : 'includes unconstrained automatic yield',
    'cases': 100000,
    'ingredients': ingredientCount,
    'accepted': accepted,
    'expectedRejections': rejected,
    'exactComparisons': comparisons,
    'ingredientCountsCovered': counts.length,
    'wasteValuesCovered': seenWaste.length,
    'retentionValuesCovered': seenRet.length,
    'milliseconds': timer.elapsedMilliseconds,
    'failures': failures
  };
  File('${out.path}/fuzz_result.json').writeAsStringSync(jsonEncode(result));
  print(jsonEncode(result));
  if (failures.isNotEmpty) exitCode = 1;
}
