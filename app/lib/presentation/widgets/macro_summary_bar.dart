import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/macro_balance.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';
import 'instrument_widgets.dart';
import 'loss_clarity_hints.dart';
import 'macro_balance_bar.dart';
import 'yield_density_warning.dart';

/// Итоги блюда как **жизненный цикл** (аудит P1-6, доработка v1.2).
///
/// Три ступени сверху вниз, в той последовательности, в которой существует
/// блюдо:
/// 1. Сырьё — нетто-масса и Б/Ж/У до готовки;
/// 2. После готовки — что осталось после тепловой обработки;
/// 3. Порция — на 100 г, на всё блюдо, любая масса и быстрые пресеты.
///
/// Числа — tabular figures, без цветных заливок; цвет — только акцент цифры.
class MacroSummaryBar extends StatefulWidget {
  final CalculationResult result;

  /// Компактный режим для нижней закреплённой полосы на коротком экране:
  /// одна строка + «Инспектор расчёта».
  final bool compact;

  /// Главный Hero-виджет итогов в верхней части редактора (стратегия Swiss E1).
  final bool hero;

  /// Необязательный список ингредиентов для вклада в режиме legacy
  /// (для нового расчёта используются строки [CalculationResult.lines]).
  final List<Ingredient>? ingredients;

  /// Интегрированный нижний ярус Hero-карточки (параметры обработки и выхода).
  final Widget? heroFooter;

  /// Синхронизированный внешний режим расчёта («На 100 г» / «На всё блюдо»).
  final bool? showPer100g;
  final ValueChanged<bool>? onModeChanged;

  const MacroSummaryBar({
    super.key,
    required this.result,
    this.compact = false,
    this.hero = false,
    this.ingredients,
    this.heroFooter,
    this.showPer100g,
    this.onModeChanged,
  });

  /// Открывает модальный инспектор расчёта (шаги потерь, выход, вклад).
  static void showInspector(
    BuildContext context, {
    required CalculationResult result,
    List<Ingredient>? ingredients,
  }) =>
      _MacroSummaryBarState._openInspector(
        context,
        result: result,
        ingredients: ingredients,
      );

  @override
  State<MacroSummaryBar> createState() => _MacroSummaryBarState();
}

class _MacroSummaryBarState extends State<MacroSummaryBar> {
  bool _showPer100g = false;

  String m(double value) => CalculationEngine.formatMacro(value);
  String g(double value) => CalculationEngine.formatGrams(value);
  String k(double value) => CalculationEngine.formatKcal(value);
  String macros(double p, double f, double c) =>
      'Б: ${m(p)} · Ж: ${m(f)} · У: ${m(c)} г';

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final p = Palette.of(context);

    if (widget.hero) return _buildHero(context, p, r);
    if (widget.compact) return _buildCompact(context, p, r);

