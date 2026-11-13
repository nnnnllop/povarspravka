// RE-AUDIT (adversarial-fuzzer): seeded corpus + helpers. Not production code.
//
// Everything here is DETERMINISTIC: every dish is a pure function of its seed,
// so a failing case can be replayed with
//   flutter test test/reaudit_fuzz_property_test.dart --dart-define=FUZZ_SEED=<seed>
import 'dart:convert';
import 'dart:math';

import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

DateTime _ts(int i) => DateTime.utc(2026, 10, 31, 12, 0, i % 60);

/// Adversarial product names required by the task.
const List<String> kAdversarialNames = [
  '',
  'вода',
  'Вода питьевая',
  'бульон куриный',
  'молоко',
  'гречка',
  'рис',
  'макароны',
  '🍲🥘🍳',
  'ВОДА ПИТЬЕВАЯ',
  'BOДA Питьевая', // Latin homoglyphs inside a Cyrillic word
  'Гречкa', // Latin 'a' at the end
  'PИC', // Latin P + Cyrillic ИС
  'Макарoны', // Latin o
  'water',
  'Вода дистиллированная',
  'Крупа',
  'мука',
  'хлеб',
  'мясо',
  'творог',
  'сыр',
  'яйцо',
  'сливки',
  'масло',
  'сахар',
  'мёд',
  'мед',
  'морковь',
  'лук',
  'свекла',
  'картофель',
  'капуста',
  'огурцы',
  'горошек',
  'клюква',
  '\u0000\u0001\u0002',
  'вода\n\n\t',
  '制造',
  'ﬁ ligature',
  '😀water😀',
];

const String kVseEmoji = '🥘🍳🍲🥩🥕🧂🍚';

// ---------------------------------------------------------------------------
// Real products from app/assets/db/reference.db (read-only dump, 8261 rows).
// ---------------------------------------------------------------------------

class RealProduct {
  final int id;
  final String name;
  final String source;
  final int groupId;
  final String code;
  final double wastePct;
  final double protein;
  final double fat;
  final double carbs;
  final double kcal;
  final double water;
  final double fiber;
  final double ash;
  final double organicAcids;
  final double sugars;
  final double starch;
  final double sfa;
  final double pufa;
  final double chol;
  final double alcohol;
  final Object? isDish;
  final String? nameNorm;
  final Object? pageNum;

