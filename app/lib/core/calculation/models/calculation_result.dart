import 'blank_mode.dart';
import 'heat_process.dart';
import 'loss_group.dart';
import '../calculation_math.dart';
import '../calculation_validation.dart';
import '../loss_table.dart';

/// Расчёт потерь одного ингредиента: что применено и почему.
///
/// Нужен экрану (повар видит группу и способ каждого продукта и может
/// их поменять) и тестам. Для [HeatProcess.legacy] строк нет: там действует
/// одна тройка на всё блюдо.
class IngredientLossLine {
  const IngredientLossLine({
    required this.ingredientId,
    required this.group,
    required this.groupIsManual,
    required this.process,
    required this.processIsManual,
    required this.loss,
    required this.rawProtein,
    required this.rawFat,
    required this.rawCarbs,
    required this.cookedProtein,
    required this.cookedFat,
    required this.cookedCarbs,
    this.productName = '',
  });

  final String ingredientId;

  /// Название продукта (для инспектора расчёта).
  final String productName;

  /// Группа таблицы потерь (выбор повара или классификатор).
  final LossGroup group;

  /// Группу выбрал повар (`Ingredient.groupOverride`).
  final bool groupIsManual;

  /// Способ обработки, по которому взяты потери.
  final HeatProcess process;

  /// Способ задан для ингредиента вручную (`Ingredient.processOverride`).
  final bool processIsManual;

  /// Применённые потери, % (со ссылкой на источник).
  final NutrientLoss loss;

  /// Б/Ж/У сырья в блюде, г (как в бланке, до 0,01 г).
  final double rawProtein;
  final double rawFat;
  final double rawCarbs;

  /// Б/Ж/У после тепловой обработки, г: `сырьё × (100 − потери) / 100`,
  /// HALF-UP до 0,01 г.
  final double cookedProtein;
  final double cookedFat;
  final double cookedCarbs;

  /// Энергия после обработки, ккал: 4Б + 9Ж + 4У.
  double get cookedKcal =>
      CalculationMath.energy(cookedProtein, cookedFat, cookedCarbs);
}

class CalculationResult {
  final BlankMode blankMode;

  /// Вес готового блюда, г. `0` — повар вес не указал (для способа,
  /// отличного от legacy): итог считается на всё блюдо, «на 100 г» и
  /// «на порцию» не определены ([hasYield]).
  final double yieldGrams;

  // ИТОГО (сырье)
  final double rawTotalWeight;
  final double rawTotalProtein;
  final double rawTotalFat;
  final double rawTotalCarbs;
  final double?
      rawTotalKcal; // null в режиме photoCross (на строке "ИТОГО" стоит прочерк/крест)

  /// Способ обработки блюда, по которому выполнен расчёт.
  final HeatProcess process;

  /// Сохранность Б/Ж/У (доля 0…1).
  ///
  /// [HeatProcess.legacy] — тройка блюда (например, 0.94 / 0.88 / 0.91).
  /// Иначе — ИТОГОВАЯ доля `готовое / сырьё` (до 0,0001) по строкам таблицы
  /// потерь; только для отображения, в расчёте не участвует.
  final double retentionProtein;
  final double retentionFat;
  final double retentionCarbs;

  /// Потери по ингредиентам; пусто для [HeatProcess.legacy].
  final List<IngredientLossLine> lines;

  // После тепловой обработки — на всё блюдо
  final double cookedProtein;
  final double cookedFat;
  final double cookedCarbs;
  final double cookedKcal; // Б*4 + Ж*9 + У*4

  // В 100 г блюда (0, если вес готового блюда не указан — см. [hasYield])
  final double per100gProtein;
  final double per100gFat;
  final double per100gCarbs;
  final double per100gKcal;

  /// Вес готового блюда известен: значения «на 100 г» и «на порцию»
  /// определены. Иначе экран показывает итог на всё блюдо и просит
  /// указать вес готового блюда.
  bool get hasYield => yieldGrams > 0;

  /// Потери взяты из таблицы по группам ингредиентов (не legacy).
  bool get usesLossTable => !process.isLegacy;

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
    this.process = HeatProcess.legacy,
    this.lines = const [],
  });
}
