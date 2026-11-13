// AUDIT DRIVER (read-only w.r.t. production code).
//
// Встроенные кейсы выполняются всегда и проверяются по ожиданиям. Если
// аудитор положил %TEMP%\povar_reaudit\formula\cases.json, кейсы из него
// тоже выполняются, а ответы пишутся в results.json рядом (раньше без
// этого файла тест падал).
//
// Задача 2026-11-03: кейсы `hydration` и `evap` обращались к удалённой
// модели выхода (`yield_physics.dart`) и теперь отвечают `removed`;
// `classify` берёт группу из FoodClassifier, потери — из LossTable; порция
// считается только при известном весе готового блюда.
//
// Run: flutter test test/reaudit_formula_driver_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/food_classifier.dart';
import 'package:povarspravka/core/calculation/loss_table.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

final String kDir = [
  Directory.systemTemp.path,
  'povar_reaudit',
  'formula',
].join(Platform.pathSeparator);

/// Имя способа обработки, как в документе: имена удалённой модели
/// (`soup`, `grain`, `fryMain`) — алиасы, неизвестное — legacy.
HeatProcess parseProcess(String s) => HeatProcess.fromJsonName(s);

Product productOf(Map<String, dynamic> j) => Product(
      id: 1,
      code: 'c',
      name: j['name'] as String,
      groupId: 0,
      source: 'skurikhin',
      wastePct: (j['waste'] as num?)?.toDouble() ?? 0.0,
      protein: (j['p'] as num?)?.toDouble() ?? 0.0,
      fat: (j['f'] as num?)?.toDouble() ?? 0.0,
      carbs: (j['c'] as num?)?.toDouble() ?? 0.0,
      kcal: 0,
      alcohol: (j['alcohol'] as num?)?.toDouble() ?? 0.0,
      fiber: (j['fiber'] as num?)?.toDouble() ?? 0.0,
    );

