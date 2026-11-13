// DIFFERENTIAL / REGRESSION HARNESS (read-only audit).
//
// Compares the NEW implementation (app/lib/**, uncommitted fix) with a verbatim
// copy of the OLD implementation (HEAD 658d3ff) living in
// reaudit_regression_old_lib.dart, over large random + boundary input sets.
//
// Every `print` below is evidence for REPORT.md. Run with:
//   cd app && flutter test test/reaudit_regression_diff_test.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/calculation_result.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/masters_recipes.dart';

import 'reaudit_regression_old_lib.dart';

// ===========================================================================
// helpers
// ===========================================================================

final Random rng = Random(20261030);

Product prod({
  String name = 'Морковь',
  double protein = 1.3,
  double fat = 0.1,
  double carbs = 6.9,
  double kcal = 35,
  double wastePct = 0,
  double water = 0,
  double fiber = 0,
  double ash = 0,
  double organicAcids = 0,
  double sugars = 0,
  double starch = 0,
  double sfa = 0,
  double pufa = 0,
  double chol = 0,
  double alcohol = 0,
  String source = 'skurikhin',
  bool? isDish,
}) =>
    Product(
      id: rng.nextInt(100000),
      code: 'c',
      name: name,
      groupId: 1,
      source: source,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
      wastePct: wastePct,
      water: water,
      fiber: fiber,
      ash: ash,
      organicAcids: organicAcids,
      sugars: sugars,
      starch: starch,
      sfa: sfa,
      pufa: pufa,
      chol: chol,
      alcohol: alcohol,
      isDish: isDish,
    );

