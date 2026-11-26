import 'package:flutter/material.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/macro_balance.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
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
  bool _swapped = false;

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
    final stackRows =
        AppLayout.isNarrow(size.width) || AppLayout.isLargeText(textScale);
    final firstDish = _swapped ? widget.second : widget.first;
    final secondDish = _swapped ? widget.first : widget.second;
    final nameA = _dishName(firstDish, 'Блюдо 1');
    final nameB = _dishName(secondDish, 'Блюдо 2');
    final a = _swapped ? _calcB : _calcA;
    final b = _swapped ? _calcA : _calcB;

    String fmtVal(double? val, String Function(double) fmt) =>
        val == null ? '—' : fmt(val);

    String fmtDelta(double? va, double? vb, String Function(double) fmt) {
      if (va == null || vb == null) return '—';
      final diff = vb - va;
      final formatted = fmt(diff.abs());
      if (diff.abs() < 0.005 ||
          formatted == '0' ||
          formatted == '0,0' ||
          formatted == '0,00') {
        return '0';
      }
      final sign = diff > 0 ? '+' : '−';
      return '$sign$formatted';
    }

    Color deltaColor(double? va, double? vb, String Function(double) fmt) {
      if (va == null || vb == null) return p.inkMuted;
      final diff = vb - va;
      final formatted = fmt(diff.abs());
      if (diff.abs() < 0.005 ||
          formatted == '0' ||
          formatted == '0,0' ||
          formatted == '0,00') {
        return p.inkSecondary;
      }
      return p.ink;
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
        'Энергия, ккал',
        pickMetric(a, (r) => r.cookedKcal, (r) => r.per100gKcal),
        pickMetric(b, (r) => r.cookedKcal, (r) => r.per100gKcal),
        CalculationEngine.formatKcal,
      ),
      (
        'Вес готового блюда, г',
        (a != null && a.hasYield) ? a.yieldGrams : null,
        (b != null && b.hasYield) ? b.yieldGrams : null,
        CalculationEngine.formatGrams,
      ),
    ];

    final missingYieldInPer100 =
        !_wholeDish && (!(a?.hasYield ?? true) || !(b?.hasYield ?? true));

    return AppSheetScaffold(
      title: 'Сравнение блюд',
      subtitle: 'Разница показана для второго блюда относительно первого.',
      showHandle: true,
      showClose: true,
      maxHeightFactor: 0.9,
      bodyPadding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            key: const ValueKey('compare-mode-segmented'),
            showSelectedIcon: false,
            style: AppSegmentedStyle.of(p, compact: true),
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('На 100 г'),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('На всё блюдо'),
              ),
            ],
            selected: {_wholeDish},
            onSelectionChanged: (sel) {
              if (sel.isEmpty) return;
              AppHaptics.toggle();
              setState(() => _wholeDish = sel.first);
            },
          ),
          const SizedBox(height: Space.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('compare-swap-btn'),
              onPressed: () {
                AppHaptics.toggle();
                setState(() => _swapped = !_swapped);
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              ),
              icon: const Icon(Icons.swap_horiz_rounded, size: IconSizes.btn),
              label: const Text('Поменять местами'),
            ),
          ),
          if (a == null || b == null) ...[
            const SizedBox(height: Space.x2),
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
              'Для блюда без указанного веса готового блюда значения на 100 г отмечены «—».',
              style: AppTypography.caption.copyWith(color: p.inkSecondary),
            ),
          ],
          const SizedBox(height: Space.x2),
          Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: p.sunken,
              borderRadius: Radii.fieldAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 — $nameA',
                  style: AppTypography.caption.copyWith(
                    color: p.inkSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  '2 — $nameB',
                  style: AppTypography.caption.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.x3),
          GroupedSurface(
            color: p.sunken,
            padding: const EdgeInsets.all(Space.x4),
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
                          const SizedBox(width: Space.x2),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '1 ($nameA)',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: p.inkSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '2 ($nameB)',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Разница',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: p.inkSecondary,
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
                            const SizedBox(height: Space.x1),
                            Text(
                              '$nameA: ${fmtVal(rows[i].$2, rows[i].$4)}',
                              style: AppTypography.numSm
                                  .copyWith(color: p.inkSecondary),
                            ),
                            Text(
                              '$nameB: ${fmtVal(rows[i].$3, rows[i].$4)} '
                              '(Δ ${fmtDelta(rows[i].$2, rows[i].$3, rows[i].$4)})',
                              style: AppTypography.numSm.copyWith(
                                color: deltaColor(
                                  rows[i].$2,
                                  rows[i].$3,
                                  rows[i].$4,
                                ),
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
                            const SizedBox(width: Space.x2),
                            Expanded(
                              flex: 2,
                              child: Text(
                                fmtVal(rows[i].$2, rows[i].$4),
                                textAlign: TextAlign.right,
                                style: AppTypography.numSm
                                    .copyWith(color: p.inkSecondary),
                              ),
                            ),
                            const SizedBox(width: Space.x2),
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
                            const SizedBox(width: Space.x2),
                            Expanded(
                              flex: 2,
                              child: Text(
                                fmtDelta(rows[i].$2, rows[i].$3, rows[i].$4),
                                textAlign: TextAlign.right,
                                style: AppTypography.numSm.copyWith(
                                  color: deltaColor(
                                    rows[i].$2,
                                    rows[i].$3,
                                    rows[i].$4,
                                  ),
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
              if ((a != null && a.cookedKcal > 0) ||
                  (b != null && b.cookedKcal > 0)) ...[
                const SizedBox(height: Space.x3),
                GroupedSurface(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    key: const ValueKey('compare-macro-balance-tile'),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text(
                      'Соотношение Б : Ж : У',
                      style: AppTypography.label.copyWith(color: p.ink),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(
                      Space.x3,
                      0,
                      Space.x3,
                      Space.x3,
                    ),
                    children: [
                      if (a != null && a.cookedKcal > 0) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            nameA,
                            style: AppTypography.label.copyWith(color: p.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
                        if (a != null && a.cookedKcal > 0)
                          const SizedBox(height: Space.x3),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            nameB,
                            style: AppTypography.label.copyWith(color: p.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
              ],
            ],
          ),
        );
  }
}
