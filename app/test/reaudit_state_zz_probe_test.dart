// [DIAGNOSTIC PROBE — NOT ACCEPTANCE COVERAGE]
// Diagnostic dump helpers kept for manual inspection; zero-expect tests here
// (macros / editor dump / home dump) intentionally print state and do not
// substitute for regression coverage in `reaudit_state_*_test.dart`.
//
// Probe 1 — confirm the numbers before writing assertions.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'reaudit_state_support.dart';

void main() {
  test('defaults', () {
    final d = Dish(
        id: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(d.process, HeatProcess.legacy);
    expect(Dish.fromJson({'id': 'z'}).process, HeatProcess.legacy);
  });

  test('macros for potato 250 gross, legacy', () {
    final d = dishWith(const [
      Ingredient(id: 'i', product: potato, weightGrams: 250, isGross: true)
    ]);
    final r = CalculationEngine.calculate(d);
    // ignore: avoid_print
    print('P=${r.cookedProtein} F=${r.cookedFat} C=${r.cookedCarbs} '
        'kcal=${r.cookedKcal} yield=${r.yieldGrams} raw=${r.rawTotalWeight} '
        'p100=${r.per100gKcal}');
  });

  testWidgets('dump editor text for uncalculable dish', (tester) async {
    phoneSize(tester);
    final n = DishNotifier(storage: RecordingStorage());
    n.loadDish(uncalculableDish());
    final h = Harness(dish: n);
    await tester.pumpWidget(h.wrap(const RecipeEditorScreen()));
    await tester.pump();
    // ignore: avoid_print
    print('--- EDITOR TEXT ---\n${visibleText(tester)}\n--- END ---');
    h.dispose();
  });

  testWidgets('dump home text with saved uncalculable dish', (tester) async {
    phoneSize(tester);
    final n = DishNotifier(storage: RecordingStorage());
    n.loadDish(healthyDish());
    final saved = SavedDishesNotifier(RecordingStorage());
    saved.setInitialDishes([uncalculableDish(id: 'saved-bad')], healthyDish());
    final h = Harness(dish: n, saved: saved);
    await tester.pumpWidget(h.wrap(const HomeScreen()));
    await tester.pump();
    // ignore: avoid_print
    print('--- HOME TEXT ---\n${visibleText(tester)}\n--- END ---');
    h.dispose();
  });

  test('list provider names referenced by editor', () {
    final keys = <String>['calculationResultProvider'];
    expect(keys, isNotEmpty);
  });
}

