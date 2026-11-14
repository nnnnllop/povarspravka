import 'package:flutter/material.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Неблокирующий баннер ошибки сохранения на диск с кнопкой повтора.
class PersistenceErrorBanner extends StatefulWidget {
  final Future<bool> Function() onRetry;
  final EdgeInsetsGeometry margin;
  final String message;

  const PersistenceErrorBanner({
    super.key,
    required this.onRetry,
    this.margin = EdgeInsets.zero,
    this.message = 'Ошибка сохранения: изменения не сохранены на диск',
  });

  @override
  State<PersistenceErrorBanner> createState() => _PersistenceErrorBannerState();
}

class _PersistenceErrorBannerState extends State<PersistenceErrorBanner> {
  bool _retrying = false;

  Future<void> _handleRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('persistence-error-banner'),
        width: double.infinity,
        margin: widget.margin,
        padding:
            const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, Space.x1),
        decoration: BoxDecoration(
          color: p.dangerSoft,
          borderRadius: Radii.cardAll,
          border: Border.all(color: p.danger.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.cloud_off, color: p.danger, size: 20),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    widget.message,
                    style: AppTypography.caption.copyWith(
                      color: p.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('persistence-error-retry'),
                onPressed: _retrying ? null : _handleRetry,
                style: TextButton.styleFrom(
                  foregroundColor: p.danger,
                  minimumSize: const Size(0, kMinTapTarget),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                icon: _retrying
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.danger,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_retrying ? 'Повтор…' : 'Повторить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
