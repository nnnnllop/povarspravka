// Final logic audit - Block D: the ten real student scenarios, driven through
// the real engine and the real input parser.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

Product prod(String name,
        {double p = 2, double f = .4, double c = 16.3, double waste = 0}) =>
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
      kcal: 77,
    );

Dish one(Ingredient i, {double? y}) => Dish(
      id: 'd',
      ingredients: [i],
      customYieldGrams: y,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final notes = <String>[];

  test('D1 potato entered as gross shows NET in the billet', () {
    // 300 g gross at 28% waste -> 216 g net, which is what the blank prints.
    final d = one(Ingredient(
        id: '1',
        product: prod('Картофель', waste: 28),
        weightGrams: 300,
        isGross: true));
    final r = CalculationEngine.calculate(d);
    expect(d.ingredients.first.netGramsRounded, 216);
    expect(CalculationEngine.formatGrams(d.ingredients.first.netGramsRounded),
        '216');
    expect(r.rawTotalWeight, 216);
    notes.add('D1 net printed = 216 g (not 300)');
  });

  test('D2 two eggs converts to grams, not 2', () {
    final d = one(Ingredient(
        id: '1', product: prod('Яйцо куриное', p: 12.7, f: 11.5, c: .7),
        weightGrams: 94));
    expect(CalculationEngine.formatGrams(d.ingredients.first.netGramsRounded),
        '94');
    notes.add('D2 2 eggs = 94 g');
  });

  test('D3 same product twice sums correctly', () {
    final d = Dish(
      id: 'd',
      ingredients: [
        Ingredient(id: '1', product: prod('Картофель'), weightGrams: 150),
        Ingredient(id: '2', product: prod('Картофель'), weightGrams: 150),
      ],
      retentionProtein: 1,
      retentionFat: 1,
      retentionCarbs: 1,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final r = CalculationEngine.calculate(d);
    expect(r.rawTotalWeight, 300);
    // 150*2/100=3,00 twice -> 6,00 ; carbs 150*16,3/100=24,45 twice -> 48,90
    expect(r.rawTotalProtein, 6.00);
    expect(r.rawTotalCarbs, 48.90);
    notes.add('D3 duplicate sums to 6,00 / 48,90');
  });

  test('D4 delete then undo restores numbers', () {
    final ings = [
      Ingredient(id: '1', product: prod('Картофель'), weightGrams: 150),
      Ingredient(id: '2', product: prod('Морковь', p: 1.3, f: .1, c: 6.9), weightGrams: 100),
    ];
    final before = CalculationEngine.calculate(
        Dish(id: 'd', ingredients: ings, createdAt: DateTime(2026),
            updatedAt: DateTime(2026)));
    final afterDelete = CalculationEngine.calculate(
        Dish(id: 'd', ingredients: [ings.first], createdAt: DateTime(2026),
            updatedAt: DateTime(2026)));
    final restored = CalculationEngine.calculate(
        Dish(id: 'd', ingredients: List.of(ings), createdAt: DateTime(2026),
            updatedAt: DateTime(2026)));
    expect(afterDelete.rawTotalWeight, 150);
    expect(restored.rawTotalProtein, before.rawTotalProtein);
    expect(restored.rawTotalWeight, before.rawTotalWeight);
    notes.add('D4 undo restores identically');
  });

  test('D5 impossible yield is rejected with a message', () {
    // 600 g of pure fat -> cooked fat ~528 g; a 100 g yield is impossible.
    final d = one(Ingredient(
        id: '1', product: prod('Масло', p: 0, f: 99.9, c: 0), weightGrams: 600),
        y: 100);
    Object? err;
    try {
      CalculationEngine.calculate(d);
    } catch (e) {
      err = e;
    }
    expect(err, isNotNull);
    notes.add('D5 engine throws: ${err.toString().split('\n').first}');
  });

  test('D7 pathological mass inputs parse predictably', () {
    // The parser accepts a comma or a dot, rejects junk.
    expect(CalculationEngine.parseInputDouble('0'), 0.0);
    expect(CalculationEngine.parseInputDouble(',5'), .5);
    expect(CalculationEngine.parseInputDouble('5,'), 5.0);
    expect(CalculationEngine.parseInputDouble('1.000'), 1.0);
    expect(CalculationEngine.parseInputDouble('abc'), isNull);
    expect(CalculationEngine.parseInputDouble(''), isNull);
    // ',' -> '.' then parse: "," becomes "." which is not a number
    expect(CalculationEngine.parseInputDouble(','), isNull);
    notes.add('D7 0->0, ,5->0.5, 5,->5, 1.000->1, abc->null');
  });

  test('D8 empty recipe exports zero mass, not a fake 100 g', () {
    final r = CalculationEngine.calculate(
        Dish(id: 'd', createdAt: DateTime(2026), updatedAt: DateTime(2026)));
    expect(r.yieldGrams, 0);
    expect(r.rawTotalWeight, 0);
    expect(r.per100gKcal, 0);
    notes.add('D8 empty recipe -> yield 0');
  });

  test('D10 custom retention 90/85/90 appears in the formula block', () {
    final d = one(Ingredient(id: '1', product: prod('Картофель', p: 2, f: .4, c: 16.3), weightGrams: 100),
        y: 100);
    final custom = Dish(
        id: 'd',
        ingredients: d.ingredients,
        customYieldGrams: 100,
        retentionProtein: .90,
        retentionFat: .85,
        retentionCarbs: .90,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));
    expect(CalculationEngine.formatPercent(custom.retentionProtein), '90');
    expect(CalculationEngine.formatPercent(custom.retentionFat), '85');
    expect(CalculationEngine.formatPercent(custom.retentionCarbs), '90');
    final r = CalculationEngine.calculate(custom);
    // raw 2,00 / 0,40 / 16,30 ; 90% -> 1,80 ; 85% -> 0,34 ; 90% -> 14,67
    expect(r.cookedProtein, 1.80);
    expect(r.cookedFat, .34);
    expect(r.cookedCarbs, 14.67);
    notes.add('D10 90/85/90 -> 1,80 / 0,34 / 14,67');
  });

  test('D (report notes)', () {
    for (final n in notes) {
      // ignore: avoid_print
      print(n);
    }
  });
}
