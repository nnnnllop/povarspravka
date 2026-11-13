import 'package:flutter/material.dart';
import '../../core/calculation/models/source_label.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Источник справочника: **нейтральный контур + слово**, никогда не цвет
/// макроса.
///
/// Раньше `badgeSkurikhin == fatTextLight` (#8C5815 на #FAF3E8) и
/// `badgeUsda == carbsTextLight` (#244F7D на #EEF3F9) — то есть «Скурихин»
/// выглядел как «жиры», а второй источник как «углеводы». Коллизия снята: оба
/// источника живут на `sourceInk` / `sourceLine`, различаются иконкой и
/// словом. API не изменён.
///
/// Третий источник — `supplement` (приправы и вода, которых нет ни в книге,
/// ни в BLS): он подписывается «Дополнено», а не «BLS», иначе пользователь
/// решил бы, что сода и корица пришли из Bundeslebensmittelschlüssel.
class SourceBadge extends StatelessWidget {
  final String source;
  final bool compact;

  const SourceBadge({
    super.key,
    required this.source,
    this.compact = false,
  });

  /// Единая подпись источника (дефект D17): тот же словарь `SourceLabel`,
  /// что и у `Product.sourceLabel`, — не копия switch'а. Для неизвестного
  /// источника возвращается сам код: на бейдже пустая подпись смотрелась бы
  /// как дефект вёрстки.
  static String labelFor(String source) =>
      SourceLabel.of(source, fallback: source);

  static IconData iconFor(String source) {
    switch (source.toLowerCase()) {
      case 'skurikhin':
        return Icons.menu_book_rounded;
      case 'bls':
        return Icons.public_rounded;
      default:
        return Icons.add_circle_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final label = labelFor(source);

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
            iconFor(source),
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
