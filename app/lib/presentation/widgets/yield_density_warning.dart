import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Мягкое неблокирующее предупреждение (A3-INPUT-01), когда указанный выход
/// меньше массы Б/Ж/У после тепловой обработки и расчёт на 100 г превысил 100 г.
class YieldDensityWarning extends StatelessWidget {
  final CalculationResult result;

  const YieldDensityWarning({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final cookedMacroMass = CalculationMath.sumRounded(
      [result.cookedProtein, result.cookedFat, result.cookedCarbs],
      2,
    );
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: p.warningSoft,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: p.warning.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: p.warning,
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Вес готового блюда (${CalculationEngine.formatGrams(result.yieldGrams)} г) '
              'меньше массы Б/Ж/У после т.о. (${CalculationEngine.formatMacro(cookedMacroMass)} г): '
              'значения на 100 г превышают 100 г. Вес сохранён как введено — '
              'проверьте выход готового блюда.',
              style: AppTypography.bodySm.copyWith(
                color: p.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
