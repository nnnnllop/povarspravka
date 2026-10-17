import 'blank_mode.dart';
import '../calculation_math.dart';
import '../calculation_validation.dart';

class CalculationResult {
  final BlankMode blankMode;
  final double yieldGrams;

  // ИТОГО (сырье)
  final double rawTotalWeight;
  final double rawTotalProtein;
  final double rawTotalFat;
  final double rawTotalCarbs;
  final double?
      rawTotalKcal; // null в режиме photoCross (на строке "ИТОГО" стоит прочерк/крест)

  // После тепловой обработки
  final double retentionProtein; // например 0.94
  final double retentionFat; // например 0.88
  final double retentionCarbs; // например 0.91

  final double cookedProtein;
  final double cookedFat;
  final double cookedCarbs;
  final double cookedKcal; // Б*4 + Ж*9 + У*4

  // В 100 г блюда
  final double per100gProtein;
  final double per100gFat;
  final double per100gCarbs;
  final double per100gKcal;

  ({double protein, double fat, double carbs, double kcal}) portion(
      double grams) {
    CalculationValidation.range(grams, .1, 9999999, 'portionGrams');
    if (yieldGrams <= 0)
      throw StateError('A portion requires positive dish yield');
    return (
      protein: CalculationMath.ratioRounded(cookedProtein, yieldGrams, 2,
          multiplier: grams),
      fat: CalculationMath.ratioRounded(cookedFat, yieldGrams, 2,
          multiplier: grams),
      carbs: CalculationMath.ratioRounded(cookedCarbs, yieldGrams, 2,
          multiplier: grams),
      kcal: CalculationMath.ratioRounded(cookedKcal, yieldGrams, 1,
          multiplier: grams),
    );
  }

  const CalculationResult({
    required this.blankMode,
    required this.yieldGrams,
    required this.rawTotalWeight,
    required this.rawTotalProtein,
    required this.rawTotalFat,
    required this.rawTotalCarbs,
    this.rawTotalKcal,
    required this.retentionProtein,
    required this.retentionFat,
    required this.retentionCarbs,
    required this.cookedProtein,
    required this.cookedFat,
    required this.cookedCarbs,
    required this.cookedKcal,
    required this.per100gProtein,
    required this.per100gFat,
    required this.per100gCarbs,
    required this.per100gKcal,
  });
}
