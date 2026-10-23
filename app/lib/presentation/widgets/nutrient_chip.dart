import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

enum NutrientType {
  protein,
  fat,
  carbs,
  kcal,
}

/// Чистая пастельная плашка макронутриента
/// Создана по канонам минимализма: мягкий фон, контрастный читаемый текст,
/// моноширинные табличные цифры (tabular figures).
class NutrientChip extends StatelessWidget {
  final NutrientType type;
  final String value;
  final String? labelOverride;
  final bool compact;
  final Key? valueKey;

  const NutrientChip({
    super.key,
    required this.type,
    required this.value,
    this.labelOverride,
    this.compact = false,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color text;
    final Color border;
    final String label;
    final String unit;

    switch (type) {
      case NutrientType.protein:
        label = labelOverride ?? 'Б';
        unit = 'г';
        bg = isDark ? AppColors.proteinBgDark : AppColors.proteinBgLight;
        text = isDark ? AppColors.proteinTextDark : AppColors.proteinTextLight;
        border = isDark ? AppColors.proteinBorderDark : AppColors.proteinBorderLight;
        break;
      case NutrientType.fat:
        label = labelOverride ?? 'Ж';
        unit = 'г';
        bg = isDark ? AppColors.fatBgDark : AppColors.fatBgLight;
        text = isDark ? AppColors.fatTextDark : AppColors.fatTextLight;
        border = isDark ? AppColors.fatBorderDark : AppColors.fatBorderLight;
        break;
      case NutrientType.carbs:
        label = labelOverride ?? 'У';
        unit = 'г';
        bg = isDark ? AppColors.carbsBgDark : AppColors.carbsBgLight;
        text = isDark ? AppColors.carbsTextDark : AppColors.carbsTextLight;
        border = isDark ? AppColors.carbsBorderDark : AppColors.carbsBorderLight;
        break;
      case NutrientType.kcal:
        label = labelOverride ?? 'ккал';
        unit = labelOverride != null ? 'ккал' : '';
        bg = isDark ? AppColors.kcalBgDark : AppColors.kcalBgLight;
        text = isDark ? AppColors.kcalTextDark : AppColors.kcalTextLight;
        border = isDark ? AppColors.kcalBorderDark : AppColors.kcalBorderLight;
        break;
    }

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: text.withOpacity(0.85),
              ),
            ),
            Text(
              valueKey != null ? value : (unit.isNotEmpty && !value.endsWith(unit) ? '$value $unit' : value),
              key: valueKey,
              style: AppTypography.numericSmall.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: text.withOpacity(0.85),
            ),
          ),
          Text(
            unit.isNotEmpty && !value.endsWith(unit) ? '$value $unit' : value,
            key: valueKey,
            style: AppTypography.numeric.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}
