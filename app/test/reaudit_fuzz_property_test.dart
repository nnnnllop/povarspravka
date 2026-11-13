// RE-AUDIT (adversarial-fuzzer): property-based tests of the calculation
// engine. Read-only w.r.t. production code; every case is a pure function of a
// seed, so failures replay with --dart-define=FUZZ_SEED=<seed>.
//
// Run:  flutter test test/reaudit_fuzz_property_test.dart
// One property: flutter test test/reaudit_fuzz_property_test.dart --plain-name "P2"
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/calculation_result.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

import 'reaudit_fuzz_corpus.dart';
import 'support/reference_db.dart';

// ---------------------------------------------------------------------------
// Exact decimal arithmetic written INDEPENDENTLY of the app (BigInt, HALF-UP
// over the decimal spelling of the double, i.e. Decimal(str(v))).
// ---------------------------------------------------------------------------

/// Why an exact decimal model instead of the app's own helper: the audit must
/// not reuse the code under test to compute its own expectation. This works on
/// the *decimal spelling* of the double (Decimal(str(v))), like the engine.
MapEntry<BigInt, int> decOfDouble(double v) {
  if (!v.isFinite) return MapEntry(BigInt.zero, 0);
  var t = v.toString().toLowerCase();
  var neg = false;
  if (t.startsWith('-')) {
    neg = true;
    t = t.substring(1);
  }
  var exp = 0;
  final e = t.indexOf('e');
  if (e >= 0) {
    exp = int.parse(t.substring(e + 1));
    t = t.substring(0, e);
  }
  var frac = 0;
  final dot = t.indexOf('.');
  if (dot >= 0) {
    frac = t.length - dot - 1;
    t = t.replaceAll('.', '');
  }
  var n = BigInt.parse(t);
  if (neg) n = -n;
  // value = n / 10^frac * 10^exp
  final scale = frac - exp;
  if (scale < 0) return MapEntry(n * BigInt.from(10).pow(-scale), 0);
  return MapEntry(n, scale);
}

/// Round `n / 10^s` HALF-UP (away from zero) to `frac` digits after comma.
BigInt halfUpRounded(BigInt n, int s, int frac) => _roundQuot(n, s - frac);

/// r = sign(n) * floor(|n| / 10^d + 1/2) for d>=0; d<0 multiplies instead.
BigInt _roundQuot(BigInt n, int d) {
  if (d <= 0) return n * BigInt.from(10).pow(-d);
  final den = BigInt.from(10).pow(d);
  final abs = n.abs();
  final q = (abs * BigInt.two + den) ~/ (den * BigInt.two);
  return n.isNegative ? -q : q;
}

double _toDouble(BigInt q, int frac) => q.toDouble() / pow(10, frac);

/// Independent implementation of `productRounded(a,b,digits,divideBy100)`.
double indepProductRound(double a, double b, int digits, {bool divideBy100 = false}) {
  if (a == 0.0 || b == 0.0) return 0.0;
  final da = decOfDouble(a);
  final db = decOfDouble(b);
  final n = da.key * db.key;
  final s = da.value + db.value + (divideBy100 ? 2 : 0);
  return _toDouble(halfUpRounded(n, s, digits), digits);
}

/// Independent `roundTo(v, d)`.
double indepRound(double v, int d) => indepProductRound(v, 1.0, d);

/// Independent `sumRounded`.
double indepSum(Iterable<double> values, int digits) {
  final ds = values.map(decOfDouble).toList();
  var sc = 0;
  for (final d in ds) {
    if (d.value > sc) sc = d.value;
  }
  var n = BigInt.zero;
  for (final d in ds) {
    n += d.key * BigInt.from(10).pow(sc - d.value);
  }
  return _toDouble(halfUpRounded(n, sc, digits), digits);
}

/// Independent `ratioRounded(value, divisor, digits, multiplier: m)`.
/// value = v*10^-sv, divisor = d*10^-sd, multiplier = m*10^-sm:
/// value/divisor*m = v*m*10^(sd-sv-sm)/d; rounded to `digits`.
double indepRatio(double value, double divisor, int digits, {double multiplier = 100}) {
  final dv = decOfDouble(value);
  final dd = decOfDouble(divisor);
  final dm = decOfDouble(multiplier);
  final n = dv.key * dm.key;
  var p = dd.value - dv.value - dm.value + digits;
  BigInt num;
  BigInt den;
  if (p >= 0) {
    num = n * BigInt.from(10).pow(p);
    den = dd.key;
  } else {
    num = n;
    den = dd.key * BigInt.from(10).pow(-p);
  }
  return _divRound(num, den, digits);
}