    return Container(
      color: p.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Пищевая ценность готового блюда',
                    style: AppTypography.label.copyWith(color: p.ink),
                  ),
                ),
                _buildInspectorButton(p, dense: true),
              ],
            ),
            const SizedBox(height: Space.x2),

            // ── Ступень 1: Сырьё ────────────────────────────────────────
            _StageRow(
              palette: p,
              number: 1,
              title: 'Сырьё',
              subtitle: 'нетто ${g(r.rawTotalWeight)} г',
              cells: [
                (NutrientType.protein, m(r.rawTotalProtein)),
                (NutrientType.fat, m(r.rawTotalFat)),
                (NutrientType.carbs, m(r.rawTotalCarbs)),
              ],
              muted: true,
            ),
            Divider(color: p.divider, height: Space.x2),
            // ── Ступень 2: После готовки ────────────────────────────────
            _StageRow(
              palette: p,
              number: 2,
              title: 'После готовки',
              // Новый расчёт: потери — по группе каждого продукта, одной
              // тройки на блюдо нет (детали — в инспекторе расчёта).
              subtitle: r.usesLossTable
                  ? '${r.process.label} · потери по группам продуктов'
                  : 'сохранность ${CalculationEngine.formatPercent(r.retentionProtein)} / '
                      '${CalculationEngine.formatPercent(r.retentionFat)} / '
                      '${CalculationEngine.formatPercent(r.retentionCarbs)} %',
              cells: [
                (NutrientType.protein, m(r.cookedProtein)),
                (NutrientType.fat, m(r.cookedFat)),
                (NutrientType.carbs, m(r.cookedCarbs)),
              ],
              trailing: '${k(r.cookedKcal)} ккал',
              trailingTint: p.kcal,
              onTap: () => _inspect(context),
            ),
            Divider(color: p.divider, height: Space.x3),
            // ── Ступень 3: Порция ───────────────────────────────────────
            _buildPortionStage(context, p, r),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorButton(Palette p, {required bool dense}) {
    return TextButton.icon(
      onPressed: () => _inspect(context),
      icon: const Icon(Icons.analytics_outlined, size: 16),
      label: const Text('Инспектор расчёта'),
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? Space.x2 : Space.x3, vertical: 0),
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Ступень 3: «Порция» — переключатель «на всё блюдо / на 100 г» верхней
  /// строкой, 4 значения в ряд, быстрые пресеты и поле произвольной массы.
  Widget _buildPortionStage(BuildContext context, Palette p, CalculationResult r) {
    final needsYield = r.usesLossTable && !r.hasYield;
    final per100 = _showPer100g && !needsYield;
    final totalLabel =
        needsYield ? 'На всё блюдо' : 'На всё блюдо (${g(r.yieldGrams)} г)';
    const per100Label = 'На 100 г готового блюда';

    return Padding(
      padding: const EdgeInsets.only(top: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: Space.x6,
                height: Space.x6,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accentSoft,
                  borderRadius: Radii.chipAll,
                ),
                child: Text(
                  '3',
                  style: AppTypography.caption.copyWith(
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Порция',
                  style: AppTypography.label.copyWith(color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          if (needsYield)
            Text(
              'На всё блюдо. Укажите вес готового блюда, чтобы увидеть '
              '«на 100 г» и «на порцию».',
              key: const ValueKey('yield-needed-hint'),
              style: AppTypography.caption.copyWith(
                color: p.inkSecondary,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: AppSegmentedStyle.of(p, compact: true),
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(totalLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const ButtonSegment(
                  value: true,
                  label: Text(per100Label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
              selected: {_showPer100g},
              onSelectionChanged: (value) =>
                  setState(() => _showPer100g = value.single),
            ),
          if (!needsYield && CalculationValidation.warnsImpossiblePer100g(r)) ...[
            const SizedBox(height: Space.x2),
            YieldDensityWarning(
              key: const ValueKey('portion-yield-density-warning'),
              result: r,
            ),
          ],
          const SizedBox(height: Space.x3),
          // Четыре числа через единый InlineMacroCell (ключи macro-* сохранены).
          Wrap(
            spacing: Space.x4,
            runSpacing: Space.x2,
            children: [
              InlineMacroCell(
                type: NutrientType.protein,
                label: 'Белки',
                value: m(per100 ? r.per100gProtein : r.cookedProtein),
                unit: 'г',
                stacked: true,
                valueKey: const ValueKey('macro-Белки'),
              ),
              InlineMacroCell(
                type: NutrientType.fat,
                label: 'Жиры',
                value: m(per100 ? r.per100gFat : r.cookedFat),
                unit: 'г',
                stacked: true,
                valueKey: const ValueKey('macro-Жиры'),
              ),
              InlineMacroCell(
                type: NutrientType.carbs,
                label: 'Углеводы',
                value: m(per100 ? r.per100gCarbs : r.cookedCarbs),
                unit: 'г',
                stacked: true,
                valueKey: const ValueKey('macro-Углеводы'),
              ),
              InlineMacroCell(
                type: NutrientType.kcal,
                label: 'Энергия',
                value: k(per100 ? r.per100gKcal : r.cookedKcal),
                unit: 'ккал',
                stacked: true,
                valueKey: const ValueKey('macro-Энергия'),
              ),
            ],
          ),
          if (r.yieldGrams > 0) ...[
            const SizedBox(height: Space.x3),
            _PortionCalculator(result: r),
          ],
        ],
      ),
    );
  }

  /// Главный Hero-виджет «Прибор» (`hero: true`): тёмная графитовая плита
  /// + встроенный при необходимости нижний ярус параметров.
  Widget _buildHero(BuildContext context, Palette p, CalculationResult r) {
    final canSwitch = r.hasYield;
    final per100 = canSwitch && (widget.showPer100g ?? _showPer100g);
    final kcalVal = per100 ? r.per100gKcal : r.cookedKcal;
    final proteinVal = per100 ? r.per100gProtein : r.cookedProtein;
    final fatVal = per100 ? r.per100gFat : r.cookedFat;
    final carbsVal = per100 ? r.per100gCarbs : r.cookedCarbs;

    return InstrumentSlab(
      borderRadius: Radii.slabAll,
      onTap: () => _inspect(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x4,
              Space.x3,
              Space.x4,
              Space.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  per100
                      ? 'После готовки · на 100 г'
                      : 'После готовки · на всё блюдо',
                  style: AppTypography.caption.copyWith(
                    color: p.slabSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.x1),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.x2,
                  runSpacing: Space.x1,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          AnimatedMetricText(
                            value: kcalVal,
                            formatter: k,
                            style: AppTypography.heroKcal
                                .copyWith(color: p.slabInk),
                          ),
                          const SizedBox(width: Space.x2),
                          Text(
                            per100 ? 'ккал / 100 г' : 'ккал',
                            style: AppTypography.bodySm.copyWith(
                              color: p.slabSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canSwitch)
                      Material(
                        color: p.accent,
                        borderRadius: Radii.fieldAll,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey('hero-mode-toggle'),
                          onTap: () {
                            AppHaptics.toggle();
                            final next = !per100;
                            if (widget.onModeChanged != null) {
                              widget.onModeChanged!(next);
                            } else {
                              setState(() => _showPer100g = next);
                            }
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: kMinTapTarget,
                              minHeight: kMinTapTarget,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.x3,
                                vertical: Space.x2,
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  per100 ? 'На всё блюдо' : 'На 100 г',
                                  style: AppTypography.label.copyWith(
                                    color: p.onAccent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                Wrap(
                  spacing: Space.x4,
                  runSpacing: Space.x1,
                  children: [
                    InlineMacroCell(
                      type: NutrientType.protein,
                      label: 'Белки',
                      value: m(proteinVal),
                      unit: 'г',
                      stacked: true,
                      compact: true,
                      onDarkSlab: true,
                      valueKey: const ValueKey('macro-Белки'),
                    ),
                    InlineMacroCell(
                      type: NutrientType.fat,
                      label: 'Жиры',
                      value: m(fatVal),
                      unit: 'г',
                      stacked: true,
                      compact: true,
                      onDarkSlab: true,
                      valueKey: const ValueKey('macro-Жиры'),
                    ),
                    InlineMacroCell(
                      type: NutrientType.carbs,
                      label: 'Углеводы',
                      value: m(carbsVal),
                      unit: 'г',
                      stacked: true,
                      compact: true,
                      onDarkSlab: true,
                      valueKey: const ValueKey('macro-Углеводы'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: p.slabSurface),
          Tooltip(
            message: 'Инспектор расчёта',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x3,
                Space.x4,
                Space.x3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Подробнее о расчёте',
                      style: AppTypography.label.copyWith(
                        color: p.slabSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: p.slabSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Компактная полоса для нижнего дока: одна числовая строка + инспектор.
  ///
  /// Выход блюда здесь сознательно НЕ дублируется: он уже выведен крупной
  /// строкой в карточке параметров выше.
  Widget _buildCompact(BuildContext context, Palette p, CalculationResult r) {
    final media = MediaQuery.sizeOf(context);
    final shortHeight = media.height < 460;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final inlineCells =
        shortHeight || (media.height < 640 && textScale > 1.35);
    final ultraCompact = shortHeight && textScale > 1.35;
    final compactLabels = textScale > 1.35 || media.width < 360;
    final cells = <(NutrientType, Color, String, String, String, String)>[
      (NutrientType.protein, p.protein, 'Белки', 'Б', m(r.cookedProtein), 'г'),
      (NutrientType.fat, p.fat, 'Жиры', 'Ж', m(r.cookedFat), 'г'),
      (NutrientType.carbs, p.carbs, 'Углеводы', 'У', m(r.cookedCarbs), 'г'),
      (NutrientType.kcal, p.kcal, 'Энергия', '', k(r.cookedKcal), 'ккал'),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: inlineCells ? 0 : Space.x1),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _inspect(context),
                borderRadius: Radii.fieldAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTapTarget),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!ultraCompact) ...[
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'После готовки · на всё блюдо',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (r.hasYield && !compactLabels && !shortHeight)
                              Text(
                                ' · ${k(r.per100gKcal)} / 100 г',
                                style: AppTypography.caption.copyWith(
                                  color: p.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      if (inlineCells)
                        Semantics(
                          label:
                              'После готовки · на всё блюдо: Белки ${m(r.cookedProtein)} г, Жиры ${m(r.cookedFat)} г, Углеводы ${m(r.cookedCarbs)} г, Энергия ${k(r.cookedKcal)} ккал',
                          child: Text.rich(
                            TextSpan(
                              style: AppTypography.caption.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                for (var i = 0; i < cells.length; i++) ...[
                                  if (i > 0)
                                    TextSpan(
                                      text: ' · ',
                                      style: AppTypography.caption
                                          .copyWith(color: p.inkMuted),
                                    ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 3),
                                      decoration: BoxDecoration(
                                        color: cells[i].$2,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: compactLabels
                                        ? (cells[i].$4.isEmpty
                                            ? '${cells[i].$5} ${cells[i].$6}'
                                            : '${cells[i].$4} ${cells[i].$5}')
                                        : '${cells[i].$3} ${cells[i].$5} ${cells[i].$6}',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: Space.x3,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            for (final cell in cells)
                              InlineMacroCell(
                                type: cell.$1,
                                label: cell.$3,
                                value: cell.$5,
                                unit: cell.$6,
                                stacked: true,
                                compact: true,
                                valueKey: ValueKey('macro-${cell.$3}'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Инспектор расчёта',
            onPressed: () => _inspect(context),
            icon: Semantics(
              label: 'Инспектор расчёта',
              child:
                  Icon(Icons.analytics_outlined, size: 20, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _inspect(BuildContext context) => _openInspector(
        context,
        result: widget.result,
        ingredients: widget.ingredients,
      );

  static void _openInspector(
    BuildContext context, {
    required CalculationResult result,
    List<Ingredient>? ingredients,
  }) {
    final r = result;
    final e = YieldExplanation(r.rawTotalWeight, r.yieldGrams);
    final p = Palette.of(context);
    final contributions = _buildContributionItems(r, ingredients);
    final clarityNotes = r.usesLossTable
        ? LossClarityHints.forLines(
            r.lines.map((l) => (group: l.group, process: l.process)),
          )
        : const <String>[];
    final warnsDensity = CalculationValidation.warnsImpossiblePer100g(r);
    String m(double value) => CalculationEngine.formatMacro(value);
    String g(double value) => CalculationEngine.formatGrams(value);
    String k(double value) => CalculationEngine.formatKcal(value);
    String macros(double pVal, double fVal, double cVal) =>
        'Б: ${m(pVal)} · Ж: ${m(fVal)} · У: ${m(cVal)} г';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) => AppSheetScaffold(
        title: 'Расчёт блюда',
        subtitle: 'На 100 г, на порцию и по шагам тепловой обработки.',
        showHandle: true,
        maxHeightFactor: 0.92,
        bodyPadding:
            const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 1. Результат (чистая 2-колоночная карточка) ─────────────
            GroupedSurface(
              color: p.sunken,
              padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Результат после готовки',
                      style: AppTypography.label.copyWith(color: p.inkMuted),
                    ),
                    const SizedBox(height: Space.x3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.hasYield
                                    ? 'На всё блюдо · ${g(r.yieldGrams)} г'
                                    : 'На всё блюдо',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkSecondary),
                              ),
                              const SizedBox(height: Space.x1),
                              Text(
                                '${k(r.cookedKcal)} ккал',
                                style:
                                    AppTypography.title.copyWith(color: p.ink),
                              ),
                              const SizedBox(height: Space.x1),
                              Text(
                                'Б ${m(r.cookedProtein)} · Ж ${m(r.cookedFat)} · У ${m(r.cookedCarbs)} г',
                                style: AppTypography.numSm
                                    .copyWith(color: p.inkSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'На 100 г',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkSecondary),
                              ),
                              const SizedBox(height: Space.x1),
                              if (r.hasYield) ...[
                                Text(
                                  '${k(r.per100gKcal)} ккал',
                                  style: AppTypography.title
                                      .copyWith(color: p.accent),
                                ),
                                const SizedBox(height: Space.x1),
                                Text(
                                  'Б ${m(r.per100gProtein)} · Ж ${m(r.per100gFat)} · У ${m(r.per100gCarbs)} г',
                                  style: AppTypography.numSm
                                      .copyWith(color: p.inkSecondary),
                                ),
                              ] else
                                Text(
                                  'Вес не указан',
                                  style: AppTypography.bodySm
                                      .copyWith(color: p.inkMuted),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (r.yieldGrams > 0) ...[
                const SizedBox(height: Space.x3),
                // ── 2. Моя порция ────────────────────────────────────────
                GroupedSurface(
                  padding: const EdgeInsets.all(Space.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Моя порция',
                        style: AppTypography.headline.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: Space.x2),
                      _PortionCalculator(
                        result: r,
                        keyPrefix: 'inspector-',
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Space.x3),
              // ── 3. Что изменилось при готовке (+ предупреждения) ───────
              GroupedSurface(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Что изменилось при готовке',
                      style: AppTypography.headline.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: Space.x2),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x1,
                      children: [
                        for (final stepLabel in [
                          'Сырьё ${g(r.rawTotalWeight)} г',
                          '→ ${r.process.label}',
                          '→ ${r.hasYield ? 'Готово ${g(r.yieldGrams)} г' : 'Вес не указан'}',
                        ])
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.x2,
                              vertical: Space.x1,
                            ),
                            decoration: BoxDecoration(
                              color: p.sunken,
                              borderRadius: Radii.chipAll,
                            ),
                            child: Text(
                              stepLabel,
                              style: AppTypography.caption.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    Text(
                      e.badge,
                      style: AppTypography.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      e.description,
                      style: AppTypography.bodySm
                          .copyWith(color: p.inkSecondary),
                    ),
                    if (warnsDensity) ...[
                      const SizedBox(height: Space.x2),
                      YieldDensityWarning(
                        key: const ValueKey('inspector-yield-density-warning'),
                        result: r,
                      ),
                    ],
                    if (clarityNotes.isNotEmpty) ...[
                      const SizedBox(height: Space.x2),
                      Container(
                        key: const ValueKey('inspector-loss-clarity-hints'),
                        padding: const EdgeInsets.all(Space.x3),
                        decoration: BoxDecoration(
                          color: p.accentSoft,
                          borderRadius: Radii.fieldAll,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: p.accent),
                            const SizedBox(width: Space.x2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final note in clarityNotes)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: Space.x1),
                                      child: Text(
                                        note,
                                        style: AppTypography.caption
                                            .copyWith(color: p.ink),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.x3),
              // ── 4. Детали по требованию (аккордеоны) ──────────────────
              GroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (contributions.isNotEmpty || r.cookedKcal > 0) ...[
                      ExpansionTile(
                        key: const ValueKey('inspector-acc-contrib'),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Text(
                          'Вклад продуктов и баланс БЖУ',
                          style: AppTypography.label.copyWith(color: p.ink),
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                            Space.x4, 0, Space.x4, Space.x4),
                        children: [
                          if (r.cookedKcal > 0) ...[
                            MacroBalanceBar(
                              key: const ValueKey('inspector-macro-balance'),
                              balance: MacroBalance.fromMacros(
                                protein: r.cookedProtein,
                                fat: r.cookedFat,
                                carbs: r.cookedCarbs,
                              ),
                            ),
                            if (contributions.isNotEmpty)
                              const SizedBox(height: Space.x3),
                          ],
                          if (contributions.isNotEmpty)
                            _IngredientContributionSection(items: contributions),
                        ],
                      ),
                      Divider(color: p.divider, height: 1),
                    ],
                    ExpansionTile(
                      key: const ValueKey('inspector-acc-steps'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        'Подробный расчёт по шагам',
                        style: AppTypography.label.copyWith(color: p.ink),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                          Space.x4, 0, Space.x4, Space.x4),
                      children: [
                        _buildStepSection(
                          palette: p,
                          stepNumber: 1,
                          title: 'Сырьё · нетто ${g(r.rawTotalWeight)} г',
                          content: Wrap(
                            spacing: Space.x3,
                            runSpacing: Space.x1,
                            children: [
                              InlineMacroCell(
                                type: NutrientType.protein,
                                value: m(r.rawTotalProtein),
                                unit: 'г',
                                compact: true,
                              ),
                              InlineMacroCell(
                                type: NutrientType.fat,
                                value: m(r.rawTotalFat),
                                unit: 'г',
                                compact: true,
                              ),
                              InlineMacroCell(
                                type: NutrientType.carbs,
                                value: m(r.rawTotalCarbs),
                                unit: 'г',
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                        Divider(color: p.divider, height: Space.x4),
                        if (r.usesLossTable)
                          _buildLossLinesSection(p, r)
                        else
                          _buildStepSection(
                            palette: p,
                            stepNumber: 2,
                            title: 'Потери при готовке — сохранность',
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final row in [
                                  (
                                    'Белки',
                                    r.rawTotalProtein,
                                    r.retentionProtein,
                                    r.cookedProtein
                                  ),
                                  (
                                    'Жиры',
                                    r.rawTotalFat,
                                    r.retentionFat,
                                    r.cookedFat
                                  ),
                                  (
                                    'Углеводы',
                                    r.rawTotalCarbs,
                                    r.retentionCarbs,
                                    r.cookedCarbs
                                  ),
                                ])
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: Space.x1),
                                    child: Text(
                                      '${row.$1}: ${m(row.$2)} × ${CalculationEngine.formatPercent(row.$3)}% = ${m(row.$4)} г',
                                      style: AppTypography.numSm
                                          .copyWith(color: p.ink),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Divider(color: p.divider, height: Space.x4),
                        _buildStepSection(
                          palette: p,
                          stepNumber: 3,
                          title: 'Энергетическая ценность после готовки',
                          content: GroupedSurface(
                            color: p.sunken,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.x3,
                              vertical: Space.x2,
                            ),
                            borderRadius: Radii.fieldAll,
                            child: Text(
                              '${m(r.cookedProtein)} × 4 + ${m(r.cookedFat)} × 9 + ${m(r.cookedCarbs)} × 4 = ${k(r.cookedKcal)} ккал',
                              style: AppTypography.formulaMono
                                  .copyWith(color: p.ink),
                            ),
                          ),
                        ),
                        if (r.yieldGrams > 0) ...[
                          Divider(color: p.divider, height: Space.x4),
                          _buildStepSection(
                            palette: p,
                            stepNumber: 4,
                            title: 'На 100 г (при выходе ${g(r.yieldGrams)} г)',
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Каждый итог после готовки × 100 / ${g(r.yieldGrams)}',
                                  style: AppTypography.caption
                                      .copyWith(color: p.inkMuted),
                                ),
                                const SizedBox(height: Space.x1),
                                Text(
                                  '${macros(r.per100gProtein, r.per100gFat, r.per100gCarbs)} · ${k(r.per100gKcal)} ккал',
                                  style: AppTypography.numSm.copyWith(
                                    color: p.ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Divider(color: p.divider, height: 1),
                    ExpansionTile(
                      key: const ValueKey('inspector-acc-sources'),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        'Источники данных и округление',
                        style: AppTypography.label.copyWith(color: p.ink),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                          Space.x4, 0, Space.x4, Space.x4),
                      children: [
                        Text(
                          'Сырой состав и готовое блюдо — разные стадии, а не противоречащие значения. '
                          '${r.usesLossTable ? 'Потери берутся из таблицы МР 2.3.0419-26 (прил. 4–5) по группе каждого продукта; вес готового блюда вводит повар. $kNotGostNotice ' : 'Сохранность задаётся в параметрах и не определяет уварку. '}Округление как в бланке: '
                          'БЖУ до 0,01 г, энергия до 0,1 ккал; энергия считается по округлённым БЖУ.',
                          style: AppTypography.caption
                              .copyWith(color: p.inkSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.x4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// Шаг 2 нового расчёта: потери по каждому ингредиенту — группа, способ,
  /// проценты из таблицы и «сырьё → после готовки» для Б/Ж/У.
  static Widget _buildLossLinesSection(Palette p, CalculationResult r) {
    String pct(double v) => CalculationEngine.formatGrams(v);
    String m(double value) => CalculationEngine.formatMacro(value);
    String macros(double p, double f, double c) =>
        'Б: ${m(p)} · Ж: ${m(f)} · У: ${m(c)} г';
    return _buildStepSection(
      palette: p,
      stepNumber: 2,
      title: 'Потери при готовке по продуктам',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x3,
              vertical: Space.x2,
            ),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: Radii.fieldAll,
            ),
            child: Text(
              'Итого после готовки: ${macros(r.cookedProtein, r.cookedFat, r.cookedCarbs)}',
              key: const ValueKey('inspector-loss-total'),
              style: AppTypography.numSm
                  .copyWith(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: Space.x2),
          for (final line in r.lines)
            Container(
              margin: const EdgeInsets.only(bottom: Space.x2),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x3,
                vertical: Space.x2,
              ),
              decoration: BoxDecoration(
                color: p.sunken,
                borderRadius: Radii.fieldAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: line.productName.isEmpty
                              ? 'Ингредиент'
                              : line.productName,
                          style: AppTypography.bodySm.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              '\n${line.group.label}${line.groupIsManual ? ' (вручную)' : ''} · '
                              '${line.process.label}${line.processIsManual ? ' (вручную)' : ''} — '
                              'потери Б ${pct(line.loss.protein)} %, Ж ${pct(line.loss.fat)} %, '
                              'У ${pct(line.loss.carbs)} %'
                              '${line.loss.isVerified ? '' : ' (оценка)'}',
                          style: AppTypography.caption
                              .copyWith(color: p.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.x1),
                  Text(
                    'Б ${m(line.rawProtein)} → ${m(line.cookedProtein)} · '
                    'Ж ${m(line.rawFat)} → ${m(line.cookedFat)} · '
                    'У ${m(line.rawCarbs)} → ${m(line.cookedCarbs)} г',
                    style: AppTypography.numSm.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Источник потерь: МР 2.3.0419-26, прил. 4–5; «оценка» — '
            'ближайший аналог, строки в источнике нет.',
            style: AppTypography.caption.copyWith(color: p.inkMuted),
          ),
          if (LossClarityHints.forLines(
            r.lines.map((l) => (group: l.group, process: l.process)),
          )
              case final clarityNotes when clarityNotes.isNotEmpty) ...[
            const SizedBox(height: Space.x2),
            Container(
              key: const ValueKey('inspector-loss-clarity-hints'),
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: p.accentSoft,
                borderRadius: Radii.fieldAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: p.accent),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final note in clarityNotes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.x1),
                            child: Text(
                              note,
                              style: AppTypography.caption
                                  .copyWith(color: p.ink),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildStepSection({
    required Palette palette,
    required int stepNumber,
    required String title,
    required Widget content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$stepNumber',
                style: AppTypography.caption.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: Text(
                title,
                style: AppTypography.label.copyWith(color: palette.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        content,
      ],
    );
  }
}

/// Ступень жизненного цикла: номер, заголовок, Б/Ж/У и опционально энергия.
class _StageRow extends StatelessWidget {
  final Palette palette;
  final int number;
  final String title;
  final String subtitle;
  final List<(NutrientType, String)> cells;
  final String? trailing;
  final Color? trailingTint;
  final bool muted;
  final VoidCallback? onTap;

  const _StageRow({
    required this.palette,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.cells,
    this.trailing,
    this.trailingTint,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Row(
        children: [
          Container(
            width: Space.x6,
            height: Space.x6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: muted ? p.sunken : p.accentSoft,
              borderRadius: Radii.chipAll,
            ),
            child: Text(
              '$number',
              style: AppTypography.caption.copyWith(
                color: muted ? p.inkSecondary : p.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          // Заголовок ступени и её значения — одной колонкой внутри Expanded:
          // никаких неограниченных Column внутри Row.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.label.copyWith(color: p.ink)),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(color: p.inkSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (cells.isNotEmpty || trailing != null) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: Space.x3,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final c in cells)
                        InlineMacroCell(
                          type: c.$1,
                          value: c.$2,
                          compact: true,
                          muted: muted,
                        ),
                      if (trailing != null)
                        Text(
                          trailing!,
                          style: AppTypography.numSm.copyWith(
                            color: trailingTint ?? p.kcal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.fieldAll,
      child: row,
    );
  }
}

class _PortionCalculator extends StatefulWidget {
  final CalculationResult result;
  final String keyPrefix;

  const _PortionCalculator({
    required this.result,
    this.keyPrefix = '',
  });

  @override
  State<_PortionCalculator> createState() => _PortionCalculatorState();
}

class _PortionCalculatorState extends State<_PortionCalculator> {
  static const List<int> _portionPresets = [100, 150, 200, 250, 300];

  double _portionGrams = 200;
  String? _portionError;
  late final TextEditingController _portionCtrl;

  @override
  void initState() {
    super.initState();
    _portionCtrl = TextEditingController(text: '200');
  }

  @override
  void dispose() {
    _portionCtrl.dispose();
    super.dispose();
  }

  void _selectPortionPreset(int grams) {
    setState(() {
      _portionGrams = grams.toDouble();
      _portionError = null;
      final text = grams.toString();
      _portionCtrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = widget.result;
    final prefix = widget.keyPrefix;
    final portion = r.portion(_portionGrams);
    final g = CalculationEngine.formatGrams;
    final m = CalculationEngine.formatMacro;
    final k = CalculationEngine.formatKcal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x1,
          children: [
            for (final grams in _portionPresets)
              ChoiceChip(
                key: ValueKey('${prefix}portion-preset-$grams'),
                label: Text('$grams г'),
                selected:
                    (_portionGrams - grams).abs() < 0.01 &&
                        _portionError == null,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => _selectPortionPreset(grams),
              ),
          ],
        ),
        const SizedBox(height: Space.x2),
        TextFormField(
          key: ValueKey('${prefix}portion-grams'),
          controller: _portionCtrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: AppTypography.num,
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Масса порции, г',
            errorText: _portionError,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: Space.x3, vertical: Space.x2),
          ),
          onChanged: (text) {
            final v = CalculationEngine.parseInputDouble(text);
            setState(() {
              if (v == null || v < .1 || v > 9999999) {
                _portionError = 'Введите массу от 0,1 до 9999999 г';
              } else {
                _portionGrams = v;
                _portionError = null;
              }
            });
          },
        ),
        const SizedBox(height: Space.x2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          ),
          decoration: BoxDecoration(
            color: p.sunken,
            borderRadius: Radii.fieldAll,
          ),
          child: Text(
            'Порция ${g(_portionGrams)} г: '
            'Б: ${m(portion.protein)} · Ж: ${m(portion.fat)} · У: ${m(portion.carbs)} г '
            '· ${k(portion.kcal)} ккал',
            key: ValueKey('${prefix}portion-result'),
            style: AppTypography.numSm
                .copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

enum _ContributionMetric { kcal, protein, fat, carbs }

class _ContributionItem {
  final String name;
  final double protein;
  final double fat;
  final double carbs;
  final double kcal;

  const _ContributionItem({
    required this.name,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.kcal,
  });

  double valueFor(_ContributionMetric metric) => switch (metric) {
        _ContributionMetric.kcal => kcal,
        _ContributionMetric.protein => protein,
        _ContributionMetric.fat => fat,
        _ContributionMetric.carbs => carbs,
      };
}

List<_ContributionItem> _buildContributionItems(
  CalculationResult r,
  List<Ingredient>? fallbackIngredients,
) {
  if (r.lines.isNotEmpty) {
    return [
      for (final line in r.lines)
        _ContributionItem(
          name: line.productName.trim().isEmpty
              ? 'Ингредиент'
              : line.productName.trim(),
          protein: line.cookedProtein,
          fat: line.cookedFat,
          carbs: line.cookedCarbs,
          kcal: line.cookedKcal,
        ),
    ];
  }
  final fallback = fallbackIngredients;
  if (fallback == null || fallback.isEmpty) return const [];
  final items = <_ContributionItem>[];
  for (final ing in fallback) {
    try {
      final p = CalculationMath.round2(ing.proteinInDish * r.retentionProtein);
      final f = CalculationMath.round2(ing.fatInDish * r.retentionFat);
      final c = CalculationMath.round2(ing.carbsInDish * r.retentionCarbs);
      final k = CalculationMath.energy(p, f, c);
      items.add(
        _ContributionItem(
          name: ing.product.name.trim().isEmpty
              ? 'Ингредиент'
              : ing.product.name.trim(),
          protein: p,
          fat: f,
          carbs: c,
          kcal: k,
        ),
      );
    } on ArgumentError {
      // Пропускаем невалидную строку в аварийном снимке.
    }
  }
  return items;
}

class _IngredientContributionSection extends StatefulWidget {
  final List<_ContributionItem> items;

  const _IngredientContributionSection({required this.items});

  @override
  State<_IngredientContributionSection> createState() =>
      _IngredientContributionSectionState();
}

class _IngredientContributionSectionState
    extends State<_IngredientContributionSection> {
  static const int _initialLimit = 6;

  _ContributionMetric _metric = _ContributionMetric.kcal;
  bool _showAll = false;

  Color _colorFor(Palette p, _ContributionMetric metric) => switch (metric) {
        _ContributionMetric.kcal => p.kcal,
        _ContributionMetric.protein => p.protein,
        _ContributionMetric.fat => p.fat,
        _ContributionMetric.carbs => p.carbs,
      };

  String _formatValue(double value, _ContributionMetric metric) =>
      metric == _ContributionMetric.kcal
          ? '${CalculationEngine.formatKcal(value)} ккал'
          : '${CalculationEngine.formatMacro(value)} г';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sorted = List<_ContributionItem>.from(widget.items)
      ..sort((a, b) => b.valueFor(_metric).compareTo(a.valueFor(_metric)));
    final total = sorted.fold<double>(
      0.0,
      (sum, item) => sum + item.valueFor(_metric),
    );
    final visible = (!_showAll && sorted.length > _initialLimit)
        ? sorted.sublist(0, _initialLimit)
        : sorted;
    final barColor = _colorFor(p, _metric);
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackHeader = size.width < 360 || textScale > 1.35;

    return Column(
      key: const ValueKey('inspector-contribution-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.x1),
        SegmentedButton<_ContributionMetric>(
          key: const ValueKey('inspector-contrib-metric'),
          showSelectedIcon: false,
          style: AppSegmentedStyle.of(p, compact: true),
          segments: const [
            ButtonSegment(
              value: _ContributionMetric.kcal,
              label: Text('Ккал', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: _ContributionMetric.protein,
              label: Text('Б', maxLines: 1),
            ),
            ButtonSegment(
              value: _ContributionMetric.fat,
              label: Text('Ж', maxLines: 1),
            ),
            ButtonSegment(
              value: _ContributionMetric.carbs,
              label: Text('У', maxLines: 1),
            ),
          ],
          selected: {_metric},
          onSelectionChanged: (sel) {
            if (sel.isEmpty) return;
            AppHaptics.toggle();
            setState(() => _metric = sel.first);
          },
        ),
        const SizedBox(height: Space.x3),
        if (total <= 0)
          Text(
            'Вклад по выбранному показателю равен 0.',
            style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
          )
        else ...[
          for (var i = 0; i < visible.length; i++) ...[
            Builder(
              builder: (context) {
                final item = visible[i];
                final value = item.valueFor(_metric);
                final share = (value / total).clamp(0.0, 1.0);
                final pctText = '${(share * 100).round()} %';
                final nameWidget = Text(
                  item.name,
                  style: AppTypography.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: stackHeader ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                );
                final metricWidget = Text(
                  '${_formatValue(value, _metric)} · $pctText',
                  style: AppTypography.numSm.copyWith(
                    color: i == 0 ? barColor : p.inkSecondary,
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : Space.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stackHeader) ...[
                        nameWidget,
                        const SizedBox(height: Space.x1),
                        metricWidget,
                      ] else
                        Row(
                          children: [
                            Expanded(child: nameWidget),
                            const SizedBox(width: Space.x2),
                            Flexible(child: metricWidget),
                          ],
                        ),
                      const SizedBox(height: Space.x1),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Space.x1),
                        child: Container(
                          height: 6,
                          color: p.sunken,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: share,
                            child: Container(
                              color: barColor.withOpacity(i == 0 ? 0.92 : 0.65),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (sorted.length > _initialLimit) ...[
            const SizedBox(height: Space.x2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('inspector-contrib-toggle-all'),
                onPressed: () => setState(() => _showAll = !_showAll),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, kMinTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                ),
                child: Text(
                  _showAll
                      ? 'Свернуть список'
                      : 'Показать все (${sorted.length})',
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

