import 'package:flutter/material.dart';

import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Информационный баннер вместо Red Screen (аудит STATE-01).
///
/// Когда данные блюда невычислимы, приложение **не имеет права** ронять
/// дерево виджетов в `ErrorWidget`: повар видит понятное объяснение, может
/// вернуться и исправить выход, а остальные рецепты продолжают работать.
class CalcErrorBanner extends StatelessWidget {
  /// Пояснение от валидатора (если есть) — показывается второй строкой.
  final String? detail;

  const CalcErrorBanner({super.key, this.detail});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('calc-error-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
      padding:
          const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.kcal.withOpacity(0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_rounded, size: 20, color: p.kcal),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Проверьте выход и параметры блюда',
                  style: AppTypography.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: AppTypography.caption.copyWith(color: p.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Глобальная замена `ErrorWidget` (аудит STATE-01).
///
/// Любое непредвиденное исключение рендера показывает аккуратный экран с
/// понятным текстом вместо красной страницы с raw stack trace.
class FriendlyErrorPane extends StatelessWidget {
  const FriendlyErrorPane({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Material(
      color: p.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.soup_kitchen_rounded, size: 48, color: p.accent),
              const SizedBox(height: Space.x3),
              Text(
                'Не удалось показать этот экран',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: Space.x1),
              Text(
                message ?? 'Откройте другой расчёт — ваши рецепты сохранены.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(color: p.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
