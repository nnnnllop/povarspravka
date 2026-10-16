import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class MacroSummaryBar extends StatefulWidget {
  final CalculationResult result;

  const MacroSummaryBar({
    super.key,
    required this.result,
  });

  @override
  State<MacroSummaryBar> createState() => _MacroSummaryBarState();
}

class _MacroSummaryBarState extends State<MacroSummaryBar> {
  bool _showPer100g = false;

  @override
  Widget build(BuildContext context) {
    final res = widget.result;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final proteinVal = _showPer100g ? res.per100gProtein : res.cookedProtein;
    final fatVal = _showPer100g ? res.per100gFat : res.cookedFat;
    final carbsVal = _showPer100g ? res.per100gCarbs : res.cookedCarbs;
    final kcalVal = _showPer100g ? res.per100gKcal : res.cookedKcal;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Заголовок и переключатель режима "В блюде / На 100 г"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showPer100g
                        ? 'Пищевая ценность на 100 г'
                        : 'Итого после т.о. (${CalculationEngine.formatGrams(res.yieldGrams)} г)',
                    style: AppTypography.titleMedium.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() => _showPer100g = !_showPer100g),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showPer100g ? 'В 100 г' : 'В блюде',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Четыре карточки КБЖУ
          Row(
            children: [
              _buildMacroItem(
                label: 'Белки',
                short: 'Б',
                value: CalculationEngine.formatMacro(proteinVal),
                unit: 'г',
                color: AppColors.protein,
                bgColor: AppColors.proteinLight,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildMacroItem(
                label: 'Жиры',
                short: 'Ж',
                value: CalculationEngine.formatMacro(fatVal),
                unit: 'г',
                color: AppColors.fat,
                bgColor: AppColors.fatLight,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildMacroItem(
                label: 'Углеводы',
                short: 'У',
                value: CalculationEngine.formatMacro(carbsVal),
                unit: 'г',
                color: AppColors.carbs,
                bgColor: AppColors.carbsLight,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildMacroItem(
                label: 'Калории',
                short: 'ЭЦ',
                value: CalculationEngine.formatKcal(kcalVal),
                unit: 'ккал',
                color: AppColors.kcal,
                bgColor: AppColors.kcalLight,
                isDark: isDark,
                isPrimary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroItem({
    required String label,
    required String short,
    required String value,
    required String unit,
    required Color color,
    required Color bgColor,
    required bool isDark,
    bool isPrimary = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.12) : bgColor.withOpacity(0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: isPrimary ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    short,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.numericLarge.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
            Text(
              unit,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 9,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
