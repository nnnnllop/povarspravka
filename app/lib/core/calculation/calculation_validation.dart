import 'models/dish.dart';
import 'models/product.dart';

/// Reject corrupt inputs rather than manufacturing zero nutrients.
class CalculationValidation {
  static bool inRange(double value, double min, double max) =>
      value.isFinite && value >= min && value <= max;

  static void range(double value, double min, double max, String name) {
    if (!inRange(value, min, max)) {
      throw ArgumentError.value(value, name, 'Expected finite $min..$max');
    }
  }

  static void product(Product p) {
    if (!p.hasExplicitProtein || p.protein.isNaN) {
      throw ArgumentError('Product missing protein');
    }
    if (!p.hasExplicitFat || p.fat.isNaN) {
      throw ArgumentError('Product missing fat');
    }
    if (!p.hasExplicitCarbs || p.carbs.isNaN) {
      throw ArgumentError('Product missing carbs');
    }
    range(p.wastePct, 0, 100, 'wastePct');
    range(p.protein, 0, 100, 'protein');
    range(p.fat, 0, 100, 'fat');
    range(p.carbs, 0, 100, 'carbs');
    if (p.protein + p.fat + p.carbs > 100.05) {
      throw ArgumentError(
        'Product nutrients sum (${p.protein} + ${p.fat} + ${p.carbs}) exceeds 100g',
      );
    }
  }

  static void dish(Dish dish) {
    for (final r in [
      dish.retentionProtein,
      dish.retentionFat,
      dish.retentionCarbs
    ]) {
      range(r, 0, 1, 'retention');
    }
    if (dish.customYieldGrams != null) {
      range(dish.customYieldGrams!, .1, 9999999, 'customYieldGrams');
    }
    for (final ing in dish.ingredients) {
      range(ing.weightGrams, 0, 9999999, 'weightGrams');
      product(ing.product);
    }
  }
}