Dish dishOf(List<Ingredient> ings,
        {double? y,
        double rp = 0.94,
        double rf = 0.88,
        double rc = 0.91,
        HeatProcess process = HeatProcess.legacy,
        BlankMode mode = BlankMode.detailed}) =>
    Dish(
      id: 'd',
      ingredients: ings,
      customYieldGrams: y,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      blankMode: mode,
      process: process,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Result of a calculation attempt, so that "throws" is comparable too.
class Outcome {
  final CalculationResult? r;
  final String? error;
  const Outcome(this.r, this.error);
  bool get ok => error == null;
  @override
  String toString() => ok
      ? 'ok(y=${r!.yieldGrams}, P=${r!.cookedProtein}, F=${r!.cookedFat}, '
          'C=${r!.cookedCarbs}, kcal=${r!.cookedKcal})'
      : 'throw($error)';
}

Outcome runNew(Dish d) {
  try {
    return Outcome(CalculationEngine.calculate(d), null);
  } on ArgumentError catch (e) {
    return Outcome(null, 'ArgumentError: ${e.message}');
  } catch (e) {
    return Outcome(null, e.toString());
  }
}

Outcome runOld(Dish d) {
  try {
    return Outcome(OldEngine.calculate(d), null);
  } on ArgumentError catch (e) {
    return Outcome(null, 'ArgumentError: ${e.message}');
  } catch (e) {
    return Outcome(null, e.toString());
  }
}

String diffOf(Outcome a, Outcome b) {
  if (a.ok != b.ok) return 'status';
  if (!a.ok) return a.error == b.error ? 'none' : 'error-text';
  final x = a.r!, y = b.r!;
  final fields = <String>[];
  void cmp(String n, double p, double q) {
    if (p != q) fields.add('$n ${p.toString()} -> ${q.toString()}');
  }

  cmp('yield', x.yieldGrams, y.yieldGrams);
  cmp('rawP', x.rawTotalProtein, y.rawTotalProtein);
  cmp('cookedP', x.cookedProtein, y.cookedProtein);
  cmp('cookedF', x.cookedFat, y.cookedFat);
  cmp('cookedC', x.cookedCarbs, y.cookedCarbs);
  cmp('cookedKcal', x.cookedKcal, y.cookedKcal);
  cmp('per100P', x.per100gProtein, y.per100gProtein);
  cmp('per100F', x.per100gFat, y.per100gFat);
  cmp('per100C', x.per100gCarbs, y.per100gCarbs);
  cmp('per100Kcal', x.per100gKcal, y.per100gKcal);
  return fields.isEmpty ? 'none' : fields.join('; ');
}

// ===========================================================================
// 1. CalculationMath.productRounded / round1 / round2 — the -0.0 question
// ===========================================================================
void mathDiff() {
  print('\n=== [1] CalculationMath.productRounded ===');
  final cases = <String, (double, double, int, bool)>{
    'positive typical': (12.345, 0.94, 2, false),
    'divideBy100 typical': (12.345, 94.0, 2, true),
    'a=0 b=5': (0.0, 5.0, 2, false),
    'a=5 b=0': (5.0, 0.0, 2, false),
    'a=-0.0 b=5': (-0.0, 5.0, 2, false),
    'a=5 b=-0.0': (5.0, -0.0, 2, false),
    'a=-3 b=0': (-3.0, 0.0, 2, false),
    'a=-3 b=2': (-3.0, 2.0, 2, false),
    'a=-3 b=-2': (-3.0, -2.0, 2, false),
    'a=-0.0 b=-0.0': (-0.0, -0.0, 1, false),
    'tiny a=1e-7 round1': (0.0000001, 1.0, 1, false),
    'huge 1.5e21': (1.5e21, 1.0, 1, false),
  };
  for (final e in cases.entries) {
    final (a, b, d, div) = e.value;
    final oldV = OldMath.productRounded(a, b, d, divideBy100: div);
    final newV = CalculationMath.productRounded(a, b, d, divideBy100: div);
    final same = oldV == newV && oldV.isNegative == newV.isNegative;
    print('  ${same ? "SAME" : "DIFF"}  ${e.key}: old=$oldV new=$newV '
        '(oldSign=${oldV.sign}, newSign=${newV.sign})');
  }

  // Random differential over signed magnitudes.
  var diffs = 0;
  var negZeroNew = 0;
  for (var i = 0; i < 20000; i++) {
    final a = (rng.nextDouble() * 2000 - 1000);
    final b = (rng.nextDouble() * 200 - 100);
    final d = 1 + rng.nextInt(3);
    final oldV = OldMath.productRounded(a, b, d);
    final newV = CalculationMath.productRounded(a, b, d);
    if (oldV != newV) diffs++;
    if (newV == 0 && newV.isNegative) negZeroNew++;
  }
  print('  random signed 20000: value diffs=$diffs, new -0.0 outputs=$negZeroNew');

  // NaN / infinity inputs: old threw, new throws (clamp is unreachable).
  for (final v in <double>[double.nan, double.infinity, -double.infinity]) {
    final oldErr = _err(() => OldMath.productRounded(v, 1, 2));
    final newErr = _err(() => CalculationMath.productRounded(v, 1, 2));
    print('  productRounded($v): old=${oldErr ?? "ok"} new=${newErr ?? "ok"}');
  }
}

String? _err(void Function() f) {
  try {
    f();
    return null;
  } catch (e) {
    return e.runtimeType.toString();
  }
}

// ===========================================================================
// 2. CalculationValidation.product / dish — rejections that used to pass
// ===========================================================================
void validationDiff() {
  print('\n=== [2] CalculationValidation.product / .dish ===');
  final probes = <String, Product>{
    'wastePct = 100': prod(wastePct: 100),
    'wastePct = 99.999': prod(wastePct: 99.999),
    'wastePct = 99.9995': prod(wastePct: 99.9995),
    'water = 500': prod(water: 500),
    'water = 1000.5': prod(water: 1000.5),
    'water = 100000': prod(water: 100000),
    'fiber = 150': prod(protein: 20, fat: 20, carbs: 20, fiber: 150),
    'chol = 200000': prod(chol: 200000),
    'kcal = 200000': prod(kcal: 200000),
    'kcal negative': prod(kcal: -1),
    'P+F+C = 100.004 (rounding)': prod(protein: 33.334, fat: 33.333, carbs: 33.337),
    'P+F+C = 100 exact': prod(protein: 0, fat: 100, carbs: 0),
  };
  for (final e in probes.entries) {
    final oldOk = _err(() => OldValidation.product(e.value)) == null;
    final newOk = CalculationValidation.isValidProduct(e.value);
    print('  ${oldOk == newOk ? "SAME" : "DIFF"}  ${e.key}: '
        'oldValid=$oldOk newValid=$newOk');
  }

  // Int-range columns: what does Product.fromMap do with out-of-int-range
  // values (cholesterol 250000 mg/100g is legal for liver)?
  for (final json in <String>[
    '{"name":"Печень","protein":18,"fat":6,"carbs":2,"chol":250000}',
    '{"name":"Печень","protein":18,"fat":6,"carbs":2,"chol":2500000000}',
    '{"name":"Вода","protein":0,"fat":0,"carbs":0,"water":99999}',
  ]) {
    String newRes;
    String oldRes;
    try {
      final p = Product.fromJson(jsonDecode(json) as Map<String, dynamic>);
      newRes = 'chol=${p.chol} water=${p.water} valid=${CalculationValidation.isValidProduct(p)}';
    } catch (e) {
      newRes = 'THROW ${e.runtimeType}: $e';
    }
    try {
      final p = Product.fromJson(jsonDecode(json) as Map<String, dynamic>);
      oldRes = _err(() => OldValidation.product(p)) == null ? 'valid' : 'invalid';
    } catch (e) {
      oldRes = 'THROW $e';
    }
    print('  fromJson $json\n    new: $newRes\n    old-validator: $oldRes');
  }

  // dish(): retention 0 and customYield in (0.1, 1.0)
  final base = [Ingredient(id: 'i', product: prod(), weightGrams: 100)];
  final dishProbes = <String, Dish>{
    'retention 0/0/0': dishOf(base, rp: 0, rf: 0, rc: 0),
    'retention 0.005': dishOf(base, rp: .005, rf: .005, rc: .005),
    'retention 0.01': dishOf(base, rp: .01, rf: .01, rc: .01),
    'yield 0.1': dishOf(base, y: 0.1),
    'yield 0.5': dishOf(base, y: 0.5),
    'yield 0.99': dishOf(base, y: 0.99),
    'yield 1.0': dishOf(base, y: 1.0),
  };
  for (final e in dishProbes.entries) {
    final oldOk = _err(() => OldValidation.dish(e.value)) == null;
    final newOk = _err(() => CalculationValidation.dish(e.value)) == null;
    print('  ${oldOk == newOk ? "SAME" : "DIFF"}  dish ${e.key}: '
        'oldValid=$oldOk newValid=$newOk  '
        'oldEffYield=${e.value.customYieldGrams} '
        'newEffYield=${e.value.effectiveYieldGrams}');
  }
}

// ===========================================================================
// 3. calculate() — legacy documents must be bit-identical
// ===========================================================================
void legacyIdentity() {
  print('\n=== [3] legacy (process absent) old vs new calculate() ===');
  const names = [
    'Морковь', 'Говядина 1 кат.', 'Вода питьевая', 'Макароны', 'Сыр',
    'Масло подсолнечное', 'Сахар-песок', 'Капуста белокочанная', 'Хлеб',
    'Яйцо куриное', 'Рис', 'Гречка', 'Свинина', 'Лук репчатый'
  ];
  var compared = 0;
  var mismatched = 0;
  var statusDiff = 0;
  final examples = <String>[];
  for (var i = 0; i < 4000; i++) {
    final n = 1 + rng.nextInt(4);
    final ings = <Ingredient>[];
    for (var k = 0; k < n; k++) {
      ings.add(Ingredient(
        id: 'i$k',
        product: prod(
          name: names[rng.nextInt(names.length)],
          protein: rng.nextDouble() * 25,
          fat: rng.nextDouble() * 20,
          carbs: rng.nextDouble() * 60,
          wastePct: rng.nextBool() ? 0 : rng.nextDouble() * 45,
        ),
        weightGrams: 1 + rng.nextDouble() * 400,
        isGross: rng.nextBool(),
      ));
    }
    final d = dishOf(
      ings,
      y: rng.nextBool() ? null : 50 + rng.nextDouble() * 900,
      rp: 0.01 + rng.nextDouble() * 0.99,
      rf: 0.01 + rng.nextDouble() * 0.99,
      rc: 0.01 + rng.nextDouble() * 0.99,
      mode: rng.nextBool() ? BlankMode.detailed : BlankMode.photoCross,
    );
    final a = runOld(d);
    final b = runNew(d);
    compared++;
    final dd = diffOf(a, b);
    if (dd != 'none') {
      if (dd == 'status' || dd == 'error-text') statusDiff++;
      mismatched++;
      if (examples.length < 6) examples.add('$dd | old=$a new=$b | ${d.toJson()['ingredients']}');
    }
  }
  print('  random legacy dishes compared=$compared differing=$mismatched '
      '(status/error diffs=$statusDiff)');
  for (final e in examples) {
    print('    EX $e');
  }

  // Every documented boundary the old engine used to reject must still be
  // rejected; every accepted one must give identical numbers.
  final edge = <String, Dish>{
    'empty recipe': dishOf(const []),
    'y=0 explicit': dishOf([Ingredient(id: 'i', product: prod(), weightGrams: 100)], y: 0),
    'macros > yield': dishOf([Ingredient(id: 'i', product: prod(protein: 100, fat: 0, carbs: 0), weightGrams: 200)], y: 100),
    'y=0.1': dishOf([Ingredient(id: 'i', product: prod(), weightGrams: 100)], y: 0.1),
    'y=0.5': dishOf([Ingredient(id: 'i', product: prod(), weightGrams: 1)], y: 0.5),
    'waste=100 gross': dishOf([
      Ingredient(id: 'i', product: prod(wastePct: 100), weightGrams: 200, isGross: true)
    ]),
    'retention=0': dishOf([Ingredient(id: 'i', product: prod(), weightGrams: 100)], rp: 0, rf: 0, rc: 0),
  };
  for (final e in edge.entries) {
    final a = runOld(e.value);
    final b = runNew(e.value);
    final dd = diffOf(a, b);
    print('  ${dd == 'none' ? "SAME" : "DIFF($dd)"}  ${e.key}: old=$a new=$b');
  }
}

// ===========================================================================
// 4. Non-legacy process + Dish.fromJson defaults => retention applied twice?
// ===========================================================================
void doubleLoss() {
  print('\n=== [4] fromJson({"process": ...}) without retention keys ===');
  final docJson = <String, dynamic>{
    'id': 'doc-1',
    'title': 'Каша гречневая',
    'ingredients': [
      {
        'id': 'i1',
        'weightGrams': 100.0,
        'isGross': false,
        'product': {
          'id': 654,
          'code': '654',
          'name': 'Крупа гречневая ядрица',
          'group_id': 1,
          'source': 'skurikhin',
          'protein': 12.6,
          'fat': 3.3,
          'carbs': 57.1,
          'kcal': 308.0,
        }
      }
    ],
    'customYieldGrams': 210.0,
    'blankMode': 'photoCross',
    'process': 'grain',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  };
  final fromJson = Dish.fromJson(docJson);
  print('  fromJson retention triple = ${fromJson.retentionProtein}/'
      '${fromJson.retentionFat}/${fromJson.retentionCarbs}, process=${fromJson.process}');
  // Nutrients-only model: the weight of the cooked dish is entered by the
  // cook; the alias 'grain' is read as HeatProcess.boil.
  expect(fromJson.process, HeatProcess.boil);
  final asWritten = runNew(fromJson);
  final asFactory = runNew(Dish.withProcess(
      id: 'x',
      process: HeatProcess.boil,
      customYieldGrams: 210,
      ingredients: fromJson.ingredients));
  final asLegacy = runOld(dishOf(fromJson.ingredients, y: 210));
  print('  NEW calculate(fromJson doc)         : $asWritten');
  print('  NEW calculate(Dish.withProcess)     : $asFactory');
  print('  OLD calculate(legacy, same recipe)  : $asLegacy');
  final lossFromJson = asFactory.ok
      ? asWritten.r!.cookedProtein / asFactory.r!.cookedProtein
      : double.nan;
  print('  extra factor applied on top of the '
      'loss table = ${lossFromJson.toStringAsFixed(4)} '
      '(expected 1.0000)');
  expect(lossFromJson, closeTo(1.0, 1e-9),
      reason: 'a stored retention triple must not be applied twice');

  // The same document with the triple the app writes for a new non-legacy dish
  final okDoc = Map<String, dynamic>.of(docJson)
    ..['retentionProtein'] = 1.0
    ..['retentionFat'] = 1.0
    ..['retentionCarbs'] = 1.0;
  print('  with explicit retention 1/1/1       : ${runNew(Dish.fromJson(okDoc))}');

  // copyWith(process: ...) on a legacy dish
  final legacy = dishOf(fromJson.ingredients, y: 210);
  final copied = legacy.copyWith(process: HeatProcess.boil);
  print('  NEW copyWith(process: boil) on legacy '
      '(retention ${copied.retentionProtein}/${copied.retentionFat}/${copied.retentionCarbs}): '
      '${runNew(copied)}');
  for (final p in HeatProcess.values) {
    final d = Dish.fromJson(<String, dynamic>{
      ...docJson,
      'process': p.name,
    });
    print('  process=${p.name.padRight(8)} P F C kcal = '
        '${d.effectiveYieldGrams} / ${runNew(d)}');
    expect(d.process, p, reason: 'process name round-trips');
  }
}

// ===========================================================================
// 5. rawTotalKcal — consumers and null semantics
// ===========================================================================
void rawKcal() {
  print('\n=== [5] rawTotalKcal ===');
  final d = dishOf([
    Ingredient(id: 'i', product: prod(), weightGrams: 200)
  ], mode: BlankMode.photoCross);
  final r = CalculationEngine.calculate(d);
  print('  photoCross rawTotalKcal = ${r.rawTotalKcal} (old: '
      '${OldEngine.calculate(d).rawTotalKcal}) — null in BOTH');
  final dd = dishOf([
    Ingredient(id: 'i', product: prod(), weightGrams: 200)
  ], mode: BlankMode.detailed);
  print('  detailed   rawTotalKcal = ${CalculationEngine.calculate(dd).rawTotalKcal} '
      '(old: ${OldEngine.calculate(dd).rawTotalKcal})');
}

// ===========================================================================
// 6. effectiveYieldGrams for non-legacy processes (entered weight only)
// ===========================================================================
void yieldDiff() {
  print('\n=== [6] effectiveYieldGrams, non-legacy ===');
  final ings = [
    Ingredient(
        id: 'i1',
        product: prod(name: 'Крупа гречневая ядрица', protein: 12.6, fat: 3.3, carbs: 57.1),
        weightGrams: 100),
    Ingredient(
        id: 'i2', product: prod(name: 'Вода питьевая', protein: 0, fat: 0, carbs: 0), weightGrams: 150),
  ];
  for (final y in <double?>[null, 0.1, 0.5, 0.99, 1.0, 210.0]) {
    final d = dishOf(ings, y: y, process: HeatProcess.boil);
    print('  customYield=$y -> new effectiveYield=${d.effectiveYieldGrams}, '
        'old=${oldEffectiveYield(d)}');
    // The new model never guesses the weight: below the threshold it is 0.
    expect(d.effectiveYieldGrams,
        (y != null && y >= CalculationValidation.minCustomYieldGrams) ? y : 0.0);
  }
}

// ===========================================================================
// 7. masters_recipes cards: old vs new numbers
// ===========================================================================
void mastersDiff() {
  print('\n=== [7] masters_recipes cards ===');
  for (final m in MastersRecipesCatalog.recipes) {
    final newDish = m.toDish();
    // HEAD 658d3ff: every card carried the legacy triple 0.94/0.88/0.91.
    final oldDish = Dish(
      id: 'o',
      title: m.name,
      customYieldGrams: m.expectedYieldGrams,
      retentionProtein: kLegacyRetentionProtein,
      retentionFat: kLegacyRetentionFat,
      retentionCarbs: kLegacyRetentionCarbs,
      ingredients: m.ingredients.map((i) => i.toIngredient()).toList(),
      blankMode: BlankMode.detailed,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final a = runOld(oldDish);
    final b = runNew(newDish);
    print('  ${m.name}  [${m.culinaryProcess} -> ${m.heatProcess.name}]');
    print('    OLD $a');
    print('    NEW $b   retention=${newDish.retentionProtein}/'
        '${newDish.retentionFat}/${newDish.retentionCarbs}');
    // What WOULD the card give with the legacy triple (i.e. the numbers the
    // card was authored against)?
    final r = newDish.copyWith(
      process: HeatProcess.legacy,
      retentionProtein: kLegacyRetentionProtein,
      retentionFat: kLegacyRetentionFat,
      retentionCarbs: kLegacyRetentionCarbs,
    );
    print('    legacy triple  : ${runNew(r)}');
    expect(diffOf(a, runNew(r)), 'none',
        reason: '${m.name}: legacy mode must reproduce HEAD numbers');
  }
}

// ===========================================================================
// 8. toJson byte-compatibility for a legacy dish
// ===========================================================================
void jsonCompat() {
  print('\n=== [8] toJson of a legacy dish ===');
  final d = dishOf([
    Ingredient(id: 'i', product: prod(), weightGrams: 200)
  ], y: 150);
  final json = jsonEncode(d.toJson());
  print('  keys = ${d.toJson().keys.toList()}');
  print('  contains "process" = ${json.contains('process')}');
  final oldKeys = <String>[
    'id', 'title', 'showTitleInExport', 'showPer100gRowInExport',
    'ingredients', 'customYieldGrams', 'retentionProtein', 'retentionFat',
    'retentionCarbs', 'blankMode', 'createdAt', 'updatedAt'
  ];
  print('  key order identical to HEAD = '
      '${jsonEncode(d.toJson().keys.toList()) == jsonEncode(oldKeys)}');
  // round-trip through the NEW reader must keep the numbers
  final back = Dish.fromJson(jsonDecode(json) as Map<String, dynamic>);
  print('  round-trip process = ${back.process}, numbers identical = '
      '${diffOf(runOld(d), runNew(back)) == 'none'}');
  // non-legacy dish writes the key
  final nd = d.copyWith(process: HeatProcess.boil);
  final hasKey = jsonEncode(nd.toJson()).contains('"process":"boil"');
  print('  non-legacy toJson contains "process":"boil" = $hasKey');
  expect(hasKey, isTrue);
}

// ===========================================================================
// 9. FoodClassifier + LossTable (replaces classifyProduct/lossProfileFor)
// ===========================================================================
void classifyDiff() {
  print('\n=== [9] FoodClassifier — group and boil loss ===');
  for (final n in [
    'Вода питьевая', 'Вода', 'Говядина 1 кат.', 'Морковь', 'Капуста белокочанная',
    'Крупа гречневая ядрица', 'Рис', 'Молоко 3,2%', 'Яйцо куриное',
    'Творог полужирный 9,0% жирности', 'Масло сливочное', 'Сахар-песок',
    'Уксус столовый', 'Соль поваренная', 'Сыр твёрдый',
  ]) {
    final c = FoodClassifier.classifyByName(n);
    print('  ${n.padRight(36)} -> ${c.name.padRight(14)} '
        'boil-loss=${LossTable.lossFor(c, HeatProcess.boil).protein}%P');
  }
}

void main() {
  test('reaudit differential harness', () {
    mathDiff();
    validationDiff();
    legacyIdentity();
    doubleLoss();
    rawKcal();
    yieldDiff();
    mastersDiff();
    jsonCompat();
    classifyDiff();
  });
}
