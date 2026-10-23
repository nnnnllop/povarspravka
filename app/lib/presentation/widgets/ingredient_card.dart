import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'nutrient_chip.dart';
import 'source_badge.dart';

/// Карточка сырого ингредиента блюда
/// Стиль: швейцарский минимализм, 1px граница, мягкие пастельные плашки макронутриентов.
class IngredientCard extends StatelessWidget {
  final int index;
  final Ingredient ingredient;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const IngredientCard({
    super.key,
    required this.index,
    required this.ingredient,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final formattedIndex = index.toString().padLeft(2, '0');
    final netGramsStr = CalculationEngine.formatGrams(ing.netGramsRounded);
    final grossGramsStr = CalculationEngine.formatGrams(ing.weightGrams);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Верхняя строка: номер, название продукта, бейдж базы и кнопка удаления
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        formattedIndex,
                        style: AppTypography.numericSmall.copyWith(
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ing.product.name,
                        style: AppTypography.titleMedium.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: 'Удалить ингредиент',
                      onPressed: onDelete,
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Вторая строка: источник (Скурихин/USDA) и цепочка веса (брутто -> отходы -> нетто)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SourceBadge(source: ing.product.source, compact: true),
                    if (ing.isGross) ...[
                      Text(
                        'Брутто: $grossGramsStr г',
                        style: AppTypography.numericSmall.copyWith(
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                      Text(
                        '→',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                      Text(
                        '−${CalculationEngine.formatWastePercent(ing.product.wastePct)}% отх.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.accentLight : AppColors.accent,
                        ),
                      ),
                      Text(
                        '→',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Нетто: $netGramsStr г',
                        style: AppTypography.numeric.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Третья строка: пастельные плашки макронутриентов
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    NutrientChip(
                      type: NutrientType.protein,
                      value: CalculationEngine.formatMacro(ing.proteinInDish),
                      compact: true,
                    ),
                    NutrientChip(
                      type: NutrientType.fat,
                      value: CalculationEngine.formatMacro(ing.fatInDish),
                      compact: true,
                    ),
                    NutrientChip(
                      type: NutrientType.carbs,
                      value: CalculationEngine.formatMacro(ing.carbsInDish),
                      compact: true,
                    ),
                    NutrientChip(
                      type: NutrientType.kcal,
                      value: CalculationEngine.formatKcal(ing.blankKcalInDish),
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
