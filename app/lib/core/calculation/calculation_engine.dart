import 'calculation_math.dart';
import 'models/blank_mode.dart';
import 'models/calculation_result.dart';
import 'models/dish.dart';

class CalculationEngine {
  static double _round1(double v) => CalculationMath.round1(v);
  static double _round2(double v) => CalculationMath.round2(v);

  /// Выполняет расчет показателей бланка для переданного блюда.
  /// Суммы по столбцам рассчитываются по округленным значениям ячеек (до 0,01 г / 0,1 ккал),
  /// чтобы ручная проверка калькулятором по напечатанному бланку сходилась копейка в копейку.
  static CalculationResult calculate(Dish dish) {
    double rawTotalWeight = 0.0;
    double rawTotalProtein = 0.0;
    double rawTotalFat = 0.0;
    double rawTotalCarbs = 0.0;
    double rawTotalKcal = 0.0;

    for (final ing in dish.ingredients) {
      rawTotalWeight += ing.netGramsRounded;
      rawTotalProtein += ing.proteinInDish;
      rawTotalFat += ing.fatInDish;
      rawTotalCarbs += ing.carbsInDish;
      rawTotalKcal += ing.blankKcalInDish;
    }

    rawTotalWeight = _round1(rawTotalWeight);
    rawTotalProtein = _round2(rawTotalProtein);
    rawTotalFat = _round2(rawTotalFat);
    rawTotalCarbs = _round2(rawTotalCarbs);
    rawTotalKcal = _round1(rawTotalKcal);

    // Сохранность при тепловой обработке
    final pPct = CalculationMath.productRounded(dish.retentionProtein, 100, 10);
    final fPct = CalculationMath.productRounded(dish.retentionFat, 100, 10);
    final cPct = CalculationMath.productRounded(dish.retentionCarbs, 100, 10);

    final cookedProtein = CalculationMath.productRounded(
        rawTotalProtein, pPct, 2,
        divideBy100: true);
    final cookedFat = CalculationMath.productRounded(
        rawTotalFat, fPct, 2,
        divideBy100: true);
    final cookedCarbs = CalculationMath.productRounded(
        rawTotalCarbs, cPct, 2,
        divideBy100: true);

    // Формула ЭЦ: Б × 4 + Ж × 9 + У × 4
    final cookedKcal =
        CalculationMath.energy(cookedProtein, cookedFat, cookedCarbs);

    final baseYield =
        (dish.customYieldGrams != null && dish.customYieldGrams! > 0)
            ? _round1(dish.customYieldGrams!)
            : rawTotalWeight;

    final yieldGrams = baseYield > 0 ? baseYield : 100.0;

    // В 100 г готового блюда
    final per100gProtein = yieldGrams > 0
        ? CalculationMath.productRounded(
            cookedProtein / yieldGrams, 100, 2)
        : 0.0;
    final per100gFat = yieldGrams > 0
        ? CalculationMath.productRounded(cookedFat / yieldGrams, 100, 2)
        : 0.0;
    final per100gCarbs = yieldGrams > 0
        ? CalculationMath.productRounded(
            cookedCarbs / yieldGrams, 100, 2)
        : 0.0;
    final per100gKcal = yieldGrams > 0
        ? CalculationMath.productRounded(
            cookedKcal / yieldGrams, 100, 1)
        : 0.0;

    return CalculationResult(
      blankMode: dish.blankMode,
      yieldGrams: yieldGrams,
      rawTotalWeight: rawTotalWeight,
      rawTotalProtein: rawTotalProtein,
      rawTotalFat: rawTotalFat,
      rawTotalCarbs: rawTotalCarbs,
      rawTotalKcal: dish.blankMode == BlankMode.detailed ? rawTotalKcal : null,
      retentionProtein: dish.retentionProtein,
      retentionFat: dish.retentionFat,
      retentionCarbs: dish.retentionCarbs,
      cookedProtein: cookedProtein,
      cookedFat: cookedFat,
      cookedCarbs: cookedCarbs,
      cookedKcal: cookedKcal,
      per100gProtein: per100gProtein,
      per100gFat: per100gFat,
      per100gCarbs: per100gCarbs,
      per100gKcal: per100gKcal,
    );
  }

  /// Форматирование чисел для бланка с русской десятичной запятой
  static String formatGrams(double value) {
    final rounded = _round1(value);
    if (rounded == rounded.roundToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(1).replaceAll('.', ',');
  }

  static String formatMacro(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String formatKcal(double value) {
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Разбор пользовательского ввода с поддержкой запятой и точки
  static double? parseInputDouble(String input) {
    final cleaned = input.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }
}
