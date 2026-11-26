import 'calculation_engine.dart';

/// Mass balance is an assumption, not evidence that water was added.
class YieldExplanation {
  final double rawGrams;
  final double yieldGrams;
  const YieldExplanation(this.rawGrams, this.yieldGrams);

  bool get hasBasis =>
      rawGrams.isFinite &&
      yieldGrams.isFinite &&
      rawGrams > 0 &&
      yieldGrams > 0;
  double get concentration => hasBasis ? rawGrams / yieldGrams : 1;
  double get delta => yieldGrams - rawGrams;
  bool get changed => hasBasis && delta.abs() >= 0.05;

  /// Сырьё есть, а вес готового блюда не указан. Приложение его не угадывает
  /// (задача 2026-11-03): итог показывается на всё блюдо.
  bool get needsYield =>
      rawGrams.isFinite &&
      rawGrams > 0 &&
      !(yieldGrams.isFinite && yieldGrams > 0);

  String get badge {
    if (needsYield) return 'Укажите вес готового блюда';
    if (!changed) return 'Вес равен сумме нетто';
    final factor = concentration.toStringAsFixed(2).replaceAll('.', ',');
    if (delta > 0) {
      return '+${CalculationEngine.formatGrams(delta)} г жидкости · плотность ×$factor';
    }
    return '−${CalculationEngine.formatGrams(-delta / rawGrams * 100)}\u202F% массы · концентрация ×$factor';
  }

  String get description {
    if (needsYield) {
      return 'Без веса готового блюда расчёт показан только на всё блюдо; значения на 100 г и на порцию появятся после ввода веса.';
    }
    if (!hasBasis) {
      return 'Добавьте ингредиенты с положительным весом для расчёта на 100 г.';
    }
    if (!changed) {
      return 'Вес готового блюда совпадает с суммой нетто ингредиентов.';
    }
    final factor = concentration.toStringAsFixed(2).replaceAll('.', ',');
    if (delta > 0) {
      return 'Расчёт предполагает добавление воды или жидкости без БЖУ: плотность на 100 г снижена до ×$factor. Бульон, молоко или масло добавляйте отдельными ингредиентами.';
    }
    return 'Расчёт предполагает потерю влаги при готовке: плотность на 100 г выросла до ×$factor. Новые нутриенты не появляются — КБЖУ всего блюда не меняется.';
  }
}
