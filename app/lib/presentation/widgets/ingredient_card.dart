import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'source_badge.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ing = ingredient;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Иконка перетаскивания
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color:
                      isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                ),
                const SizedBox(width: 4),

                // Номер п/п
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.cardDark
                        : AppColors.backgroundLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Text(
                    '$index',
                    style: AppTypography.numericSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Название и теги (Wrap для защиты от переполнения на узких экранах)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ing.product.name,
                              style: AppTypography.titleMedium.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SourceBadge(source: ing.product.source, compact: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          _buildMacroChip(
                            'Б: ${CalculationEngine.formatMacro(ing.proteinInDish)}г',
                            AppColors.protein,
                          ),
                          _buildMacroChip(
                            'Ж: ${CalculationEngine.formatMacro(ing.fatInDish)}г',
                            AppColors.fat,
                          ),
                          _buildMacroChip(
                            'У: ${CalculationEngine.formatMacro(ing.carbsInDish)}г',
                            AppColors.carbs,
                          ),
                          _buildMacroChip(
                            '${CalculationEngine.formatKcal(ing.blankKcalInDish)} ккал',
                            AppColors.kcal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Масса продукта
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Text(
                        '${CalculationEngine.formatGrams(ing.netGramsRounded)} г',
                        style: AppTypography.numeric.copyWith(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (ing.isGross)
                      Text(
                        'брутто ${CalculationEngine.formatGrams(ing.weightGrams)}г',
                        style: AppTypography.bodySmall.copyWith(fontSize: 10),
                      ),
                  ],
                ),

                // Кнопка удаления
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color:
                      isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMacroChip(String text, Color color) {
    return Text(
      text,
      style: AppTypography.numericSmall.copyWith(
        fontSize: 10,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
