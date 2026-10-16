import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

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
    final isSkurikhin = source.toLowerCase() == 'skurikhin';
    final label = isSkurikhin ? 'Скурихин' : 'USDA';
    final textColor = isSkurikhin ? AppColors.badgeSkurikhin : AppColors.badgeUsda;
    final bgColor = isSkurikhin ? AppColors.badgeSkurikhinBg : AppColors.badgeUsdaBg;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: textColor.withOpacity(0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSkurikhin ? Icons.menu_book_rounded : Icons.public_rounded,
            size: compact ? 10 : 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
