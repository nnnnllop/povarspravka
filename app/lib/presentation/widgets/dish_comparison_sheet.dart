import 'package:flutter/material.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/macro_balance.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';
import 'instrument_widgets.dart';
import 'macro_balance_bar.dart';

/// Шторка сравнения двух блюд: по 100 г или целиком, с разницей (Δ) и балансом Б/Ж/У.
class DishComparisonSheet extends StatefulWidget {
  final Dish first;
  final Dish second;

  const DishComparisonSheet({
    super.key,
    required this.first,
    required this.second,
  });

  static Future<void> show(
    BuildContext context, {
    required Dish first,
    required Dish second,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => DishComparisonSheet(first: first, second: second),
    );
  }

  @override
  State<DishComparisonSheet> createState() => _DishComparisonSheetState();
}

class _DishComparisonSheetState extends State<DishComparisonSheet> {
  late final CalculationResult? _calcA;
  late final CalculationResult? _calcB;
  late bool _wholeDish;

  @override
  void initState() {
    super.initState();
    _calcA = CalculationEngine.tryCalculate(widget.first);
    _calcB = CalculationEngine.tryCalculate(widget.second);
    final bothHaveYield = (_calcA?.hasYield ?? false) && (_calcB?.hasYield ?? false);
    _wholeDish = !bothHaveYield;
  }

