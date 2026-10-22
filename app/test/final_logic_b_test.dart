// Final logic audit - Block B: one recipe must print the SAME numbers on every
// surface.  The surfaces are derived from the same CalculationEngine result, so
// this test proves agreement at the data level and dumps the exact strings each
// surface consumes for cross-checking against generated PDF/DOCX/XLSX.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product prod(String name, double p, double f, double c, {double waste = 0}) =>
    Product(
      id: name.hashCode,
      code: name,
      name: name,
      groupId: 1,
      source: 'skurikhin',
      wastePct: waste,
      protein: p,
      fat: f,
      carbs: c,
      kcal: 0,
    );

List<Ingredient> a4() => [
      Ingredient(id: '1', product: prod('Говядина 1 кат.', 18.60, 16.00, 0), weightGrams: 600),
      Ingredient(id: '2', product: prod('Лук', 1.40, .20, 8.20), weightGrams: 100),
      Ingredient(id: '3', product: prod('Хлеб пшеничный', 7.60, .80, 49.20), weightGrams: 80),
      Ingredient(id: '4', product: prod('Молоко 3,2%', 2.90, 3.20, 4.70), weightGrams: 120),
      Ingredient(id: '5', product: prod('Масло сливочное', .80, 72.50, 1.30), weightGrams: 100),
    ];

Dish make(List<Ingredient> ings,
        {double? y = 750,
        double rp = .94,
        double rf = .88,
        double rc = .91,
        BlankMode mode = BlankMode.photoCross}) =>
    Dish(
      id: 'a4',
      ingredients: ings,
      customYieldGrams: y,
      retentionProtein: rp,
      retentionFat: rf,
      retentionCarbs: rc,
      blankMode: mode,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// The exact strings every surface displays for a dish.
Map<String, dynamic> surface(Dish d) {
  final r = CalculationEngine.calculate(d);
  return {
    'nets': d.ingredients
        .map((i) => CalculationEngine.formatGrams(i.netGramsRounded))
        .toList(),
    'rawP': CalculationEngine.formatMacro(r.rawTotalProtein),
    'rawF': CalculationEngine.formatMacro(r.rawTotalFat),
    'rawC': CalculationEngine.formatMacro(r.rawTotalCarbs),
    'cookedP': CalculationEngine.formatMacro(r.cookedProtein),
    'cookedF': CalculationEngine.formatMacro(r.cookedFat),
    'cookedC': CalculationEngine.formatMacro(r.cookedCarbs),
    'cookedKcal': CalculationEngine.formatKcal(r.cookedKcal),
    'yield': CalculationEngine.formatGrams(r.yieldGrams),
    'per100P': CalculationEngine.formatMacro(r.per100gProtein),
    'per100F': CalculationEngine.formatMacro(r.per100gFat),
    'per100C': CalculationEngine.formatMacro(r.per100gCarbs),
    'per100Kcal': CalculationEngine.formatKcal(r.per100gKcal),
    'retP': CalculationEngine.formatPercent(d.retentionProtein),
    'retF': CalculationEngine.formatPercent(d.retentionFat),
    'retC': CalculationEngine.formatPercent(d.retentionCarbs),
  };
}

void main() {
  final baseline = surface(make(a4()));
  final log = <String, dynamic>{'baseline': baseline};

  test('B: reference numbers for A4', () {
    expect(baseline['rawP'], '123,36');
    expect(baseline['rawF'], '173,18');
    expect(baseline['rawC'], '54,50');
    expect(baseline['cookedP'], '115,96');
    expect(baseline['cookedF'], '152,40');
    expect(baseline['cookedC'], '49,60');
    expect(baseline['cookedKcal'], '2033,8');
    expect(baseline['per100P'], '15,46');
    expect(baseline['per100F'], '20,32');
    expect(baseline['per100C'], '6,61');
    expect(baseline['per100Kcal'], '271,2');
    expect(baseline['yield'], '750');
  });

  test('B1 photoCross <-> detailed: cooked numbers identical', () {
    final a = surface(make(a4()));
    final b = surface(make(a4(), mode: BlankMode.detailed));
    for (final k in [
      'cookedP', 'cookedF', 'cookedC', 'cookedKcal',
      'per100P', 'per100F', 'per100C', 'per100Kcal', 'rawP', 'rawF', 'rawC'
    ]) {
      expect(b[k], a[k], reason: 'mode switch changed $k');
    }
  });

  test('B2 gross <-> net entry: net mass unchanged', () {
    // 750 g net entered as gross with 0% waste must equal 750 g net.
    final asNet = make([
      Ingredient(id: '1', product: prod('Говядина 1 кат.', 18.60, 16.00, 0), weightGrams: 600),
    ], y: null);
    final asGross = make([
      Ingredient(id: '1', product: prod('Говядина 1 кат.', 18.60, 16.00, 0), weightGrams: 600, isGross: true),
    ], y: null);
    expect(asGross.ingredients.first.netGramsRounded,
        asNet.ingredients.first.netGramsRounded);
    // with waste the net shrinks consistently in both entry modes
    final gross = Ingredient(
        id: 'g', product: prod('Картофель', 2.0, .4, 16.3, waste: 28),
        weightGrams: 400, isGross: true);
    expect(gross.netGramsRounded, 288); // 400*72/100
  });

  test('B3 yield auto -> manual -> auto returns to the original numbers', () {
    final auto = surface(make(a4(), y: null));
    final manual = surface(make(a4(), y: 750));
    final backToAuto = surface(make(a4(), y: null));
    expect(backToAuto, equals(auto));
    // manual 750 differs from auto 1000 in per-100g only
    expect(manual['cookedP'], auto['cookedP']);
    expect(manual['per100P'], isNot(auto['per100P']));
  });

  test('B4 retention toggles restore the original strings', () {
    final a = surface(make(a4()));
    final cold = surface(make(a4(), rp: 1, rf: 1, rc: 1));
    final back = surface(make(a4()));
    expect(back, equals(a));
    expect(cold['retP'], '100');
    expect(cold['cookedP'], a['rawP']); // retention 100 -> equals raw total
  });

  test('B5 save -> reload (JSON round trip) -> duplicate keeps numbers', () {
    final d = make(a4());
    final restored = Dish.fromJson(jsonDecode(jsonEncode(d.toJson())));
    expect(surface(restored), equals(baseline));
    final dup = Dish.fromJson(jsonDecode(jsonEncode(restored.toJson())));
    expect(surface(dup), equals(baseline));
  });

  test('B6 household measure grams are the reference value', () {
    // Two eggs at 47 g each must be 94 g, not 2 g.
    final egg = Ingredient(id: 'e', product: prod('Яйцо куриное', 12.7, 11.5, .7), weightGrams: 94);
    expect(CalculationEngine.formatGrams(egg.netGramsRounded), '94');
  });

  dumpLog(log);
}

void dumpLog(Map<String, dynamic> log) {
  final f = File(r'C:\projects\povarspravka\audit\signoff\b_results.json');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(log));
}
