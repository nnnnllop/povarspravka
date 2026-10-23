import 'package:flutter/material.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

enum NutrientType {
  protein,
  fat,
  carbs,
  kcal,
}

/// Показатель макронутриента: **текст + 2-dp маркер**, без цветной плашки.
///
/// Правило R2 аудита: ни одной заливки цветом-акцентом площадью > 48 dp².
/// Пастельные плашки БЖУ в каждой карточке (4 цветные заливки × 8 ингредиентов
/// = 32 пятна) и были тем самым «визуальным дребезгом». Цвет остаётся ровно
/// там, где он несёт смысл: тонкий маркер слева и цвет цифры.
///
/// API не изменён (`type`, `value`, `compact`, `labelOverride`, `valueKey`) —
/// все вызывающие места и тестовые ключи (`macro-Белки`, `macro-Энергия`)
/// продолжают работать.
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
    final p = Palette.of(context);

    final Color tint;
    final String label;
    final String unit;

    switch (type) {
      case NutrientType.protein:
        label = labelOverride ?? 'Б';
        unit = 'г';
        tint = p.protein;
        break;
      case NutrientType.fat:
        label = labelOverride ?? 'Ж';
        unit = 'г';
        tint = p.fat;
        break;
      case NutrientType.carbs:
        label = labelOverride ?? 'У';
        unit = 'г';
        tint = p.carbs;
        break;
      case NutrientType.kcal:
        label = labelOverride ?? 'ккал';
        unit = labelOverride != null ? 'ккал' : '';
        tint = p.kcal;
        break;
    }

    final text = unit.isNotEmpty && !value.endsWith(unit) ? '$value $unit' : value;
    final markerHeight = compact ? 12.0 : 14.0;

    return Semantics(
      label: '$label $text',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 2-dp маркер: единственный носитель цвета макроса.
          Container(
            width: 2,
            height: markerHeight,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          SizedBox(width: compact ? 5 : 6),
          Text(
            '$label ',
            style: (compact ? AppTypography.caption : AppTypography.label)
                .copyWith(color: p.inkMuted),
          ),
          Text(
            text,
            key: valueKey,
            style: (compact ? AppTypography.numSm : AppTypography.num).copyWith(
              color: p.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