  const RealProduct({
    required this.id,
    required this.name,
    required this.source,
    required this.groupId,
    required this.code,
    required this.wastePct,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.kcal,
    required this.water,
    required this.fiber,
    required this.ash,
    required this.organicAcids,
    required this.sugars,
    required this.starch,
    required this.sfa,
    required this.pufa,
    required this.chol,
    required this.alcohol,
    required this.isDish,
    required this.nameNorm,
    required this.pageNum,
  });
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

RealProduct realProductFromJson(Map<String, dynamic> m) => RealProduct(
      id: (m['id'] as num).toInt(),
      name: (m['name'] as String?) ?? '',
      source: (m['source'] as String?) ?? 'skurikhin',
      groupId: (m['group_id'] as num?)?.toInt() ?? 0,
      code: (m['code'] as String?) ?? '',
      wastePct: _d(m['waste_pct']),
      protein: _d(m['protein']),
      fat: _d(m['fat']),
      carbs: _d(m['carbs']),
      kcal: _d(m['kcal']),
      water: _d(m['water']),
      fiber: _d(m['fiber']),
      ash: _d(m['ash']),
      organicAcids: _d(m['organic_acids']),
      sugars: _d(m['sugars']),
      starch: _d(m['starch']),
      sfa: _d(m['sfa']),
      pufa: _d(m['pufa']),
      chol: _d(m['chol']),
      alcohol: _d(m['alcohol']),
      isDish: m['is_dish'],
      nameNorm: m['name_norm'] as String?,
      pageNum: m['page_num'],
    );

Product productFromReal(RealProduct p, {double? wasteOverride}) {
  final json = <String, dynamic>{
    'id': p.id,
    'code': p.code,
    'name': p.name,
    'name_norm': p.nameNorm,
    'group_id': p.groupId,
    'source': p.source,
    'page_num': p.pageNum,
    'waste_pct': wasteOverride ?? p.wastePct,
    'protein': p.protein,
    'fat': p.fat,
    'carbs': p.carbs,
    'kcal': p.kcal,
    'water': p.water,
    'fiber': p.fiber,
    'ash': p.ash,
    'organic_acids': p.organicAcids,
    'sugars': p.sugars,
    'starch': p.starch,
    'sfa': p.sfa,
    'pufa': p.pufa,
    'chol': p.chol,
    'alcohol': p.alcohol,
    if (p.isDish != null) 'is_dish': p.isDish,
    'measures': const <dynamic>[],
  };
  return Product.fromJson(json);
}

Product syntheticProduct({
  required String name,
  double protein = 10,
  double fat = 5,
  double carbs = 20,
  double waste = 0,
  double kcal = 165,
  bool explicitKcal = true,
  int id = 1,
}) {
  final json = <String, dynamic>{
    'id': id,
    'code': 'SYN',
    'name': name,
    'group_id': 99,
    'source': 'skurikhin',
    'waste_pct': waste,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    if (explicitKcal) 'kcal': kcal,
    'water': 0.0,
    'measures': const <dynamic>[],
  };
  return Product.fromJson(json);
}

// ---------------------------------------------------------------------------
// Weights / retention
// ---------------------------------------------------------------------------

const List<double> kWeights = [0, 0.001, 0.05, 0.1, 1, 17.3, 999, 1e6];
const List<double> kWastes = [0, 1, 33.3, 50, 90, 99, 99.999];
const List<double?> kCustomYields = [null, 0.1, 1, 0.11, 0.5, 9999999];
const List<double> kRetentions = [1.0, 0.01, 0.935, 0.88, 0.5, 0.94];
const List<(double, double, double)> kRetentionTriples = [
  (1.0, 1.0, 1.0),
  (0.01, 0.01, 0.01),
  (0.94, 0.88, 0.91), // default legacy triple
  (0.5, 0.5, 0.5),
  (1.0, 0.5, 0.01),
  (0.935, 0.917, 0.918),
];

const List<double> kScaleFactors = [1.0001, 1.01, 1.5, 2, 10, 1000];

// ---------------------------------------------------------------------------
// BЖУ triples
// ---------------------------------------------------------------------------

class Nutri {
  final double p, f, c, kcal;
  const Nutri(this.p, this.f, this.c, this.kcal);
}

const List<Nutri> kNutri = [
  Nutri(0, 0, 0, 0),
  Nutri(100, 0, 0, 400),
  Nutri(0, 100, 0, 900),
  Nutri(0, 0, 100, 400),
  Nutri(0, 0, 100, 0), // carbs but zero kcal declared
  Nutri(10, 5, 85, 425), // P+F+C = 100 exactly
  Nutri(33, 33, 34, 300),
  Nutri(0.01, 0.01, 0.01, 0),
  Nutri(16.0, 51.0, 0.5, 850), // butter-like
  Nutri(35.0, 15.0, 0.0, 275), // fatty sauce: БЖУ mass > 100 g per 100 g?
  Nutri(85, 15, 0, 475), // macro mass 100 g, mostly fat
];

// ---------------------------------------------------------------------------
// Generated dish bundle
// ---------------------------------------------------------------------------

class GenDish {
  final int seed;
  final Dish dish;
  final HeatProcess process;
  final BlankMode mode;
  final bool hadEmptyName;
  GenDish(this.seed, this.dish, this.process, this.mode, this.hadEmptyName);

  Map<String, dynamic> toJson() => dish.toJson();
}

class DishBreeder {
  DishBreeder(this.realProducts);

  final List<RealProduct> realProducts;
  List<RealProduct> _adversarialPool = const [];
  List<Product> _syntheticPool = const [];

  /// Products from the DB whose real BЖУ are extremes (0 and 100).
  void buildPools(Random r) {
    final pool = <RealProduct>[];
    // Real rows that exercise extremes.
    final zeros = realProducts
        .where((p) =>
            p.protein == 0 &&
            p.fat == 0 &&
            p.carbs == 0 &&
            p.wastePct >= 90)
        .take(300)
        .toList();
    final high = realProducts.where((p) => p.fat >= 80).take(50).toList();
    final sumHundred =
        realProducts.where((p) => (p.protein + p.fat + p.carbs) >= 99.9).take(50);
    pool.addAll(zeros);
    pool.addAll(high);
    pool.addAll(sumHundred);
    if (pool.length < 40) pool.addAll(realProducts.take(600));
    _adversarialPool = pool;
    _syntheticPool = <Product>[
      for (var i = 0; i < kNutri.length; i++) _synth(kNutri[i], i),
    ];
  }

  int get adversarialPoolSize => _adversarialPool.length;

