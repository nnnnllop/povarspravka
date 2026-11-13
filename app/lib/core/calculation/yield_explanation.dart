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
    if (!changed) return 'Выход равен сумме нетто';
    final factor = concentration.toStringAsFixed(2).replaceAll('.', ',');
    if (delta > 0)
      return '+${CalculationEngine.formatGrams(delta)} г жидкости • разбавление ×$factor';
    return '−${CalculationEngine.formatGrams(-delta / rawGrams * 100)}% уварка • концентрация ×$factor';
  }

  String get description {
    if (needsYield)
      return 'Укажите вес готового блюда: без него пищевая ценность показана на всё блюдо, а «на 100 г» и «на порцию» не рассчитываются. Приложение вес готового блюда не угадывает.';
    if (!hasBasis)
      return 'Добавьте ингредиенты с положительным весом для расчёта на 100 г.';
    if (!changed)
      return 'Без поправки на изменение массы: выход равен сумме нетто ингредиентов.';
    if (delta > 0)
      return 'Расчёт предполагает добавление воды или жидкости без БЖУ. Концентрация на 100 г снижена в ${CalculationEngine.formatMacro(1 / concentration)} раза. Если добавлен бульон, молоко или масло, внесите их отдельными ингредиентами. По одному выходу нельзя определить состав добавки.';
    return 'Расчёт предполагает уварку / испарение влаги. Концентрация на 100 г возросла в ${CalculationEngine.formatMacro(concentration)} раза. Нутриенты не появляются: общее БЖУ после т.о. не меняется при изменении выхода.';
  }
}
