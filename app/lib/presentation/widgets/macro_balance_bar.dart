import 'package:flutter/material.dart';

import '../../core/calculation/macro_balance.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Компактная полоска энергетического баланса Б / Ж / У (% ккал) и соотношения.
class MacroBalanceBar extends StatelessWidget {
  final MacroBalance balance;
  final bool compact;
  final bool barOnly;
  final double barHeight;
  final bool onDarkSlab;

  const MacroBalanceBar({
    super.key,
    required this.balance,
    this.compact = false,
    this.barOnly = false,
    this.barHeight = 8,
    this.onDarkSlab = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!balance.hasEnergy) return const SizedBox.shrink();
    final p = Palette.of(context);
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final cProtein = onDarkSlab ? p.slabProtein : p.protein;
    final cFat = onDarkSlab ? p.slabFat : p.fat;
    final cCarbs = onDarkSlab ? p.slabCarbs : p.carbs;
    final segments = <(int pct, Color color, String label)>[
      (balance.proteinPct, cProtein, 'Белки ${balance.proteinPct} %'),
      (balance.fatPct, cFat, 'Жиры ${balance.fatPct} %'),
      (balance.carbsPct, cCarbs, 'Углеводы ${balance.carbsPct} %'),
    ];
    final active = [
      for (final seg in segments)
        if (seg.$1 > 0) seg,
    ];

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(barHeight / 2),
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (int i = 0; i < active.length; i++) ...[
              if (i > 0 && barHeight >= 6) const SizedBox(width: 1.5),
              Expanded(
                flex: active[i].$1,
                child: AnimatedContainer(
                  duration: disableAnimations ? Duration.zero : Motion.base,
                  curve: Motion.ease,
                  color: active[i].$2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (barOnly) return bar;
    final ratio = balance.ratioLabel;
    final textColor = onDarkSlab ? p.slabInk : p.ink;
    final secondaryColor = onDarkSlab ? p.slabSecondary : p.inkSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
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
                    width: 6,
                    height: 6,
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
                              .copyWith(color: textColor),
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
            style: AppTypography.caption.copyWith(color: secondaryColor),
          ),
        ],
      ],
    );
  }
}
