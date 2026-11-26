import 'package:flutter/material.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

enum NutrientType {
  protein,
  fat,
  carbs,
  kcal;

  /// Короткая подпись для строчных ячеек («Б», «Ж», «У», «ккал»).
  String get shortLabel => switch (this) {
        NutrientType.protein => 'Б',
        NutrientType.fat => 'Ж',
        NutrientType.carbs => 'У',
        NutrientType.kcal => 'ккал',
      };

  /// Полная подпись для итогов и скринридера.
  String get fullLabel => switch (this) {
        NutrientType.protein => 'Белки',
        NutrientType.fat => 'Жиры',
        NutrientType.carbs => 'Углеводы',
        NutrientType.kcal => 'Энергия',
      };

  /// Единица измерения по умолчанию.
  String get defaultUnit => this == NutrientType.kcal ? 'ккал' : 'г';

  /// Семантический цвет из [Palette].
  Color tintOf(Palette p) => switch (this) {
        NutrientType.protein => p.protein,
        NutrientType.fat => p.fat,
        NutrientType.carbs => p.carbs,
        NutrientType.kcal => p.kcal,
      };
}

/// Показатель макронутриента: **текст + цветовой акцент**, без цветной плашки.
///
/// Правило R2 аудита: ни одной заливки цветом-акцентом площадью > 48 dp².
/// API сохранён (`type`, `value`, `compact`, `labelOverride`, `valueKey`) —
/// все вызывающие места и тестовые ключи (`macro-Белки`, `macro-Энергия`)
/// продолжают работать.
class NutrientChip extends StatelessWidget {
  final NutrientType type;
  final String value;
  final String? labelOverride;
  final bool compact;
  final Key? valueKey;
  final bool showUnit;
  final bool stacked;
  final bool muted;
  final bool onDarkSlab;
  final double dotSize;

  const NutrientChip({
    super.key,
    required this.type,
    required this.value,
    this.labelOverride,
    this.compact = false,
    this.valueKey,
    this.showUnit = true,
    this.stacked = false,
    this.muted = false,
    this.onDarkSlab = false,
    this.dotSize = 6,
  });

  @override
  Widget build(BuildContext context) {
    final unit = !showUnit
        ? null
        : (type == NutrientType.kcal && labelOverride == null
            ? null
            : type.defaultUnit);
    return InlineMacroCell(
      type: type,
      label: labelOverride,
      value: value,
      unit: unit,
      stacked: stacked,
      compact: compact,
      muted: muted,
      onDarkSlab: onDarkSlab,
      dotSize: dotSize,
      valueKey: valueKey,
    );
  }
}

/// Универсальная типографическая ячейка макронутриента (без цветных плашек).
///
/// Объединяет строчный вид (`stacked: false`, например `Б 1,41`) и
/// двухстрочный вид итогов (`stacked: true`, например `Белки` / `1,41 г`)
/// с единой доступной семантикой (`Semantics(excludeSemantics: true)`),
/// сохраняя `valueKey` непосредственно на [Text] со значением.
class InlineMacroCell extends StatelessWidget {
  final NutrientType? type;
  final Color? tint;
  final String? label;
  final String value;
  final String? unit;
  final bool stacked;
  final bool compact;
  final bool muted;
  final bool onDarkSlab;
  final double dotSize;
  final Key? valueKey;
  final String? semanticsLabel;

  const InlineMacroCell({
    super.key,
    required NutrientType this.type,
    required this.value,
    this.label,
    this.unit,
    this.stacked = false,
    this.compact = false,
    this.muted = false,
    this.onDarkSlab = false,
    this.dotSize = 6,
    this.valueKey,
    this.semanticsLabel,
  }) : tint = null;

  const InlineMacroCell.custom({
    super.key,
    required Color this.tint,
    required String this.label,
    required this.value,
    this.unit,
    this.stacked = false,
    this.compact = false,
    this.muted = false,
    this.onDarkSlab = false,
    this.dotSize = 6,
    this.valueKey,
    this.semanticsLabel,
  }) : type = null;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final resolvedTint = tint ??
        (onDarkSlab
            ? switch (type!) {
                NutrientType.protein => p.slabProtein,
                NutrientType.fat => p.slabFat,
                NutrientType.carbs => p.slabCarbs,
                NutrientType.kcal => p.kcal,
              }
            : type!.tintOf(p));
    final showDot = type != NutrientType.kcal;
    final resolvedLabel = label ?? type!.shortLabel;
    final hasUnit =
        unit != null && unit!.isNotEmpty && !value.endsWith(unit!);
    final displayValue = hasUnit ? '$value $unit' : value;
    final valueColor = onDarkSlab
        ? (muted ? p.slabSecondary : p.slabInk)
        : (muted ? p.inkSecondary : p.ink);
    final labelColor = onDarkSlab ? p.slabSecondary : p.inkSecondary;
    final valueStyle =
        (compact ? AppTypography.numSm : AppTypography.num).copyWith(
      color: valueColor,
      fontWeight: type == NutrientType.kcal ? FontWeight.w700 : FontWeight.w600,
    );

    final a11yLabel =
        semanticsLabel ?? _defaultSemanticsLabel(resolvedLabel, displayValue);

    final valueText = Text(
      displayValue,
      key: valueKey,
      style: valueStyle,
    );

    final dotWidget = showDot
        ? Container(
            width: dotSize,
            height: dotSize,
            margin: const EdgeInsets.only(right: Space.x1),
            decoration: BoxDecoration(
              color: resolvedTint,
              shape: BoxShape.circle,
            ),
          )
        : null;

    final Widget content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dotWidget != null) dotWidget,
                  Text(
                    resolvedLabel,
                    style: AppTypography.caption.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              valueText,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (dotWidget != null) dotWidget,
              Text(
                '$resolvedLabel ',
                style: (compact ? AppTypography.caption : AppTypography.label)
                    .copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: valueText,
                ),
              ),
            ],
          );

    return Semantics(
      label: a11yLabel,
      excludeSemantics: true,
      child: content,
    );
  }

  String _defaultSemanticsLabel(String resolvedLabel, String displayValue) {
    if (type == null) return '$resolvedLabel $displayValue'.trim();
    final spokenTitle =
        (label == null || label == type!.shortLabel)
            ? type!.fullLabel
            : resolvedLabel;
    final needsUnit = (unit == null || unit!.isEmpty) &&
        !value.endsWith(type!.defaultUnit) &&
        value != '—';
    final spokenUnit = needsUnit ? ' ${type!.defaultUnit}' : '';
    return '$spokenTitle $displayValue$spokenUnit'.trim();
  }
}
