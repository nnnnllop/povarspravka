// DIFFERENTIAL / REGRESSION HARNESS — part 2 (read-only audit).
//
// Round 2 probes derived from round 1 evidence:
//  * method meaning (measure) filter before/after the fix, over the real
//    reference.db measure table (mode=ro);
//  * runtime conformance of the new validators against every product row of
//    the real reference.db;
//  * "promote on save": saving a pre-2 parameter change writes a document the
//    previous binary reads differently;
//  * the -0.0 measurement in isolation.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

import 'support/reference_db.dart';

void main() {
  test('reaudit differential harness round 2', () async {
    _measureFilter();
    await _realDbConformance();
    _promoteOnSave();
    _negativeZero();
  });
}

// ---------------------------------------------------------------------------
// HEAD models/product.dart `calculationMeasures`
// ---------------------------------------------------------------------------
List<ProductMeasure> oldMeasures(Product p) {
  if (!p.isSkurikhin) {
    return p.measures.where((m) {
      if (!m.grams.isFinite || m.grams <= 0 || m.grams > 5000) return false;
      final mLower = m.name.toLowerCase();
      final pLower = p.name.toLowerCase();
      if (mLower.contains('egg') ||
          pLower.contains('яйц') ||
          mLower.contains('яйц')) {
        final isQuail = mLower.contains('quail') || pLower.contains('перепел');
        if (isQuail) {
          if (m.grams < 6.0 || m.grams > 25.0) return false;
        } else {
          if (m.grams < 25.0 || m.grams > 120.0) return false;
        }
      }
      if (mLower.contains('cup') || mLower.contains('стакан')) {
        if (m.grams < 50.0 || m.grams > 450.0) return false;
      }
      if (mLower.contains('tbsp') || mLower.contains('столовая лож')) {
        if (m.grams < 3.0 || m.grams > 50.0) return false;
      }
      if (mLower.contains('tsp') || mLower.contains('чайная лож')) {
        if (m.grams < 0.5 || m.grams > 25.0) return false;
      }
      return true;
    }).toList();
  }
  final values = switch (p.name) {
    'Яйцо куриное' => {'1 шт. (1 категория, нетто)': 47.0},
    'Яйцо перепелиное' => {'1 шт. (нетто)': 9.0},
    'Сметана 10,0% жирности' => {
        'стакан (чайный 250 мл)': 250.0,
        'стакан (граненый 200 мл)': 200.0,
        'столовая ложка': 20.0,
        'чайная ложка': 9.0
      },
    'Сметана 30,0% жирности' => {
        'стакан (чайный 250 мл)': 250.0,
        'стакан (граненый 200 мл)': 200.0,
        'столовая ложка': 25.0,
        'чайная ложка': 11.0
      },
    _ => <String, double>{},
  };
  return values.entries
      .toList()
      .asMap()
      .entries
      .map((entry) => ProductMeasure(
          id: -(entry.key + 1),
          productId: p.id,
          name: entry.value.key,
          grams: entry.value.value))
      .toList();
}

void _measureFilter() {
  print('\n=== [10] calculationMeasures (HEAD formula) vs calculationMeasures (fix) ===');
  // Pure in-memory cases first: no database needed.
  final sugar = Product(
    id: 1,
    code: '1',
    name: 'Сахар-песок',
    groupId: 1,
    source: 'skurikhin',
    protein: 0,
    fat: 0,
    carbs: 99.8,
    kcal: 399,
    measures: const [
      ProductMeasure(id: 1, productId: 1, name: 'стакан (250 мл)', grams: 200),
      ProductMeasure(id: 2, productId: 1, name: '1 ч. л.', grams: 8),
    ],
  );
  print('  Сахар-песок (skurikhin, 2 measures in DB): '
      'old=${oldMeasures(sugar).length} new=${sugar.calculationMeasures.length} '
      'names new=${sugar.calculationMeasures.map((m) => m.name).toList()}');
  final cream = Product(
    id: 2,
    code: '2',
    name: 'Сметана 20%',
    groupId: 1,
    source: 'skurikhin',
    protein: 2.8,
    fat: 20,
    carbs: 3.2,
    kcal: 204,
    measures: const [
      ProductMeasure(id: 3, productId: 2, name: 'стакан', grams: 2000),
      ProductMeasure(id: 4, productId: 2, name: 'ложка', grams: 20),
    ],
  );
  print('  Сметана 20% (measures 2000 g + 20 g): '
      'old=${oldMeasures(cream).map((m) => m.grams).toList()} '
      'new=${cream.calculationMeasures.map((m) => m.grams).toList()}');
  final quail = Product(
    id: 3,
    code: '3',
    name: 'Яйцо перепелиное',
    groupId: 1,
    source: 'bls',
    protein: 11.9,
    fat: 13.1,
    carbs: 0.6,
    kcal: 168,
    measures: const [
      ProductMeasure(id: 5, productId: 3, name: 'egg', grams: 9),
    ],
  );
  print('  Яйцо перепелиное/bls/"egg" 9 g: '
      'old=${oldMeasures(quail).length} new=${quail.calculationMeasures.length}');
  final water = Product(
    id: 4,
    code: '4',
    name: 'Вода',
    groupId: 1,
    source: 'supplement',
    protein: 0,
    fat: 0,
    carbs: 0,
    kcal: 0,
    measures: const [
      ProductMeasure(id: 6, productId: 4, name: 'стакан', grams: 2000),
    ],
  );
  print('  Вода/supplement/"стакан" 2000 g: '
      'old=${oldMeasures(water).length} new=${water.calculationMeasures.length}');
}