Dish dishOf(Map<String, dynamic> j) {
  final ings = <Ingredient>[];
  var i = 0;
  for (final r in (j['ings'] as List<dynamic>)) {
    final m = r as Map<String, dynamic>;
    ings.add(Ingredient(
      id: 'i${i++}',
      product: productOf(m),
      weightGrams: (m['w'] as num).toDouble(),
      isGross: (m['gross'] as bool?) ?? false,
    ));
  }
  return Dish(
    id: 'd',
    ingredients: ings,
    customYieldGrams: (j['customYield'] as num?)?.toDouble(),
    retentionProtein: (j['rP'] as num?)?.toDouble() ?? 0.94,
    retentionFat: (j['rF'] as num?)?.toDouble() ?? 0.88,
    retentionCarbs: (j['rC'] as num?)?.toDouble() ?? 0.91,
    process: parseProcess(j['process'] as String? ?? 'legacy'),
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

Map<String, dynamic> runCase(Map<String, dynamic> c) {
  final kind = c['kind'] as String;
  final resp = <String, dynamic>{'id': c['id']};
  try {
    switch (kind) {
      case 'waste':
        final w = (c['waste'] as num).toDouble();
        final g = (c['gross'] as num).toDouble();
        resp['net'] = Ingredient.netFromGross(g, w);
        resp['back'] =
            Ingredient.grossFromNet(Ingredient.netFromGross(g, w), w);
      case 'core':
        final d = dishOf(c['dish'] as Map<String, dynamic>);
        final r = CalculationEngine.calculate(d);
        resp['process'] = r.process.name;
        resp['yield'] = r.yieldGrams;
        resp['hasYield'] = r.hasYield;
        resp['rawW'] = r.rawTotalWeight;
        resp['rawP'] = r.rawTotalProtein;
        resp['rawF'] = r.rawTotalFat;
        resp['rawC'] = r.rawTotalCarbs;
        resp['rawKcal'] = r.rawTotalKcal ?? -1.0;
        resp['cookedP'] = r.cookedProtein;
        resp['cookedF'] = r.cookedFat;
        resp['cookedC'] = r.cookedCarbs;
        resp['cookedKcal'] = r.cookedKcal;
        resp['p100P'] = r.per100gProtein;
        resp['p100F'] = r.per100gFat;
        resp['p100C'] = r.per100gCarbs;
        resp['p100Kcal'] = r.per100gKcal;
        resp['fmtP'] = CalculationEngine.formatMacro(r.cookedProtein);
        resp['fmtF'] = CalculationEngine.formatMacro(r.cookedFat);
        resp['fmtC'] = CalculationEngine.formatMacro(r.cookedCarbs);
        resp['fmtKcal'] = CalculationEngine.formatKcal(r.cookedKcal);
        resp['fmtRawP'] = CalculationEngine.formatMacro(r.rawTotalProtein);
        resp['fmtRawF'] = CalculationEngine.formatMacro(r.rawTotalFat);
        resp['fmtRawC'] = CalculationEngine.formatMacro(r.rawTotalCarbs);
        resp['fmtRawKcal'] =
            CalculationEngine.formatKcal(r.rawTotalKcal ?? double.nan);
        resp['fmtYield'] = CalculationEngine.formatGrams(r.yieldGrams);
        // Без веса готового блюда порция не определена (StateError).
        if (r.hasYield) {
          final p = r.portion(r.yieldGrams);
          resp['portionWhole'] = [p.protein, p.fat, p.carbs, p.kcal];
          final p200 = r.portion(200);
          resp['portion200'] = [p200.protein, p200.fat, p200.carbs, p200.kcal];
        } else {
          resp['portionWhole'] = null;
          resp['portion200'] = null;
        }
        resp['perRow'] = [
          for (final ing in d.ingredients)
            [
              ing.netGramsRounded,
              ing.proteinInDish,
              ing.fatInDish,
              ing.carbsInDish,
              ing.blankKcalInDish
            ]
        ];
        resp['cls'] = [
          for (final ing in d.ingredients)
            FoodClassifier.classify(ing.product).name
        ];
        resp['loss'] = [
          for (final l in r.lines) [l.loss.protein, l.loss.fat, l.loss.carbs]
        ];
      case 'energy':
        final p = (c['p'] as num).toDouble();
        final f = (c['f'] as num).toDouble();
        final cc = (c['c'] as num).toDouble();
        resp['energy'] = CalculationMath.energy(p, f, cc);
      case 'round':
        final v = (c['v'] as num).toDouble();
        resp['r1'] = CalculationMath.round1(v);
        resp['r2'] = CalculationMath.round2(v);
        resp['fG'] = CalculationEngine.formatGrams(v);
        resp['fM'] = CalculationEngine.formatMacro(v);
        resp['fK'] = CalculationEngine.formatKcal(v);
      case 'prodround':
        final a = (c['a'] as num).toDouble();
        final b = (c['b'] as num).toDouble();
        final dg = (c['digits'] as num).toInt();
        final div = (c['div'] as bool?) ?? false;
        resp['v'] = CalculationMath.productRounded(a, b, dg, divideBy100: div);
      case 'ratio':
        final a = (c['a'] as num).toDouble();
        final b = (c['b'] as num).toDouble();
        final dg = (c['digits'] as num).toInt();
        final m = (c['m'] as num?)?.toDouble() ?? 100.0;
        resp['v'] = CalculationMath.ratioRounded(a, b, dg, multiplier: m);
      case 'sum':
        final vals = [
          for (final x in (c['vals'] as List<dynamic>)) (x as num).toDouble()
        ];
        final dg = (c['digits'] as num).toInt();
        resp['v'] = CalculationMath.sumRounded(vals, dg);
      case 'classify':
        final pr = parseProcess(c['process'] as String);
        final cls = FoodClassifier.classifyByName(c['name'] as String);
        final loss = LossTable.lossFor(cls, pr);
        resp['cls'] = cls.name;
        resp['process'] = pr.name;
        resp['loss'] = [loss.protein, loss.fat, loss.carbs];
        resp['verified'] = loss.isVerified;
      case 'hydration':
      case 'evap':
        // Модель выхода (развариваемость, уварка) удалена: вес готового
        // блюда вводит повар.
        resp['error'] = 'removed: yield physics deleted (2026-11-03)';
        resp['names'] = [for (final p in HeatProcess.values) p.name];
      case 'parse':
        resp['v'] = CalculationEngine.parseInputDouble(c['s'] as String);
      default:
        resp['error'] = 'unknown kind';
    }
  } catch (e) {
    resp['error'] = e.toString();
  }
  return resp;
}

const _beef = {'name': 'Говядина 1 кат.', 'w': 100, 'p': 18.6, 'f': 16.0, 'c': 0};
const _potato = {'name': 'Картофель', 'w': 200, 'p': 2.0, 'f': 0.4, 'c': 16.3};

/// Встроенные кейсы: вход и ожидаемые поля ответа (числа — ±0,01).
/// Ожидания посчитаны вручную: говядина 100 г (18,6/16/0) + картофель
/// 200 г (2/0,4/16,3) = сырьё 22,6/16,8/32,6; legacy × 0,94/0,88/0,91; варка —
/// мясо 10/25/0 %, картофель 2/2/5 % (LossTable, МР 2.3.0419-26, прил. 4).
final List<(Map<String, dynamic>, Map<String, Object?>)> kBuiltIn = [
  (
    {'id': 'w1', 'kind': 'waste', 'gross': 200, 'waste': 25},
    {'net': 150.0, 'back': 200.0},
  ),
  (
    {
      'id': 'c-legacy',
      'kind': 'core',
      'dish': {
        'ings': [_beef, _potato],
      },
    },
    {
      'process': 'legacy',
      'yield': 300.0,
      'rawP': 22.6,
      'rawF': 16.8,
      'rawC': 32.6,
      'cookedP': 21.24,
      'cookedF': 14.78,
      'cookedC': 29.67,
      'cls': ['meat', 'rootTuber'],
      'loss': <Object?>[],
    },
  ),
  (
    {
      'id': 'c-boil-noweight',
      'kind': 'core',
      'dish': {
        'process': 'boil',
        'ings': [_beef, _potato],
      },
    },
    {
      'process': 'boil',
      'yield': 0.0,
      'hasYield': false,
      'cookedP': 20.66,
      'cookedF': 12.78,
      'cookedC': 30.97,
      'p100P': 0.0,
      'portionWhole': null,
      'loss': [
        [10.0, 25.0, 0.0],
        [2.0, 2.0, 5.0],
      ],
    },
  ),
  (
    {
      'id': 'c-soup-alias-weight',
      'kind': 'core',
      'dish': {
        'process': 'soup',
        'customYield': 250,
        'ings': [_beef, _potato],
      },
    },
    {
      'process': 'boil',
      'yield': 250.0,
      'hasYield': true,
      'cookedP': 20.66,
      'p100P': 8.26,
    },
  ),
  (
    {'id': 'e1', 'kind': 'energy', 'p': 10, 'f': 5, 'c': 20},
    {'energy': 165.0},
  ),
  (
    {'id': 'r1', 'kind': 'round', 'v': 1.25},
    {'r1': 1.3, 'r2': 1.25},
  ),
  (
    {'id': 'pr1', 'kind': 'prodround', 'a': 150, 'b': 18.6, 'digits': 2, 'div': true},
    {'v': 27.9},
  ),
  (
    {'id': 'ra1', 'kind': 'ratio', 'a': 27.9, 'b': 300, 'digits': 2},
    {'v': 9.3},
  ),
  (
    {'id': 's1', 'kind': 'sum', 'vals': [0.1, 0.2, 0.3], 'digits': 1},
    {'v': 0.6},
  ),
  (
    {'id': 'k1', 'kind': 'classify', 'name': 'Масло сливочное', 'process': 'fryMain'},
    {'cls': 'fatOil', 'process': 'fry', 'loss': [50.0, 50.0, 50.0]},
  ),
  (
    {'id': 'k2', 'kind': 'classify', 'name': 'Творог 9%', 'process': 'grain'},
    {'cls': 'dairy', 'process': 'boil', 'loss': [5.0, 5.0, 5.0]},
  ),
  (
    {'id': 'k3', 'kind': 'classify', 'name': 'Говядина 1 кат.', 'process': 'cold'},
    {'cls': 'meat', 'process': 'cold', 'loss': [0.0, 0.0, 0.0]},
  ),
  (
    {'id': 'h1', 'kind': 'hydration', 'name': 'Крупа гречневая'},
    {'error': 'removed: yield physics deleted (2026-11-03)'},
  ),
  (
    {'id': 'p1', 'kind': 'parse', 's': '1,5'},
    {'v': 1.5},
  ),
];

void _expectValue(Object? actual, Object? expected, String where) {
  if (expected is num) {
    expect(actual, isA<num>(), reason: where);
    expect((actual as num).toDouble(), closeTo(expected.toDouble(), 0.01),
        reason: where);
  } else if (expected is List) {
    expect(actual, isA<List<dynamic>>(), reason: where);
    final list = actual as List<dynamic>;
    expect(list.length, expected.length, reason: where);
    for (var i = 0; i < expected.length; i++) {
      _expectValue(list[i], expected[i], '$where[$i]');
    }
  } else {
    expect(actual, expected, reason: where);
  }
}

void main() {
  test('reaudit formula driver', () {
    // 1) Встроенные кейсы — всегда, с проверкой ожиданий.
    for (final (input, expected) in kBuiltIn) {
      final resp = runCase(input);
      if (!expected.containsKey('error')) {
        expect(resp['error'], isNull, reason: '${input['id']}: ${resp['error']}');
      }
      for (final e in expected.entries) {
        _expectValue(resp[e.key], e.value, '${input['id']}.${e.key}');
      }
    }

    // 2) Внешние кейсы аудитора — только если файл положен.
    final inFile = File('$kDir${Platform.pathSeparator}cases.json');
    if (inFile.existsSync()) {
      final decoded = jsonDecode(inFile.readAsStringSync());
      final List<dynamic> cases =
          decoded is List ? decoded : (decoded['cases'] as List<dynamic>);
      final out = [
        for (final raw in cases) runCase(raw as Map<String, dynamic>)
      ];
      File('$kDir${Platform.pathSeparator}results.json')
          .writeAsStringSync(jsonEncode(out));
      expect(out.length, cases.length);
    }
  });
}
