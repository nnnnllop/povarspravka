// Regression tests for calculation oracle hygiene:
// - F05 / mutation A27 closure: `round2` precision on `proteinInDish`,
//   `fatInDish`, and `carbsInDish` (catches `round2 -> round1` on any of the
//   three getters without touching existing `audit3_*_test.dart` files).
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';

void main() {
  test('A27 control: Ingredient protein/fat/carbs retain round2 precision', () {
    const prod = Product(
      id: 99001,
      code: 'hygiene-a27',
      name: 'Контрольный продукт БЖУ round2',
      groupId: 3,
      source: 'skurikhin',
      protein: 1.23,
      fat: 2.34,
      carbs: 3.47,
      kcal: 40,
    );
    const ing = Ingredient(
      id: 'ing-a27',
      product: prod,
      weightGrams: 137.3,
    );

    // 1.23 * 137.3 / 100 = 1.68879 -> round2 = 1.69 (round1 = 1.7)
    // 2.34 * 137.3 / 100 = 3.21282 -> round2 = 3.21 (round1 = 3.2)
    // 3.47 * 137.3 / 100 = 4.76431 -> round2 = 4.76 (round1 = 4.8)
    expect(ing.proteinInDish, 1.69);
    expect(ing.fatInDish, 3.21);
    expect(ing.carbsInDish, 4.76);

    final dish = Dish.withProcess(
      id: 'dish-a27',
      process: HeatProcess.cold,
      ingredients: const [ing],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final result = CalculationEngine.calculate(dish);
    expect(
      [result.cookedProtein, result.cookedFat, result.cookedCarbs],
      [1.69, 3.21, 4.76],
    );
  });
}