// ---------------------------------------------------------------------------
// real DB conformance — the Dart side of db_validate.py
// ---------------------------------------------------------------------------
Future<void> _realDbConformance() async {
  print('\n=== [11] real reference.db vs new validators ===');
  // Строки читаются прямо из assets/db/reference.db (только чтение); раньше — из
  // выгрузки %TEMP%\povar_reaudit\regress\products_dump.json, которой нет
  // на чистой машине.
  final products = await loadAllReferenceProducts();
  expect(products, isNotEmpty);
  var invalid = 0;
  final examples = <String>[];
  for (final p in products) {
    if (!CalculationValidation.isValidProduct(p)) {
      invalid++;
      if (examples.length < 5) examples.add('${p.id} ${p.name}');
    }
  }
  print('  products in reference.db = ${products.length}; '
      'CalculationValidation.isValidProduct == false on $invalid');
  print('  examples: $examples');
  // the new `sum > 100` boundary is already enforced by HEAD: show the max
  var maxSum = 0.0;
  for (final p in products) {
    final s = p.protein + p.fat + p.carbs;
    if (s > maxSum) maxSum = s;
  }
  print('  max(P+F+C) over the whole DB = $maxSum');
}

// ---------------------------------------------------------------------------
// promote-on-save
// ---------------------------------------------------------------------------
void _promoteOnSave() {
  print('\n=== [12] saving a pre-2 document promotes it (old binary then '
      'computes different numbers) ===');
  final legacyDoc = <String, dynamic>{
    'id': 'doc-legacy',
    'title': 'Борщ',
    'ingredients': [
      {
        'id': 'i1',
        'weightGrams': 200.0,
        'isGross': false,
        'product': {
          'id': 779,
          'code': '779',
          'name': 'Свекла',
          'group_id': 1,
          'source': 'skurikhin',
          'protein': 1.5,
          'fat': 0.1,
          'carbs': 8.8,
          'kcal': 42.0,
        }
      }
    ],
    'customYieldGrams': 150.0,
    'retentionProtein': 0.94,
    'retentionFat': 0.88,
    'retentionCarbs': 0.91,
    'blankMode': 'photoCross',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  };
  final dish = Dish.fromJson(legacyDoc);
  print('  1) object read from a pre-2 document: process=${dish.process.name}');
  print('     toJson contains "process" = '
      '${jsonEncode(dish.toJson()).contains('"process"')}');
  // The only way a pre-2 user reaches a non-legacy process is the dialog:
  // pick any process, then pick "Без т.о. (100%)" or 94/88/91 by hand.
  final afterDialog = dish.copyWith(
      process: HeatProcess.cold, retentionProtein: 1, retentionFat: 1, retentionCarbs: 1);
  final asWritten = afterDialog.toJson();
  print('  2) after the parameters dialog set retention 100 %: '
      'process=${afterDialog.process.name}, retention='
      '${afterDialog.retentionProtein}/${afterDialog.retentionFat}/'
      '${afterDialog.retentionCarbs}');
  print('     document written by the NEW binary = '
      '${jsonEncode(asWritten)}');
  // The PREVIOUS binary knows nothing about `process`.
  final oldRead = Dish(
    id: asWritten['id'] as String,
    title: asWritten['title'] as String,
    customYieldGrams: (asWritten['customYieldGrams'] as num).toDouble(),
    retentionProtein: (asWritten['retentionProtein'] as num).toDouble(),
    retentionFat: (asWritten['retentionFat'] as num).toDouble(),
    retentionCarbs: (asWritten['retentionCarbs'] as num).toDouble(),
    ingredients: (asWritten['ingredients'] as List)
        .cast<Map<String, dynamic>>()
        .map(Ingredient.fromJson)
        .toList(),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  print('  3) PREVIOUS binary prints the same file as: '
      '${_fmt(oldRead)}  (its own numbers)');
  print('     NEW binary prints it as:                    ${_fmt(dish)}');
}

String _fmt(Dish d) {
  final p = CalculationMath.productRounded(
      CalculationMath.sumRounded(d.ingredients.map((i) => i.proteinInDish), 2),
      CalculationMath.productRounded(d.retentionProtein, 100, 10), 2,
      divideBy100: true);
  final f = CalculationMath.productRounded(
      CalculationMath.sumRounded(d.ingredients.map((i) => i.fatInDish), 2),
      CalculationMath.productRounded(d.retentionFat, 100, 10), 2,
      divideBy100: true);
  final c = CalculationMath.productRounded(
      CalculationMath.sumRounded(d.ingredients.map((i) => i.carbsInDish), 2),
      CalculationMath.productRounded(d.retentionCarbs, 100, 10), 2,
      divideBy100: true);
  final pctP = CalculationMath.productRounded(d.retentionProtein, 100, 10);
  return 'P=$p F=$f C=$c (%${pctP.toStringAsFixed(1)} retention applied by '
      'the OLD engine regardless of `process`)';
}

// ---------------------------------------------------------------------------
// -0.0 measurement
// ---------------------------------------------------------------------------
void _negativeZero() {
  print('\n=== [13] -0.0 ===');
  double minusZero() => 0.0 * -1.0;
  final mz = minusZero();
  print('  (0.0*-1.0).isNegative = ${mz.isNegative}, a==0.0 -> ${mz == 0.0}');
  print('  NEW productRounded(-0.0, 5, 2) = ${CalculationMath.productRounded(mz, 5, 2)} '
      'sign=${CalculationMath.productRounded(mz, 5, 2).sign}');
  print('  HEAD productRounded(-0.0, 5, 2): identical body '
      '(see calculation_math.dart:16-18 == HEAD lines 16-18), '
      'so no behavioural delta exists; measured via differential run [1].');
}
