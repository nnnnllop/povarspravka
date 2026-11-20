import 'package:flutter/material.dart';

import '../../core/calculation/macro_balance.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Компактная полоска энергетического баланса Б / Ж / У (% ккал) и соотношения.
class MacroBalanceBar extends StatelessWidget {
  final MacroBalance balance;
  final bool compact;

  const MacroBalanceBar({
    super.key,
    required this.balance,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!balance.hasEnergy) return const SizedBox.shrink();
    final p = Palette.of(context);
    final segments = <(int pct, Color color, String label)>[
      (balance.proteinPct, p.protein, 'Белки ${balance.proteinPct} %'),
      (balance.fatPct, p.fat, 'Жиры ${balance.fatPct} %'),
      (balance.carbsPct, p.carbs, 'Углеводы ${balance.carbsPct} %'),
    ];
    final ratio = balance.ratioLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final seg in segments)
                  if (seg.$1 > 0)
                    Expanded(
                      flex: seg.$1,
                      child: Container(color: seg.$2),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x3,
          runSpacing: Space.x1,
          children: [
            for (final seg in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: seg.$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      seg.$3,
                      style:
                          (compact ? AppTypography.caption : AppTypography.numSm)
                              .copyWith(color: p.ink),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (!compact && ratio != null) ...[
          const SizedBox(height: Space.x1),
          Text(
            'Соотношение Б : Ж : У = $ratio',
            style: AppTypography.caption.copyWith(color: p.inkSecondary),
          ),
        ],
      ],
    );
  }
}
