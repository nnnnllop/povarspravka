import 'calculation_math.dart';
import 'calculation_validation.dart';
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
    CalculationValidation.dish(dish);
    final rawTotalWeight = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.netGramsRounded), 1);
    final rawTotalProtein = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.proteinInDish), 2);
    final rawTotalFat = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.fatInDish), 2);
    final rawTotalCarbs = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.carbsInDish), 2);
    final rawTotalKcal = CalculationMath.sumRounded(
        dish.ingredients.map((i) => i.blankKcalInDish), 1);

    // Сохранность при тепловой обработке
    final pPct = CalculationMath.productRounded(dish.retentionProtein, 100, 10);
    final fPct = CalculationMath.productRounded(dish.retentionFat, 100, 10);
    final cPct = CalculationMath.productRounded(dish.retentionCarbs, 100, 10);

    final cookedProtein = CalculationMath.productRounded(
        rawTotalProtein, pPct, 2,
        divideBy100: true);
    final cookedFat =
        CalculationMath.productRounded(rawTotalFat, fPct, 2, divideBy100: true);
    final cookedCarbs = CalculationMath.productRounded(rawTotalCarbs, cPct, 2,
        divideBy100: true);

    // Формула ЭЦ: Б × 4 + Ж × 9 + У × 4
    final cookedKcal =
        CalculationMath.energy(cookedProtein, cookedFat, cookedCarbs);

    // One source of truth for the editor, saved recipes and exports.
    // An empty recipe has zero mass, not a fictitious 100 g yield.
    final yieldGrams = dish.effectiveYieldGrams;

    final totalCookedMacros = CalculationMath.sumRounded(
        [cookedProtein, cookedFat, cookedCarbs], 2);
    if (CalculationMath.sumExceeds(
        [cookedProtein, cookedFat, cookedCarbs], yieldGrams)) {
      throw ArgumentError(
        'Cooked macronutrients mass ($totalCookedMacros g) cannot exceed dish yield ($yieldGrams g)',
      );
    }

    // В 100 г готового блюда
    final per100gProtein = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedProtein, yieldGrams, 2)
        : 0.0;
    final per100gFat = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedFat, yieldGrams, 2)
        : 0.0;
    final per100gCarbs = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedCarbs, yieldGrams, 2)
        : 0.0;
    final per100gKcal = yieldGrams > 0
        ? CalculationMath.ratioRounded(cookedKcal, yieldGrams, 1)
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
    return _round2(value).toStringAsFixed(2).replaceAll('.', ',');
  }

  static String formatKcal(double value) {
    return _round1(value).toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Shared exact percentage text for UI and all exports.
  static String formatPercent(double retention) =>
      CalculationMath.productRounded(retention, 100, 10)
          .toStringAsFixed(10)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '')
          .replaceAll('.', ',');

  /// Exact format for waste percentage (e.g. 1.5 -> "1,5", 25 -> "25")
  static String formatWastePercent(double wastePct) => wastePct
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .replaceAll('.', ',');

  /// Разбор пользовательского ввода с поддержкой запятой и точки
  static double? parseInputDouble(String input) {
    final cleaned = input.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
