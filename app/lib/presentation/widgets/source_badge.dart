import 'package:flutter/material.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Источник справочника: **нейтральный контур + слово**, никогда не цвет
/// макроса.
///
/// Раньше `badgeSkurikhin == fatTextLight` (#8C5815 на #FAF3E8) и
/// `badgeUsda == carbsTextLight` (#244F7D на #EEF3F9) — то есть «Скурихин»
/// выглядел как «жиры», а «USDA» как «углеводы». Коллизия снята: оба
/// источника живут на `sourceInk` / `sourceLine`, различаются иконкой и
/// словом. API не изменён.
class SourceBadge extends StatelessWidget {
  final String source;
  final bool compact;

  const SourceBadge({
    super.key,
    required this.source,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final isSkurikhin = source.toLowerCase() == 'skurikhin';
    final label = isSkurikhin ? 'Скурихин' : 'USDA';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: Radii.chipAll,
        border: Border.all(color: p.sourceLine, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSkurikhin ? Icons.menu_book_rounded : Icons.public_rounded,
            size: compact ? 12 : 14,
            color: p.sourceInk,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w400,
              color: p.sourceInk,
            ),
          ),
        ],
      ),
    );
  }
}