  String _dishName(Dish d, String fallback) {
    final t = d.title.trim();
    return t.isEmpty ? fallback : t;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackRows = size.width < 360 || textScale > 1.35;
    final nameA = _dishName(widget.first, 'Блюдо 1');
    final nameB = _dishName(widget.second, 'Блюдо 2');
    final a = _calcA;
    final b = _calcB;

    String fmtVal(double? val, String Function(double) fmt) =>
        val == null ? '—' : fmt(val);

    String fmtDelta(double? va, double? vb, String Function(double) fmt) {
      if (va == null || vb == null) return '—';
      final diff = vb - va;
      if (diff.abs() < 0.005) return '0';
      final sign = diff > 0 ? '+' : '−';
      return '$sign${fmt(diff.abs())}';
    }

    Color deltaColor(double? va, double? vb) {
      if (va == null || vb == null) return p.inkMuted;
      final diff = vb - va;
      if (diff.abs() < 0.005) return p.inkSecondary;
      return diff > 0 ? p.accent : p.ink;
    }

    double? pickMetric(CalculationResult? r, double Function(CalculationResult) whole,
        double Function(CalculationResult) per100) {
      if (r == null) return null;
      if (_wholeDish) return whole(r);
      return r.hasYield ? per100(r) : null;
    }

    final rows = <(
      String label,
      double? aVal,
      double? bVal,
      String Function(double) fmt,
    )>[
      (
        'Энергия, ккал',
        pickMetric(a, (r) => r.cookedKcal, (r) => r.per100gKcal),
        pickMetric(b, (r) => r.cookedKcal, (r) => r.per100gKcal),
        CalculationEngine.formatKcal,
      ),
      (
        'Белки, г',
        pickMetric(a, (r) => r.cookedProtein, (r) => r.per100gProtein),
        pickMetric(b, (r) => r.cookedProtein, (r) => r.per100gProtein),
        CalculationEngine.formatMacro,
      ),
      (
        'Жиры, г',
        pickMetric(a, (r) => r.cookedFat, (r) => r.per100gFat),
        pickMetric(b, (r) => r.cookedFat, (r) => r.per100gFat),
        CalculationEngine.formatMacro,
      ),
      (
        'Углеводы, г',
        pickMetric(a, (r) => r.cookedCarbs, (r) => r.per100gCarbs),
        pickMetric(b, (r) => r.cookedCarbs, (r) => r.per100gCarbs),
        CalculationEngine.formatMacro,
      ),
      (
        'Выход, г',
        (a != null && a.hasYield) ? a.yieldGrams : null,
        (b != null && b.hasYield) ? b.yieldGrams : null,
        CalculationEngine.formatGrams,
      ),
    ];

    final missingYieldInPer100 =
        !_wholeDish && (!(a?.hasYield ?? true) || !(b?.hasYield ?? true));

    return SizedBox(
      height: size.height * 0.88,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Сравнение блюд',
                style: AppTypography.title.copyWith(color: p.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Разница (Δ) показана для второго блюда относительно первого.',
                style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: Space.x2),
              SegmentedButton<bool>(
                key: const ValueKey('compare-mode-segmented'),
                showSelectedIcon: false,
                style: AppSegmentedStyle.of(p, compact: true),
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text('На 100 г')),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('На всё блюдо'),
                    ),
                  ),
                ],
                selected: {_wholeDish},
                onSelectionChanged: (sel) {
                  if (sel.isEmpty) return;
                  AppHaptics.toggle();
                  setState(() => _wholeDish = sel.first);
                },
              ),
              if (a == null || b == null) ...[
                const SizedBox(height: Space.x3),
                Container(
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(
                    color: p.dangerSoft,
                    borderRadius: Radii.fieldAll,
                  ),
                  child: Text(
                    'Одно из блюд содержит ошибку расчёта — значения отмечены прочерком.',
                    style: AppTypography.caption.copyWith(color: p.danger),
                  ),
                ),
              ],
              if (missingYieldInPer100) ...[
                const SizedBox(height: Space.x2),
                Text(
                  'Для блюда без указанного выхода значения на 100 г отмечены «—».',
                  style: AppTypography.caption.copyWith(color: p.inkSecondary),
                ),
              ],
              const SizedBox(height: Space.x3),
              GroupedSurface(
                color: p.sunken,
                padding: const EdgeInsets.all(Space.x3 + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!stackRows) ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Показатель',
                              style: AppTypography.caption
                                  .copyWith(color: p.inkMuted),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              nameA,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              nameB,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Δ',
                              textAlign: TextAlign.right,
                              style: AppTypography.caption.copyWith(
                                color: p.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(color: p.divider, height: Space.x3),
                    ],
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) Divider(color: p.divider, height: Space.x3),
                      if (stackRows)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].$1,
                              style: AppTypography.label.copyWith(color: p.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$nameA: ${fmtVal(rows[i].$2, rows[i].$4)}',
                              style: AppTypography.numSm
                                  .copyWith(color: p.inkSecondary),
                            ),
                            Text(
                              '$nameB: ${fmtVal(rows[i].$3, rows[i].$4)} '
                              '(Δ ${fmtDelta(rows[i].$2, rows[i].$3, rows[i].$4)})',
                              style: AppTypography.numSm.copyWith(
                                color: deltaColor(rows[i].$2, rows[i].$3),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                rows[i].$1,
                                style: AppTypography.bodySm.copyWith(color: p.ink),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                fmtVal(rows[i].$2, rows[i].$4),
                                textAlign: TextAlign.right,
                                style: AppTypography.numSm
                                    .copyWith(color: p.inkSecondary),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                fmtVal(rows[i].$3, rows[i].$4),
                                textAlign: TextAlign.right,
                                style: AppTypography.numSm.copyWith(
                                  color: p.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                fmtDelta(rows[i].$2, rows[i].$3, rows[i].$4),
                                textAlign: TextAlign.right,
                                style: AppTypography.numSm.copyWith(
                                  color: deltaColor(rows[i].$2, rows[i].$3),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
              if (a != null && a.cookedKcal > 0) ...[
                const SizedBox(height: Space.x4),
                Text(
                  nameA,
                  style: AppTypography.label.copyWith(color: p.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.x2),
                MacroBalanceBar(
                  balance: MacroBalance.fromMacros(
                    protein: a.cookedProtein,
                    fat: a.cookedFat,
                    carbs: a.cookedCarbs,
                  ),
                ),
              ],
              if (b != null && b.cookedKcal > 0) ...[
                const SizedBox(height: Space.x3),
                Text(
                  nameB,
                  style: AppTypography.label.copyWith(color: p.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.x2),
                MacroBalanceBar(
                  balance: MacroBalance.fromMacros(
                    protein: b.cookedProtein,
                    fat: b.cookedFat,
                    carbs: b.cookedCarbs,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