  Product _synth(Nutri n, int i) {
    final name = kAdversarialNames[(i * 3) % kAdversarialNames.length];
    return Product.fromJson(<String, dynamic>{
      'id': 900000 + i,
      'code': 'ADV$i',
      'name': name,
      'group_id': 99,
      'source': 'skurikhin',
      'waste_pct': 0.0,
      'protein': n.p,
      'fat': n.f,
      'carbs': n.c,
      'kcal': n.kcal,
      'water': 0.0,
      'measures': const <dynamic>[],
    });
  }

  Product pickProduct(Random r, {double? wasteOverride}) {
    if (r.nextInt(100) < 22) {
      return _syntheticPool[r.nextInt(_syntheticPool.length)];
    }
    if (r.nextInt(100) < 12) {
      final name = r.nextInt(40) == 0
          ? kVseEmoji * 50 // 500-char emoji name
          : kAdversarialNames[r.nextInt(kAdversarialNames.length)];
      final n = kNutri[r.nextInt(kNutri.length)];
      final waste = wasteOverride ?? kWastes[r.nextInt(kWastes.length)];
      return Product.fromJson(<String, dynamic>{
        'id': 800000 + r.nextInt(1000),
        'code': 'C',
        'name': name,
        'group_id': 1,
        'source': 'skurikhin',
        'waste_pct': waste,
        'protein': n.p,
        'fat': n.f,
        'carbs': n.c,
        'kcal': n.kcal,
        'measures': const <dynamic>[],
      });
    }
    final rp = r.nextInt(100) < 20
        ? _adversarialPool[r.nextInt(_adversarialPool.length)]
        : realProducts[r.nextInt(realProducts.length)];
    final waste = wasteOverride ??
        (r.nextInt(100) < 50 ? rp.wastePct : kWastes[r.nextInt(kWastes.length)]);
    return productFromReal(rp, wasteOverride: waste);
  }

  GenDish breed(int seed) {
    final r = Random(seed);
    final n = seed % 5 == 0 ? 0 : r.nextInt(41); // 0..40, empty meals guaranteed
    final process = HeatProcess.values[r.nextInt(HeatProcess.values.length)];
    final mode = BlankMode.values[r.nextInt(BlankMode.values.length)];
    final triple = kRetentionTriples[r.nextInt(kRetentionTriples.length)];
    final custom = kCustomYields[r.nextInt(kCustomYields.length)];
    final ings = <Ingredient>[];
    var emptyName = false;
    for (var i = 0; i < n; i++) {
      final weight = kWeights[r.nextInt(kWeights.length)];
      final product = pickProduct(r);
      if (product.name.isEmpty) emptyName = true;
      ings.add(Ingredient(
        id: 'i$i',
        product: product,
        weightGrams: weight,
        isGross: r.nextBool(),
      ));
    }
    final dish = Dish(
      id: 'dish-$seed',
      title: 'Блюдо $seed ${kAdversarialNames[seed % kAdversarialNames.length]}',
      ingredients: ings,
      customYieldGrams: custom,
      retentionProtein: triple.$1,
      retentionFat: triple.$2,
      retentionCarbs: triple.$3,
      blankMode: mode,
      process: process,
      createdAt: _ts(seed),
      updatedAt: _ts(seed + 1),
    );
    return GenDish(seed, dish, process, mode, emptyName);
  }
}

/// Emit a dish JSON together with a one-line replay seed (never throws).
String explain(int seed, Dish dish) {
  String j;
  try {
    j = jsonEncode(dish.toJson());
  } catch (e) {
    j = '<unencodable: $e>';
  }
  return 'seed=$seed json=$j';
}

/// Structural equality on JSON.
bool jsonEq(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!jsonEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

bool _safeViolates(Dish d, bool Function(Dish) violates) {
  try {
    return violates(d);
  } catch (_) {
    return false;
  }
}

/// Deterministic 1-minimal reducer: repeatedly drops the first ingredient
/// whose removal still reproduces the violation. Result is smallest-by-drop.
Dish shrink(Dish base, bool Function(Dish) violates, {int maxPasses = 8}) {
  var current = base;
  for (var pass = 0; pass < maxPasses; pass++) {
    var dropped = false;
    for (var i = 0; i < current.ingredients.length; i++) {
      final candidate = current.copyWith(
          ingredients: [...current.ingredients]..removeAt(i));
      if (_safeViolates(candidate, violates)) {
        current = candidate;
        dropped = true;
        break;
      }
    }
    if (!dropped) break;
  }
  return current;
}
