import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/calculation/yield_explanation.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

const beet = Product(
    id: 1,
    code: '1',
    name: 'Свекла',
    groupId: 1,
    source: 'skurikhin',
    protein: 1.5,
    fat: .1,
    carbs: 8.8,
    kcal: 42);
Dish fixture(double grams, {double? yieldGrams, bool gross = false}) => Dish(
    id: 'beet',
    ingredients: [
      Ingredient(
          id: 'beet-1', product: beet, weightGrams: grams, isGross: gross)
    ],
    customYieldGrams: yieldGrams,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026));

void main() {
  test('100 g automatic yield: whole and per100 identical after retention', () {
    final dish = fixture(100);
    final r = CalculationEngine.calculate(dish);
    expect(dish.customYieldGrams, isNull);
    expect(r.yieldGrams, 100);
    expect(r.cookedProtein, 1.41);
    expect(r.cookedFat, .09);
    expect(r.cookedCarbs, 8.01);
    expect(r.cookedKcal, 38.5);
    expect([r.per100gProtein, r.per100gFat, r.per100gCarbs, r.per100gKcal],
        [r.cookedProtein, r.cookedFat, r.cookedCarbs, r.cookedKcal]);
  });
  test('Explicit dilution changes concentration, not total nutrients', () {
    final r = CalculationEngine.calculate(fixture(100, yieldGrams: 200));
    expect(r.cookedProtein, 1.41);
    expect(r.per100gProtein, .71);
    expect(r.per100gKcal, 19.3);
    const e = YieldExplanation(100, 200);
    expect(e.concentration, .5);
    expect(e.badge, contains('+100 г'));
    expect(e.description, contains('предполагает'));
    expect(e.description, contains('отдельными ингредиентами'));
  });
  test('Explicit evaporation: no nutrient creation', () {
    final r = CalculationEngine.calculate(fixture(200, yieldGrams: 100));
    expect(r.cookedProtein, 2.82);
    expect(r.per100gProtein, 2.82);
    expect(r.cookedKcal, 77);
    const e = YieldExplanation(200, 100);
    expect(e.concentration, 2);
    expect(e.badge, contains('50%'));
    expect(e.description, contains('не появляются'));
  });
  test('Automatic yield follows edits, add, remove, undo', () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    n.addIngredient(beet, 100);
    final ing = n.state.ingredients.single;
    expect(n.state.effectiveYieldGrams, 100);
    n.updateIngredient(ing.id, 200);
    expect(n.state.effectiveYieldGrams, 200);
    n.addIngredient(beet, 50);
    expect(n.state.effectiveYieldGrams, 250);
    n.removeIngredient(ing.id);
    expect(n.state.effectiveYieldGrams, 50);
    n.restoreIngredient(ing, 0);
    expect(n.state.effectiveYieldGrams, 150);
    n.restoreIngredient(ing, 0);
    expect(n.state.ingredients.length, 2);
    await n.flushPendingSaves();
  });
  test('Custom yield persists until explicitly reset', () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    n.addIngredient(beet, 100);
    n.setCustomYield(200);
    n.updateIngredient(n.state.ingredients.single.id, 150);
    expect(n.state.effectiveYieldGrams, 200);
    n.setCustomYield(null);
    expect(n.state.effectiveYieldGrams, 150);
    await n.flushPendingSaves();
  });
  test('Invalid custom input never silently resets a valid yield', () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    n.setCustomYield(200);
    for (final invalid in [0.0, -10.0, .01, double.nan, double.infinity]) {
      n.setCustomYield(invalid);
      expect(n.state.customYieldGrams, 200);
    }
    await n.flushPendingSaves();
  });
  test('Comma input, non-finite and invalid text', () {
    expect(CalculationEngine.parseInputDouble('150,5'), 150.5);
    for (final value in ['', 'NaN', 'Infinity', '1e999', 'abc']) {
      expect(CalculationEngine.parseInputDouble(value), isNull);
    }
  });
  test('Serialization preserves explicit and automatic yield', () {
    for (final dish in [fixture(100), fixture(100, yieldGrams: 200)]) {
      final copy = Dish.fromJson(dish.toJson());
      expect(copy.customYieldGrams, dish.customYieldGrams);
      expect(copy.effectiveYieldGrams, dish.effectiveYieldGrams);
    }
  });
  test('Empty recipe has no phantom 100 g', () {
    final dish = fixture(0).copyWith(ingredients: []);
    final r = CalculationEngine.calculate(dish);
    expect(r.yieldGrams, 0);
    expect(r.per100gKcal, 0);
    expect(const YieldExplanation(0, 0).hasBasis, isFalse);
  });
  test('Mass correction does not change retention or total energy', () {
    final base = CalculationEngine.calculate(fixture(200));
    for (final mass in [.1, 100.0, 200.0, 99999.0]) {
      final r = CalculationEngine.calculate(fixture(200, yieldGrams: mass));
      expect(r.cookedProtein, base.cookedProtein);
      expect(r.cookedKcal, base.cookedKcal);
      expect(r.retentionProtein, .94);
    }
  });
  test('Zero retention and no heating remain independent of yield', () {
    for (final retention in [0.0, 1.0]) {
      final r = CalculationEngine.calculate(fixture(100).copyWith(
          retentionProtein: retention,
          retentionFat: retention,
          retentionCarbs: retention));
      expect(r.cookedProtein, 1.5 * retention);
      expect(r.per100gProtein, r.cookedProtein);
    }
  });
}