double _divRound(BigInt n, BigInt d, int digits) {
  // round(n/d) half-up away from zero; returns n/d rounded to `digits`
  final abs = n.abs();
  final q = (abs * BigInt.two + d) ~/ (d * BigInt.two);
  return _toDouble(n.isNegative ? -q : q, digits);
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

class Violation {
  final List<int> seeds;
  final int count;
  final String detail;
  final Dish? witness;
  Violation(this.seeds, this.count, this.detail, [this.witness]);
}

class PropLog {
  final String id;
  final String statement;
  int cases;
  final Violation? Function() run;
  Violation? result;
  String? crash;
  int ms = 0;
  bool get passed => crash == null && result == null;
  PropLog(this.id, this.statement, this.cases, this.run);
}

final List<PropLog> _logs = [];
final StringBuffer _out = StringBuffer();

void emit(String s) {
  _out.writeln(s);
  print(s);
}

PropLog register(String id, String statement, int cases, Violation? Function() run) {
  final log = PropLog(id, statement, cases, run);
  _logs.add(log);
  return log;
}

void exec(PropLog log, {bool mandatory = true}) {
  final sw = Stopwatch()..start();
  try {
    log.result = log.run();
  } catch (e, st) {
    log.crash = '$e | ${st.toString().split('\n').take(4).join(' / ')}';
  }
  sw.stop();
  log.ms = sw.elapsedMilliseconds;
  emit('## ${log.id} | cases=${log.cases} | ${log.ms} ms');
  if (log.crash != null) {
    emit('   UNHANDLED: ${log.crash}');
  } else if (log.result != null) {
    final v = log.result!;
    emit('   FAIL: verdict=${v.count}; seeds=${v.seeds.take(6).join(",")}');
    emit('   detail: ${v.detail}');
    if (v.witness != null) emit('   minimal: ${_jsonOf(v.witness!)}');
  } else {
    emit('   PASS');
  }
}

int get _baseSeed => const int.fromEnvironment('FUZZ_SEED', defaultValue: 20261031);

/// Loop count for a property. The default run (part of `flutter test`) uses
/// 1/100 of the full count (at least 50) so the suite stays fast;
/// `--dart-define=FUZZ_FULL=1` restores the full numbers and
/// `--dart-define=FUZZ_SMOKE=1` shrinks runs to a few dozen cases.
int _N(int full) => const bool.fromEnvironment('FUZZ_SMOKE')
    ? (full ~/ 1000).clamp(5, 50)
    : const bool.fromEnvironment('FUZZ_FULL')
        ? full
        : (full ~/ 100).clamp(50, full);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _jsonOf(Dish d) {
  try {
    return jsonEncode(d.toJson());
  } catch (e) {
    return '<unencodable $e>';
  }
}

Dish scaled(Dish d, double k) => d.copyWith(
      ingredients: [
        for (final i in d.ingredients) i.copyWith(weightGrams: i.weightGrams * k),
      ],
    );

bool sameJson(Dish a, Dish b) {
  try {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  } catch (_) {
    return false;
  }
}

/// Cached, shrinkable violation collector: first 4 originals + 2 minimized.
class Collector {
  final String cls;
  final List<String> originals = [];
  final List<String> minimized = [];
  final List<int> seeds = [];
  final Set<String> minimizedKeys = {};
  int count = 0;

  Collector(this.cls);

  void add(String msg, {Dish? witness, int? seed, void Function(Dish found)? shrinker}) {
    count++;
    if (originals.length < 4) originals.add(msg);
    if (seed != null) seeds.add(seed);
  }

  Dish? _best;
  void addShrinkable(String msg, Dish dish, bool Function(Dish) violates, int seed) {
    count++;
    if (originals.length < 4) originals.add(msg);
    seeds.add(seed);
    if (minimized.length >= 2) return;
    final small = shrink(dish, violates, maxPasses: 6);
    final key = jsonEncode(small.toJson());
    if (_best == null || small.ingredients.length < _best!.ingredients.length) {
      _best = small;
      minimized
        ..clear()
        ..add('seed=$seed ingredients=${small.ingredients.length} json=${key}');
    }
  }

  Violation? toViolation() {
    if (count == 0) return null;
    final buf = StringBuffer();
    for (final o in originals) {
      buf.writeln('[$cls] $o');
    }
    for (final m in minimized) {
      buf.writeln('[$cls] $m');
    }
    return Violation(seeds, count, buf.toString().trim(), _best);
  }
}

/// Attempt calculate, swallowing typed ArgumentErrors only.
CalculationResult? tryCalc(Dish d) {
  try {
    return CalculationEngine.calculate(d);
  } on ArgumentError {
    return null;
  }
}

Map<String, double> _byName(CalculationResult r) => {
      'yieldGrams': r.yieldGrams,
      'rawTotalWeight': r.rawTotalWeight,
      'rawTotalProtein': r.rawTotalProtein,
      'rawTotalFat': r.rawTotalFat,
      'rawTotalCarbs': r.rawTotalCarbs,
      if (r.rawTotalKcal != null) 'rawTotalKcal': r.rawTotalKcal!,
      'cookedProtein': r.cookedProtein,
      'cookedFat': r.cookedFat,
      'cookedCarbs': r.cookedCarbs,
      'cookedKcal': r.cookedKcal,
      'per100gProtein': r.per100gProtein,
      'per100gFat': r.per100gFat,
      'per100gCarbs': r.per100gCarbs,
      'per100gKcal': r.per100gKcal,
    };

// ---------------------------------------------------------------- fixtures
Dish dishOf(List<Ingredient> ings,
        {HeatProcess process = HeatProcess.legacy,
        double? customYield,
        BlankMode mode = BlankMode.photoCross,
        (double, double, double) ret = (0.94, 0.88, 0.91),
        String id = 'demo'}) =>
    Dish(
      id: id,
      ingredients: ings,
      process: process,
      customYieldGrams: customYield,
      retentionProtein: ret.$1,
      retentionFat: ret.$2,
      retentionCarbs: ret.$3,
      blankMode: mode,
      createdAt: DateTime.utc(2026, 10, 31),
      updatedAt: DateTime.utc(2026, 10, 31),
    );

Product nullableProduct(String name) => Product.fromJson(<String, dynamic>{
      'id': 1,
      'code': 'NULL',
      'name': name,
      'group_id': 1,
      'source': 'skurikhin',
      'waste_pct': 0.0,
      'measures': const <dynamic>[],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Продукты — настоящие строки `assets/db/reference.db` (только чтение).
  // Раньше тест читал выгрузку audit_artifacts/reaudit_fuzz/products.json,
  // которой нет в репозитории, и падал до первого свойства.
  late final List<RealProduct> realProducts;
  late final DishBreeder breeder;
  setUpAll(() async {
    final rows = await loadAllReferenceRows();
    realProducts = [
      for (final row in rows) realProductFromJson(Map<String, dynamic>.from(row)),
    ];
    breeder = DishBreeder(realProducts)..buildPools(Random(7));
  });
  final baseSeed = _baseSeed;

  final cache = <int, GenDish>{};
  GenDish dishAt(int i) => cache.putIfAbsent(baseSeed + i, () => breeder.breed(baseSeed + i));

  test('reaudit fuzz: properties', () {
    emit('# Adversarial property run (adversarial-fuzzer re-audit)');
    emit('base seed = $baseSeed; real products loaded = ${realProducts.length}; '
        'adversarial pool = ${breeder.adversarialPoolSize}');

    // ---------------------------------------------------------------- P1
    exec(register('P1', 'все выходы (массы, Б/Ж/У, ккал, на 100 г) >= 0', 300000, () {
      final c = Collector('P1');
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        final res = tryCalc(g.dish);
        if (res == null) continue;
        for (final e in _byName(res).entries) {
          // В Dart `0.0 == -0.0` — true, поэтому отрицательный ноль ищем по знаку
          // (раньше любой ноль, например «вес не указан» = 0, считался нарушением).
          if (e.value < 0 || (e.value == 0 && e.value.isNegative)) {
            c.add('seed=${g.seed} ${e.key}=${e.value}');
          }
        }
      }
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P2
    exec(register('P2', 'ни один выход не NaN и не ±Inf', 300000, () {
      final c = Collector('P2');
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        final res = tryCalc(g.dish);
        if (res == null) continue;
        for (final e in _byName(res).entries) {
          if (!e.value.isFinite) c.add('seed=${g.seed} ${e.key}=${e.value}');
        }
      }
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P3
    exec(register('P3', 'k>1 ⇒ cooked Б/Ж/У не убывают (k=1.0001…1000; блюдо и один ингредиент)',
        150000, () {
      final c = Collector('P3');
      for (var i = 0; i < _N(150000); i++) {
        final g = dishAt(i);
        final base = tryCalc(g.dish);
        if (base == null) continue;
        final k = kScaleFactors[i % kScaleFactors.length];
        final big = tryCalc(scaled(g.dish, k));
        if (big == null) continue;
        final pairs = [
          ('cookedProtein', base.cookedProtein, big.cookedProtein),
          ('cookedFat', base.cookedFat, big.cookedFat),
          ('cookedCarbs', base.cookedCarbs, big.cookedCarbs),
        ];
        for (final p in pairs) {
          if (p.$3 < p.$2) {
            c.add('seed=${g.seed} k=$k ${p.$1} ${p.$2} -> ${p.$3}');
          }
        }
        // single-ingredient monotonicity
        if (g.dish.ingredients.length == 1) {
          for (final p in pairs) {
            if (p.$3 < p.$2) c.add('single seed=${g.seed} k=$k ${p.$1} ${p.$2} -> ${p.$3}');
          }
        }
        // cold dishes: identity model — strict monotonicity for positive weights
        if (g.process == HeatProcess.cold &&
            g.dish.customYieldGrams == null &&
            (base.rawTotalProtein > 0 || base.rawTotalFat > 0 || base.rawTotalCarbs > 0)) {
          if (big.cookedProtein < base.cookedProtein &&
              big.cookedFat < base.cookedFat &&
              big.cookedCarbs < base.cookedCarbs &&
              (big.cookedProtein != base.cookedProtein ||
                  big.cookedFat != base.cookedFat ||
                  big.cookedCarbs != base.cookedCarbs)) {
            c.add('cold seed=${g.seed} k=$k all macros decreased: '
                '${base.cookedProtein}/${base.cookedFat}/${base.cookedCarbs} -> '
                '${big.cookedProtein}/${big.cookedFat}/${big.cookedCarbs}');
          }
        }
      }
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P4
    exec(register('P4', 'масштабирование: per100g(k·блюдо) = per100g(блюдо) в пределах округления; '
        'выход растёт с k', 150000, () {
      final c = Collector('P4');
      var maxDevKcal = 0.0;
      var maxDevP = 0.0;
      var maxDevF = 0.0;
      var maxDevC = 0.0;
      var yieldNotScaled = 0;
      var yieldNotScaledFirst = '';
      var yieldScaledCount = 0;
      var per100Deviation = 0;
      for (var i = 0; i < _N(150000); i++) {
        final g = dishAt(i);
        final base = tryCalc(g.dish);
        if (base == null || base.yieldGrams <= 0) continue;
        final k = kScaleFactors[i % kScaleFactors.length];
        final big = tryCalc(scaled(g.dish, k));
        if (big == null || big.yieldGrams <= 0) continue;
        if (g.dish.customYieldGrams != null) continue; // custom yield is a constant
        yieldScaledCount++;
        final dk = (big.per100gKcal - base.per100gKcal).abs();
        final dp = (big.per100gProtein - base.per100gProtein).abs();
        final df = (big.per100gFat - base.per100gFat).abs();
        final dc = (big.per100gCarbs - base.per100gCarbs).abs();
        if (dk > maxDevKcal) maxDevKcal = dk;
        if (dp > maxDevP) maxDevP = dp;
        if (df > maxDevF) maxDevF = df;
        if (dc > maxDevC) maxDevC = dc;
        // Ячейки округлены до 0,01 г построчно: на малом выходе ошибка
        // округления (n+1)·0,005 г даёт до (n+1)·0,5/выход г на 100 г в каждом
        // из двух блюд. Прежний абсолютный порог 0,01 этот шаг не учитывал
        // (пример: 0,01 г жира на 1 г → 1,00; ×1,5 → 0,02 на 1,5 г → 1,33).
        final rows = g.dish.ingredients.length + 1;
        final tolG = 0.01 + rows * 1.0 / base.yieldGrams;
        final tolK = 0.1 + rows * 17.0 / base.yieldGrams;
        if (dk > tolK || dp > tolG || df > tolG || dc > tolG) {
          per100Deviation++;
          c.add('seed=${g.seed} k=$k per100g(${base.per100gProtein},${base.per100gFat},'
              '${base.per100gCarbs},${base.per100gKcal}) vs (${big.per100gProtein},'
              '${big.per100gFat},${big.per100gCarbs},${big.per100gKcal})');
        }
        if (big.yieldGrams < base.yieldGrams) {
          c.add('yield decreased seed=${g.seed} k=$k ${base.yieldGrams} -> ${big.yieldGrams}');
        }
        if (big.yieldGrams == base.yieldGrams) {
          yieldNotScaled++;
          if (yieldNotScaledFirst.isEmpty) {
            yieldNotScaledFirst = 'seed=${g.seed} k=$k yield=${big.yieldGrams} rawNet=${big.rawTotalWeight}';
          }
        }
      }
      emit('   P4 stats: scaledCases=$yieldScaledCount maxDev[P,F,C,kcal]='
          '[$maxDevP, $maxDevF, $maxDevC, $maxDevKcal]; '
          'cases exceeding printed-rounding bound=$per100Deviation; '
          'yieldNotScaled=$yieldNotScaled first=$yieldNotScaledFirst');
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P5
    exec(register('P5', 'перестановка ингредиентов не меняет итоги (без округления суммы)', 200000, () {
      final c = Collector('P5');
      final r = Random(baseSeed + 5);
      var maxDiff = 0.0;
      String firstDiff = '';
      for (var i = 0; i < _N(200000); i++) {
        final g = dishAt(i);
        if (g.dish.ingredients.length < 2) continue;
        final base = tryCalc(g.dish);
        if (base == null) continue;
        final shuffled = g.dish.copyWith(ingredients: [...g.dish.ingredients]..shuffle(r));
        final other = tryCalc(shuffled);
        if (other == null) {
          c.add('seed=${g.seed} shuffle made dish invalid');
          continue;
        }
        final a = _byName(base), b = _byName(other);
        for (final k in a.keys) {
          final diff = (a[k]! - b[k]!).abs();
          if (diff > maxDiff) maxDiff = diff;
          if (diff != 0) {
            c.add('seed=${g.seed} ${k}: ${a[k]} vs ${b[k]}');
            if (firstDiff.isEmpty) firstDiff = 'seed=${g.seed} ${k} ${a[k]} vs ${b[k]}';
          }
        }
      }
      emit('   P5 stats: maxDiff=$maxDiff first=$firstDiff');
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P6
    exec(register('P6', 'save→load→save: Dish.toJson ∘ fromJson идемпотентен байт-в-байт '
        '(все blankMode × process, Unicode/эмодзи/500 симв.)', 300000, () {
      final c = Collector('P6');
      int sumDoubleBug = 0;
      String firstSumDouble = '';
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        final d0 = g.dish;
        final j1 = _jsonOf(d0);
        final loaded = Dish.fromJson(jsonDecode(j1) as Map<String, dynamic>);
        final j2 = _jsonOf(loaded);
        final loaded2 = Dish.fromJson(jsonDecode(j2) as Map<String, dynamic>);
        final j3 = _jsonOf(loaded2);
        if (j1 != j2 || j2 != j3) {
          c.add('seed=${g.seed} process=${g.process.name} mode=${g.mode.name} '
              'j1!=j2:${j1 != j2} j2!=j3:${j2 != j3}');
        }
        // ingredient-level toJson must survive too
        for (var k = 0; k < loaded.ingredients.length; k++) {
          final a = jsonEncode(d0.ingredients[k].toJson());
          final b = jsonEncode(loaded.ingredients[k].toJson());
          if (a != b) c.add('seed=${g.seed} ingredient[$k] json differs');
        }
        final isLegacy = g.process == HeatProcess.legacy;
        final jsonHasProcess = (jsonDecode(j1) as Map).containsKey('process');
        if (isLegacy == jsonHasProcess) {
          // legacy must omit `process`; non-legacy must write it
          final same = (jsonDecode(j1) as Map<String, dynamic>);
          final proc = same['process'];
          final parsedBack = Dish.fromJson(same);
          if (isLegacy ? proc != null : parsedBack.process.name != g.process.name) {
            c.add('seed=${g.seed} process round-trip broken (isLegacy=$isLegacy, json=$proc)');
          }
        }
      }
      if (sumDoubleBug > 0) c.add('sum-of-doubles override bug: $sumDoubleBug first=$firstSumDouble');
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P7
    exec(register('P7', 'вес готового блюда не угадывается: введённый вес — как есть; '
        'без него legacy → сумма нетто, остальные → 0 (на 100 г = 0)', 300000, () {
      final c = Collector('P7');
      var entered = 0;
      var legacyNet = 0;
      var noWeight = 0;
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        final d = g.dish;
        if (d.ingredients.isEmpty) continue;
        final res = tryCalc(d);
        if (res == null) continue;
        final custom = d.customYieldGrams;
        final hasCustom = custom != null &&
            custom.isFinite &&
            custom >= CalculationValidation.minCustomYieldGrams;
        if (hasCustom) {
          entered++;
          if ((res.yieldGrams - custom).abs() > 0.005) {
            c.add('seed=${g.seed} process=${g.process.name} entered=$custom '
                'yield=${res.yieldGrams}');
          }
        } else if (g.process == HeatProcess.legacy) {
          legacyNet++;
          if ((res.yieldGrams - res.rawTotalWeight).abs() > 0.005) {
            c.add('seed=${g.seed} legacy yield=${res.yieldGrams} '
                'rawNet=${res.rawTotalWeight}');
          }
        } else {
          noWeight++;
          if (res.yieldGrams != 0.0 ||
              res.hasYield ||
              res.per100gProtein != 0.0 ||
              res.per100gFat != 0.0 ||
              res.per100gCarbs != 0.0 ||
              res.per100gKcal != 0.0) {
            c.add('seed=${g.seed} process=${g.process.name} weight guessed: '
                'yield=${res.yieldGrams} per100kcal=${res.per100gKcal}');
          }
        }
      }
      emit('   P7 stats: entered=$entered legacyNet=$legacyNet noWeight=$noWeight');
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P8
    exec(register('P8', 'сухое вещество не растёт при уварке: cooked Б/Ж/У ≤ raw Б/Ж/У '
        '(не-legacy)', 300000, () {
      final c = Collector('P8');
      final increasedByProcess = <String, int>{};
      final singleRowCounter = <String, int>{};
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        if (g.process == HeatProcess.legacy) continue;
        final res = tryCalc(g.dish);
        if (res == null) continue;
        for (final p in [
          ('P', res.rawTotalProtein, res.cookedProtein),
          ('F', res.rawTotalFat, res.cookedFat),
          ('C', res.rawTotalCarbs, res.cookedCarbs),
        ]) {
          if (p.$3 > p.$2 + 1e-9) {
            increasedByProcess.update('${g.process.name}/${p.$1}', (v) => v + 1,
                ifAbsent: () => 1);
            c.add('seed=${g.seed} process=${g.process.name} ${p.$1}: raw=${p.$2} cooked=${p.$3}');
          }
        }
        // Whole-dish retention can hide a row-level increase: compare a
        // synthetic single-row dish over each admissibly "other" class.
        for (final ing in g.dish.ingredients) {
          final cls = _classify(ing.product);
          final dish1 = g.dish.copyWith(ingredients: [ing]);
          final r1 = tryCalc(dish1);
          if (r1 == null) continue;
          if (r1.cookedProtein > r1.rawTotalProtein + 1e-9 ||
              r1.cookedFat > r1.rawTotalFat + 1e-9 ||
              r1.cookedCarbs > r1.rawTotalCarbs + 1e-9) {
            if (r1.rawTotalProtein + r1.rawTotalFat + r1.rawTotalCarbs > 0) {
              singleRowCounter.update('${cls.name}/${g.process.name}', (v) => v + 1,
                  ifAbsent: () => 1);
              if (singleRowCounter['${cls.name}/${g.process.name}'] == 1) {
                c.add('singleRow seed=${g.seed} class=${cls.name} process=${g.process.name} '
                    'raw=${r1.rawTotalProtein}/${r1.rawTotalFat}/${r1.rawTotalCarbs} '
                    'cooked=${r1.cookedProtein}/${r1.cookedFat}/${r1.cookedCarbs}');
              }
            }
          }
        }
      }
      emit('   P8 stats: dish-level increases by process/macro = $increasedByProcess');
      emit('   P8 stats: single-row increases by class/process = $singleRowCounter');
      return c.toViolation();
    }));

    // ---------------------------------------------------------------- P9
    exec(register('P9', 'cold: cooked == raw (потерь нет); тройка сохранности '
        'блюда в не-legacy расчёте не участвует', 300000, () {
      final c = Collector('P9');
      var coldOk = 0;
      var customTriple = 0;
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        if (g.process != HeatProcess.cold) continue;
        final res = tryCalc(g.dish);
        if (res == null) continue;
        final isDefault = g.dish.retentionProtein == 1.0 &&
            g.dish.retentionFat == 1.0 &&
            g.dish.retentionCarbs == 1.0;
        if (!isDefault) customTriple++;
        final equal = res.cookedProtein == res.rawTotalProtein &&
            res.cookedFat == res.rawTotalFat &&
            res.cookedCarbs == res.rawTotalCarbs;
        if (equal) {
          coldOk++;
        } else {
          c.add('seed=${g.seed} cold retention=(${g.dish.retentionProtein},'
              '${g.dish.retentionFat},${g.dish.retentionCarbs}) raw=${res.rawTotalProtein}/'
              '${res.rawTotalFat}/${res.rawTotalCarbs} cooked=${res.cookedProtein}/'
              '${res.cookedFat}/${res.cookedCarbs}');
        }
      }
      emit('   P9 stats: coldOk=$coldOk coldWithCustomTriple=$customTriple');
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P10
    exec(register('P10', 'legacy: cooked = HALF-UP(rawTotal × retention/100), проверено '
        'независимой BigInt-арифметикой', 300000, () {
      final c = Collector('P10');
      for (var i = 0; i < _N(300000); i++) {
        final g = dishAt(i);
        if (g.process != HeatProcess.legacy) continue;
        final res = tryCalc(g.dish);
        if (res == null) continue;
        // Тройка хранится долями (0,94); движок (как и HEAD 658d3ff) сначала
        // переводит её в проценты HALF-UP до 10 знаков, затем raw × % / 100.
        double expOf(double raw, double ret) => indepProductRound(
            raw, indepProductRound(ret, 100, 10), 2,
            divideBy100: true);
        final expP = expOf(res.rawTotalProtein, g.dish.retentionProtein);
        final expF = expOf(res.rawTotalFat, g.dish.retentionFat);
        final expC = expOf(res.rawTotalCarbs, g.dish.retentionCarbs);
        if (expP != res.cookedProtein || expF != res.cookedFat || expC != res.cookedCarbs) {
          c.add('seed=${g.seed} expected=$expP/$expF/$expC got=${res.cookedProtein}/'
              '${res.cookedFat}/${res.cookedCarbs} raw=${res.rawTotalProtein}/'
              '${res.rawTotalFat}/${res.rawTotalCarbs} ret=(${g.dish.retentionProtein},'
              '${g.dish.retentionFat},${g.dish.retentionCarbs})');
        }
        final expKcal = indepProductRound(
            4 * expP + 9 * expF + 4 * expC, 1.0, 1);
        if (expKcal != res.cookedKcal && _energy(expP, expF, expC) != res.cookedKcal) {
          c.add('seed=${g.seed} kcal expected=${_energy(expP, expF, expC)} got=${res.cookedKcal}');
        }
      }
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P11
    exec(register('P11', 'детерминизм: 1000 повторов → бит-идентичный результат; '
        'вход (Dish/Product) не мутируется', 1000, () {
      final c = Collector('P11');
      final r = Random(baseSeed + 11);
      for (var i = 0; i < _N(1000); i++) {
        final g = dishAt(i * 37);
        final before = _jsonOf(g.dish);
        final first = tryCalc(g.dish);
        final firstJson = first == null ? 'ERR' : _byName(first).toString();
        for (var rep = 0; rep < 3; rep++) {
          final again = tryCalc(g.dish);
          final againJson = again == null ? 'ERR' : _byName(again).toString();
          if (againJson != firstJson) {
            c.add('seed=${g.seed} repeat=$rep differs: $firstJson vs $againJson');
          }
        }
        final after = _jsonOf(g.dish);
        if (before != after) c.add('MUTATED seed=${g.seed}');
        // Product not mutated
        for (var k = 0; k < g.dish.ingredients.length; k++) {
          final pj = jsonEncode(g.dish.ingredients[k].product.toJson());
          tryCalc(g.dish);
          if (pj != jsonEncode(g.dish.ingredients[k].product.toJson())) {
            c.add('PRODUCT MUTATED seed=${g.seed} i=$k');
          }
        }
        // random extra reads to exercise caches
        r.nextInt(1);
      }
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P12
    exec(register('P12', 'ассоциативность/группировка: sumRounded не зависит от разбиения '
        'на группы; итог = HALF-UP(точная сумма)', 100000, () {
      final c = Collector('P12');
      final r = Random(baseSeed + 12);
      for (var i = 0; i < _N(100000); i++) {
        final g = dishAt(i);
        final vals = [for (final ing in g.dish.ingredients) ing.netGramsRounded];
        if (vals.isEmpty) continue;
        final whole = CalculationMath.sumRounded(vals, 1);
        final expectWhole = indepSum(vals, 1);
        if (whole != expectWhole) c.add('seed=${g.seed} sumRounded=${whole} exact=${expectWhole}');
        // grouping: split in 2..4 chunks, sum each, then sum the chunk sums
        final shuffled = [...vals]..shuffle(r);
        for (var groups = 2; groups <= 4 && shuffled.length >= groups; groups++) {
          final chunks = <double>[];
          final size = (shuffled.length / groups).ceil();
          for (var s = 0; s < shuffled.length; s += size) {
            final end = min(s + size, shuffled.length);
            chunks.add(CalculationMath.sumRounded(shuffled.sublist(s, end), 1));
          }
          final regrouped = CalculationMath.sumRounded(chunks, 1);
          if (regrouped != whole) {
            c.add('seed=${g.seed} groups=$groups whole=$whole regrouped=$regrouped');
          }
        }
        // reassociation of exact sums in fitting window: |sum| small -> identical
        if (whole.abs() < 1e6) {
          var acc1 = 0.0;
          for (final v in shuffled) {
            acc1 += v;
          }
          var acc2 = 0.0;
          for (final v in shuffled.reversed) {
            acc2 += v;
          }
          if (indepRound(acc1, 1) != indepRound(acc2, 1)) {
            c.add('seed=${g.seed} float reassociation: $acc1 vs $acc2');
          }
        }
      }
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P13
    exec(register('P13', 'пустое блюдо: выход 0, на 100 г = 0 (не NaN), без исключения', 100000, () {
      final c = Collector('P13');
      var n = 0;
      for (var i = 0; i < _N(100000); i++) {
        final g = dishAt(i);
        final proc = HeatProcess.values[i % HeatProcess.values.length];
        final mode = BlankMode.values[(i ~/ 7) % BlankMode.values.length];
        for (final custom in [null, 1.0, 9999999.0]) {
          final dish = dishOf([], process: proc, mode: mode, customYield: custom, id: 'empty$i');
          n++;
          try {
            final res = CalculationEngine.calculate(dish);
            if (custom == null) {
              if (res.yieldGrams != 0) c.add('seed=${g.seed} proc=${proc.name} yield=${res.yieldGrams}');
            }
            for (final e in _byName(res).entries) {
              if (!e.value.isFinite) c.add('seed=${g.seed} ${e.key}=${e.value}');
              if (e.value != 0 && !(custom != null && (e.key == 'yieldGrams'))) {
                c.add('seed=${g.seed} custom=$custom proc=${proc.name} ${e.key}=${e.value}');
              }
            }
            // Контракт движка (и HEAD 658d3ff): столбец «ккал сырья» есть
            // только в подробном бланке — у пустого блюда он равен 0, в фото-бланке
            // его нет (null).
            if (mode == BlankMode.detailed
                ? res.rawTotalKcal != 0.0
                : res.rawTotalKcal != null) {
              c.add('seed=${g.seed} mode=${mode.name} rawTotalKcal=${res.rawTotalKcal} on empty');
            }
          } catch (e) {
            c.add('seed=${g.seed} proc=${proc.name} custom=$custom threw ${e.runtimeType}: $e');
          }
        }
      }
      emit('   P13 cases counted=$n');
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P14
    final p14Typed = <String, int>{};
    exec(register('P14', 'любой невалидный вход → типизированное исключение '
        '(ArgumentError/FormatException/RangeError/StateError), не TypeError/NoSuchMethod/'
        'StackOverflow', 120000, () {
      final c = Collector('P14');
      String classify(Object e) {
        if (e is ArgumentError) return 'ArgumentError';
        if (e is FormatException) return 'FormatException';
        if (e is RangeError) return 'RangeError';
        if (e is StateError) return 'StateError';
        if (e is TypeError) return 'TypeError';
        if (e is NoSuchMethodError) return 'NoSuchMethodError';
        if (e is StackOverflowError) return 'StackOverflowError';
        return e.runtimeType.toString();
      }

      void probe(String cls, Dish d) {
        try {
          CalculationEngine.calculate(d);
          p14Typed.update('$cls:ACCEPTED', (v) => v + 1, ifAbsent: () => 1);
        } catch (e) {
          final k = classify(e);
          p14Typed.update('$cls:$k', (v) => v + 1, ifAbsent: () => 1);
          if (!(e is ArgumentError || e is FormatException || e is RangeError || e is StateError)) {
            c.add('$cls -> untyped $k: $e');
          }
        }
      }

      Product withField(String name, Map<String, Object?> patch) {
        final j = <String, dynamic>{
          'id': 1, 'code': 'X', 'name': name, 'group_id': 1, 'source': 'skurikhin',
          'waste_pct': 0.0, 'protein': 10.0, 'fat': 5.0, 'carbs': 20.0, 'kcal': 165.0,
          'measures': const <dynamic>[],
        };
        j.addAll(patch);
        return Product.fromJson(j);
      }

      final base = nullableProduct('курица');
      final builders = <String, void Function()>{
        'retention>1': () => probe('retention>1', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], ret: (1.5, 1, 1))),
        'retention=0': () => probe('retention=0', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], ret: (0, 1, 1))),
        'retention=NaN': () => probe('retention=NaN', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], ret: (double.nan, 1, 1))),
        'retention=inf': () => probe('retention=inf', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], ret: (double.infinity, 1, 1))),
        'weight<0': () => probe('weight<0', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: -1)])),
        'weight=NaN': () => probe('weight=NaN', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: double.nan)])),
        'weight=inf': () => probe('weight=inf', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: double.infinity)])),
        'weight>max': () => probe('weight>max', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 1e7)])),
        'customYield<1': () => probe('customYield<1', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: 0.5)),
        'customYield<0.1': () => probe('customYield<0.1', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: 0.05)),
        'customYield=0': () => probe('customYield=0', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: 0.0)),
        'customYield>max': () => probe('customYield>max', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: 1e7)),
        'customYield=inf': () => probe('customYield=inf', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: double.infinity)),
        'customYield=NaN': () => probe('customYield=NaN', dishOf(
            [Ingredient(id: 'a', product: base, weightGrams: 100)], customYield: double.nan)),
        'waste=99.999': () => probe('waste=99.999 ok', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'waste_pct': 99.999}), weightGrams: 100, isGross: true)])),
        'waste=100': () => probe('waste=100', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'waste_pct': 100.0}), weightGrams: 100, isGross: true)])),
        'waste>100': () => probe('waste>100', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'waste_pct': 150.0}), weightGrams: 100, isGross: true)])),
        'waste<0': () => probe('waste<0', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'waste_pct': -1.0}), weightGrams: 100, isGross: true)])),
        'waste=NaN': () => probe('waste=NaN', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'waste_pct': double.nan}), weightGrams: 100, isGross: true)])),
        'P>100': () => probe('P>100', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': 101.0}), weightGrams: 100)])),
        'P<0': () => probe('P<0', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': -1.0}), weightGrams: 100)])),
        'P+F+C>100': () => probe('P+F+C>100', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': 40.0, 'fat': 40.0, 'carbs': 40.0}), weightGrams: 100)])),
        'P=NaN (explicit)': () => probe('P=NaN', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': double.nan}), weightGrams: 100)])),
        'P=inf': () => probe('P=inf', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': double.infinity}), weightGrams: 100)])),
        'protein missing': () => probe('protein missing', dishOf(
            [Ingredient(id: 'a', product: nullableProduct('курица'), weightGrams: 100)])),
        'kcal=NaN': () => probe('kcal=NaN', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'kcal': double.nan}), weightGrams: 100)])),
        'kcal=inf': () => probe('kcal=inf', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'kcal': double.infinity}), weightGrams: 100)])),
        'kcal=-1': () => probe('kcal=-1', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'kcal': -1.0}), weightGrams: 100)])),
        'calories-inconsistent': () => probe('kcal-policy', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'protein': 0.0, 'fat': 0.0, 'carbs': 0.0, 'kcal': 900.0}), weightGrams: 100)])),
        'water=NaN (no kcal)': () => probe('water=NaN', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'water': double.nan, 'kcal': null}), weightGrams: 100)],
            process: HeatProcess.boil)),
        'fiber=NaN (no kcal)': () => probe('fiber=NaN', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'fiber': double.nan, 'kcal': null}), weightGrams: 100)],
            process: HeatProcess.boil)),
        'water=-5': () => probe('water<0', dishOf(
            [Ingredient(id: 'a', product: withField('курица', {'water': -5.0, 'kcal': null}), weightGrams: 100)])),
        'names weird': () => probe('names', dishOf([
            for (var i = 0; i < kAdversarialNames.length; i++)
              Ingredient(id: 'n$i', product: withField(kAdversarialNames[i], {}), weightGrams: 33)
        ])),
        'iso/water mix': () => probe('water+cold', dishOf([
          Ingredient(id: 'w', product: withField('Вода питьевая', {}), weightGrams: 400),
          Ingredient(id: 'b', product: withField('Телячья грудинка в бульоне, варёная',
              {'protein': 23.657, 'fat': 15.214, 'carbs': 0.0}), weightGrams: 100),
        ], process: HeatProcess.stock)),
      };
      builders.forEach((k, f) => f());

      // Fuzz the same pathologies over random generated dishes.
      final r = Random(baseSeed + 14);
      final pathological = <Product Function()>[
        () => productFromReal(realProducts[r.nextInt(realProducts.length)]),
        () => nullableProduct('курица'),
        () => withField('курица', {'protein': 100.0, 'fat': 0.0, 'carbs': 0.0}),
        () => withField('гречка', {'protein': 0.0, 'fat': 100.0, 'carbs': 0.0}),
        () => withField('вода', {'protein': 0.0, 'fat': 0.0, 'carbs': 0.0, 'kcal': 0.0}),
      ];
      final badWeights = [-1.0, double.nan, double.infinity, -0.0, 1e7, 9999999.0];
      for (var i = 0; i < _N(120000); i++) {
        final n = r.nextInt(4);
        final ings = <Ingredient>[];
        for (var k = 0; k < n; k++) {
          final w = r.nextInt(5) == 0 ? badWeights[r.nextInt(badWeights.length)] : kWeights[r.nextInt(kWeights.length)];
          ings.add(Ingredient(id: 'q$k', product: pathological[r.nextInt(pathological.length)](),
              weightGrams: w, isGross: r.nextBool()));
        }
        final ret = r.nextInt(6) == 0 ? (0.0, 0.0, 0.0) : kRetentionTriples[r.nextInt(kRetentionTriples.length)];
        final cy = r.nextInt(5) == 0
            ? [10.0, -1.0, double.nan, double.infinity, 0.0][r.nextInt(5)]
            : kCustomYields[r.nextInt(kCustomYields.length)];
        final d = dishOf(ings,
            process: HeatProcess.values[r.nextInt(HeatProcess.values.length)],
            customYield: cy,
            ret: ret,
            mode: BlankMode.values[r.nextInt(BlankMode.values.length)]);
        try {
          CalculationEngine.calculate(d);
          p14Typed.update('fuzz:ACCEPTED', (v) => v + 1, ifAbsent: () => 1);
        } catch (e) {
          final k = classify(e);
          p14Typed.update('fuzz:$k', (v) => v + 1, ifAbsent: () => 1);
          if (!(e is ArgumentError || e is FormatException || e is RangeError || e is StateError)) {
            c.add('fuzz -> untyped $k: $e');
          }
        }
        // tryCalculate must never throw
        CalculationEngine.tryCalculate(d);
        // non-finite results only for inputs we admitted as valid
      }
      emit('   P14 taxonomy: $p14Typed');
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P15
    exec(register('P15', 'portion(): portion(выход)=блюдо целиком, монотонно по граммам, '
        'per100g×выход/100 ≈ cooked', 200000, () {
      final c = Collector('P15');
      final r = Random(baseSeed + 15);
      var maxPortionDev = 0.0;
      var maxPer100Dev = 0.0;
      var portionMono = 0;
      for (var i = 0; i < _N(200000); i++) {
        final g = dishAt(i);
        final res = tryCalc(g.dish);
        if (res == null || res.yieldGrams <= 0) continue;
        final whole = res.portion(res.yieldGrams);
        if (whole.protein != res.cookedProtein ||
            whole.fat != res.cookedFat ||
            whole.carbs != res.cookedCarbs ||
            whole.kcal != res.cookedKcal) {
          c.add('seed=${g.seed} portion(yield) != dish: ${whole.protein}/'
              '${whole.fat}/${whole.carbs} vs ${res.cookedProtein}/${res.cookedFat}/${res.cookedCarbs}');
        }
        var prevProtein = -1.0;
        var prevFat = -1.0;
        var prevCarbs = -1.0;
        var prevKcal = -1.0;
        // Серия проверяется на ВОЗРАСТАЮЩИХ x (раньше x были случайными
        // и неупорядоченными — «немонотонность» была артефактом теста).
        final xs = [for (var s = 0; s < 3; s++) 0.1 + r.nextDouble() * 9999]
          ..sort();
        for (final x in xs) {
          final a = res.portion(x);
          final b = res.portion(x + 0.01);
          if (b.protein < a.protein || b.fat < a.fat || b.carbs < a.carbs || b.kcal < a.kcal) {
            portionMono++;
            c.add('seed=${g.seed} portion not monotone at x=$x');
          }
          if (a.protein < prevProtein || a.fat < prevFat || a.carbs < prevCarbs || a.kcal < prevKcal) {
            portionMono++;
            c.add('seed=${g.seed} portion(x) series not monotone in x at x=$x');
          }
          prevProtein = a.protein;
          prevFat = a.fat;
          prevCarbs = a.carbs;
          prevKcal = a.kcal;
          final dev = (indepRatio(res.cookedProtein, res.yieldGrams, 2) - res.per100gProtein).abs();
          if (dev > maxPer100Dev) maxPer100Dev = dev;
          final expectP = indepRatio(res.cookedProtein, res.yieldGrams, 2, multiplier: x);
          if ((a.protein - expectP).abs() > 0.01 + 0.01 * x / 100) {
            c.add('seed=${g.seed} portion(x=$x) protein=${a.protein} expected≈$expectP');
          }
        }
        // per100 g × yield/100 ≈ cooked within rounding of the printed value
        // Допуск — ошибка округления печатного значения на 100 г, умноженная
        // на yield/100: Б/Ж/У на 100 г округлены до 0,01 (ошибка ≤ 0,005),
        // ккал на 100 г — до 0,1 от округлённых Б/Ж/У (≤ 0,05 + 17 × 0,005).
        // Плюс округление самих итогов (0,01 / 0,1). При весе 9 999 999 г
        // прежний общий допуск 0,01 × yield/100 был меньше ошибки ккал.
        for (final m in [
          (res.per100gProtein, res.cookedProtein, false),
          (res.per100gFat, res.cookedFat, false),
          (res.per100gCarbs, res.cookedCarbs, false),
          (res.per100gKcal, res.cookedKcal, true),
        ]) {
          final recon = m.$1 * res.yieldGrams / 100;
          final dv = (recon - m.$2).abs();
          if (dv > maxPortionDev) maxPortionDev = dv;
          final bound = m.$3
              ? 0.06 + 0.14 * res.yieldGrams / 100
              : 0.0151 + 0.01 * res.yieldGrams / 100;
          if (dv > bound) {
            c.add('seed=${g.seed} per100×yield/100=${recon} vs cooked=${m.$2} '
                '(yield=${res.yieldGrams})');
          }
        }
      }
      // Negative / zero portion handling
      try {
        final res = CalculationEngine.calculate(dishOf([
          Ingredient(id: 'a', product: syntheticProduct(name: 'курица'), weightGrams: 200),
        ]));
        for (final v in [0.0, -1.0, 0.05, double.nan]) {
          try {
            res.portion(v);
            c.add('portion($v) accepted');
          } catch (e) {
            final k = e.runtimeType.toString();
            p14Typed.update('portion($v):$k', (v2) => v2 + 1, ifAbsent: () => 1);
            if (!(e is ArgumentError || e is RangeError || e is StateError)) {
              c.add('portion($v) untyped $k');
            }
          }
        }
      } on ArgumentError {
        //
      }
      emit('   P15 stats: maxPer100Dev=$maxPer100Dev maxPortionDev=$maxPortionDev mono=$portionMono');
      return c.toViolation();
    }));

    // --------------------------------------------------------------- P16
    exec(register('P16', 'JSON-устойчивость: мутированный JSON либо грузится, либо бросает '
        'типизированно; загруженное блюдо не даёт NaN', 130000, () {
      final c = Collector('P16');
      final r = Random(baseSeed + 16);
      final fuzzCounts = <String, int>{};

      String classify(Object e) {
        if (e is ArgumentError) return 'ArgumentError';
        if (e is FormatException) return 'FormatException';
        if (e is RangeError) return 'RangeError';
        if (e is StateError) return 'StateError';
        if (e is TypeError) return 'TypeError';
        if (e is NoSuchMethodError) return 'NoSuchMethodError';
        if (e is StackOverflowError) return 'StackOverflowError';
        if (e is Error) return 'OTHER_Error:${e.runtimeType}';
        return 'NON_ERROR:${e.runtimeType}';
      }

      void probe(String cls, Object? raw) {
        Dish? dish;
        try {
          if (raw is! Map<String, dynamic>) throw const FormatException('not a map');
          dish = Dish.fromJson(raw);
        } catch (e) {
          final k = classify(e);
          fuzzCounts.update('$cls:$k', (v) => v + 1, ifAbsent: () => 1);
          // TypeError из Dish.fromJson — тоже типизированный исход: хранилище
          // (`DishStorageRepository`, `on TypeError`) считает такой документ
          // повреждённым и берёт резервную копию. Тихий мусор (загрузилось и
          // дало NaN) ловится ниже.
          if (!(e is ArgumentError ||
              e is FormatException ||
              e is RangeError ||
              e is StateError ||
              e is TypeError)) {
            c.add('$cls -> untyped $k: $e');
          }
          return;
        }
        try {
          final res = CalculationEngine.calculate(dish);
          for (final e in _byName(res).entries) {
            if (!e.value.isFinite) c.add('$cls loaded then NaN/Inf ${e.key}=${e.value}');
          }
          fuzzCounts.update('$cls:CALCULATED', (v) => v + 1, ifAbsent: () => 1);
          // save→load→save on the loaded object
          final j = jsonEncode(dish.toJson());
          final again = Dish.fromJson(jsonDecode(j) as Map<String, dynamic>);
          if (jsonEncode(again.toJson()) != j) c.add('$cls not idempotent after load');
        } on ArgumentError {
          fuzzCounts.update('$cls:CALC_THREW_ArgumentError', (v) => v + 1, ifAbsent: () => 1);
        } on FormatException {
          fuzzCounts.update('$cls:CALC_THREW_FormatException', (v) => v + 1, ifAbsent: () => 1);
        } on TypeError {
          c.add('$cls calculate() -> TypeError (untyped)');
        } on NoSuchMethodError {
          c.add('$cls calculate() -> NoSuchMethodError (untyped)');
        } on StateError {
          fuzzCounts.update('$cls:CALC_THREW_StateError', (v) => v + 1, ifAbsent: () => 1);
        } on StackOverflowError {
          c.add('$cls calculate() -> StackOverflowError (untyped)');
        } on OutOfMemoryError {
          c.add('$cls calculate() -> OutOfMemoryError (untyped)');
        } on Exception catch (e) {
          fuzzCounts.update('$cls:CALC_THREW_Exception:${e.runtimeType}',
              (v) => v + 1, ifAbsent: () => 1);
        }
      }

      // Fixture dish with real content
      final gen = dishAt(17);
      final fixture = <String, dynamic>{
        ...jsonDecode(jsonEncode(gen.dish.copyWith(
                id: 'fx', process: HeatProcess.boil, customYieldGrams: null).toJson()))
            as Map<String, dynamic>,
      };
      // make it always valid (fresh non-empty ingredients, sane retention)
      fixture['retentionProtein'] = 0.935;
      fixture['retentionFat'] = 0.917;
      fixture['retentionCarbs'] = 0.918;
      fixture['customYieldGrams'] = null;
      final prod = <String, dynamic>{
        'id': 1, 'code': 'C', 'name': 'курица', 'group_id': 1, 'source': 'skurikhin',
        'waste_pct': 0.0, 'protein': 10.0, 'fat': 5.0, 'carbs': 20.0, 'kcal': 165.0,
        'measures': const <dynamic>[],
      };
      fixture['ingredients'] = [
        {'id': 'a', 'product': prod, 'weightGrams': 100.0, 'isGross': false},
        {'id': 'b', 'product': {...prod, 'name': 'гречка'}, 'weightGrams': 60.0, 'isGross': false},
      ];

      final mutations = <String, Object? Function(Map<String, dynamic>)>{
        'as-is': (m) => m,
        'missing id': (m) => {...m}..remove('id'),
        'missing ingredients': (m) => {...m}..remove('ingredients'),
        'missing all': (m) => <String, dynamic>{},
        'title null': (m) => {...m, 'title': null},
        'title wrong type': (m) => {...m, 'title': 42},
        'id wrong type': (m) => {...m, 'id': 42},
        'id empty': (m) => {...m, 'id': ''},
        'blankMode wrong': (m) => {...m, 'blankMode': 'nope'},
        'blankMode null': (m) => {...m, 'blankMode': null},
        'process wrong': (m) => {...m, 'process': 'nope'},
        'process null': (m) => {...m, 'process': null},
        'process wrong type': (m) => {...m, 'process': 7},
        'retention NaN via string': (m) => {...m, 'retentionProtein': '0.9'},
        'retention huge': (m) => {...m, 'retentionProtein': 1e308},
        'retention negative': (m) => {...m, 'retentionProtein': -1e308},
        'retention null': (m) => {...m, 'retentionProtein': null},
        'retention 1e308 all': (m) => {...m, 'retentionProtein': 1e308, 'retentionFat': 1e308, 'retentionCarbs': 1e308},
        'customYield huge': (m) => {...m, 'customYieldGrams': 1e308},
        'customYield negative': (m) => {...m, 'customYieldGrams': -1e308},
        'customYield string': (m) => {...m, 'customYieldGrams': '100'},
        'customYield null': (m) => {...m, 'customYieldGrams': null},
        'customYield bool': (m) => {...m, 'customYieldGrams': true},
        'ingredients null': (m) => {...m, 'ingredients': null},
        'ingredients wrong type': (m) => {...m, 'ingredients': 'nope'},
        'ingredients ints': (m) => {...m, 'ingredients': [1, 2, 3]},
        'ingredients 10k nulls': (m) => {...m, 'ingredients': List<Object?>.filled(10000, null)},
        'ingredients 10k copies (dup ids)': (m) => {
              ...m,
              'ingredients': List<Object?>.filled(10000, (m['ingredients'] as List)[0]),
            },
        'weight string': (m) => {
              ...m,
              'ingredients': [
                {
                  'id': 'a',
                  'product': prod,
                  'weightGrams': '100',
                  'isGross': false,
                }
              ]
            },
        'weight 1e308': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'product': prod, 'weightGrams': 1e308, 'isGross': false}
              ]
            },
        'weight -1': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'product': prod, 'weightGrams': -1.0, 'isGross': false}
              ]
            },
        'weight null': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'product': prod, 'weightGrams': null, 'isGross': false}
              ]
            },
        'isGross string': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'product': prod, 'weightGrams': 100.0, 'isGross': 'false'}
              ]
            },
        'product missing': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'weightGrams': 100.0}
              ]
            },
        'product deep nested injection': (m) => {
              ...m,
              'ingredients': [
                {
                  'id': 'a',
                  'weightGrams': 100.0,
                  'product': {
                    ...prod,
                    'nested': {
                      'a': {'b': [1, 2, 3]},
                      '__proto__': {'x': 1},
                    }
                  }
                }
              ]
            },
        'product protein 1e308': (m) => {
              ...m,
              'ingredients': [
                {'id': 'a', 'weightGrams': 100.0, 'product': {...prod, 'protein': 1e308}}
              ]
            },
        'product nutrient nulls': (m) => {
              ...m,
              'ingredients': [
                {
                  'id': 'a',
                  'weightGrams': 100.0,
                  'product': {
                    ...prod,
                    'protein': null,
                    'fat': null,
                    'carbs': null,
                    'kcal': null,
                  }
                }
              ]
            },
        'product 10k measures': (m) => {
              ...m,
              'ingredients': [
                {
                  'id': 'a',
                  'weightGrams': 100.0,
                  'product': {
                    ...prod,
                    'measures': List<Object?>.filled(10000, {'id': 1, 'grams': 5.0}),
                  }
                }
              ]
            },
        'createdAt garbage': (m) => {...m, 'createdAt': 'not-a-date'},
        'createdAt 1e308': (m) => {...m, 'createdAt': 1e308},
        'createdAt null': (m) => {...m, 'createdAt': null},
        'updatedAt array': (m) => {...m, 'updatedAt': []},
        'unknown keys': (m) => {...m, 'zzz': {'__proto__': 1}},
      };
      final counts = <String, int>{};
      for (var cycle = 0; cycle < _N(3000); cycle++) {
        final base = <String, dynamic>{
          ...fixture,
          if (cycle % 3 == 1) 'process': HeatProcess.values[cycle % HeatProcess.values.length].name,
          if (cycle % 7 == 2) 'blankMode': BlankMode.values[cycle % 2].name,
        };
        final mname = mutations.keys.elementAt(cycle % mutations.length);
        final mutated = mutations[mname]!(Map<String, dynamic>.from(base));
        counts[mname] = (counts[mname] ?? 0) + 1;
        probe(mname, mutated);
        // also JSON round-trip through text (to catch unencodable values)
        try {
          final text = jsonEncode(mutated);
          probe('$mname[viaText]', jsonDecode(text));
        } on JsonUnsupportedObjectError catch (e) {
          c.add('$mname: input unencodable $e');
        } on ArgumentError {
          //
        }
      }
      // Random structural mutations of generated dishes
      for (var i = 0; i < _N(100000); i++) {
        final g = dishAt(50 + i);
        final m = Map<String, dynamic>.from(g.dish.toJson());
        final op = r.nextInt(6);
        final keys = m.keys.toList();
        switch (op) {
          case 0:
            m.remove(keys[r.nextInt(keys.length)]);
          case 1:
            m[keys[r.nextInt(keys.length)]] = null;
          case 2:
            m[keys[r.nextInt(keys.length)]] = [1e308, -1e308, 'x'];
          case 3:
            m[keys[r.nextInt(keys.length)]] = 1e308;
          case 4:
            {
              final ings = m['ingredients'];
              if (ings is List && ings.isNotEmpty) {
                final k = r.nextInt(ings.length);
                final inj = Map<String, dynamic>.from(ings[k] as Map);
                inj['weightGrams'] = [0.0, -1.0, 1e308, double.infinity, double.nan, '100']
                    [r.nextInt(6)];
                ings[k] = inj;
              }
            }
          case _:
            m['process'] = ['cold', 'soup', 'grain', 'stock', 'legacy', 'nope'][r.nextInt(6)];
        }
        probe('randomMut$op', m);
      }
      fuzzCounts.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
      final summary = (counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      emit('   P16 taxonomy: $summary');
      return c.toViolation();
    }));

    // ---------------------------------------------------------- summary
    var total = 0;
    for (final l in _logs) {
      total += l.cases;
    }
    emit('# TOTAL cases = $total; properties = ${_logs.length}');
    final failed = _logs.where((l) => !l.passed).map((l) => l.id).toList();
    emit('# FAILED: ${failed.isEmpty ? "none" : failed.join(", ")}');

    // Machine-readable status for the report writer.
    final summary = File('${Directory.systemTemp.path}/povar_reaudit/fuzz/status.txt');
    summary.parent.createSync(recursive: true);
    summary.writeAsStringSync(
        'total=$total;failed=${failed.join(",")};'
        '${_logs.map((l) => '${l.id}:${l.passed ? "PASS" : "FAIL"}:${l.cases}').join(";")}\n');

    // Hard gate: the run passes only if every property passed. (This file is
    // meant to be read together with the report; expect() states the verdict.)
    expect(failed, isEmpty, reason: 'failed properties: $failed');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// Энергия от итогов Б/Ж/У (каждый уже округлён до 0,01): точная сумма в
/// сотых долях (BigInt, общий масштаб 2), затем HALF-UP до 0,1. Прежняя версия
/// брала мантиссу decOfDouble без учёта её собственного масштаба (×100 ошибка).
double _energy(double p, double f, double c) {
  BigInt cents(double x) => BigInt.from((x * 100).round());
  final sum = cents(p) * BigInt.from(4) + cents(f) * BigInt.from(9) + cents(c) * BigInt.from(4);
  return _toDouble(halfUpRounded(sum, 2, 1), 1);
}

/// Группа таблицы потерь — тем же классификатором, что и приложение
/// (собственная копия удалённого `classifyProduct` больше не нужна).
LossGroup _classify(Product product) => FoodClassifier.classify(product);

