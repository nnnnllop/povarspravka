import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/macro_balance.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'instrument_widgets.dart';
import 'macro_balance_bar.dart';
import 'nutrient_chip.dart';

/// Элемент конструктора меню / набора блюд.
class MenuItemDraft {
  final Dish dish;
  final CalculationResult calc;
  final double portionGrams;
  final bool usesWholeDish;

  const MenuItemDraft({
    required this.dish,
    required this.calc,
    required this.portionGrams,
    required this.usesWholeDish,
  });

  MenuItemDraft copyWith({double? portionGrams}) => MenuItemDraft(
        dish: dish,
        calc: calc,
        portionGrams: portionGrams ?? this.portionGrams,
        usesWholeDish: usesWholeDish,
      );

  ({double protein, double fat, double carbs, double kcal}) get macros {
    if (usesWholeDish || !calc.hasYield) {
      return (
        protein: calc.cookedProtein,
        fat: calc.cookedFat,
        carbs: calc.cookedCarbs,
        kcal: calc.cookedKcal,
      );
    }
    return calc.portion(portionGrams);
  }
}

/// Итоговые нутриенты, масса и баланс Б/Ж/У собранного меню.
class MenuSummary {
  final double totalGrams;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;
  final double totalKcal;
  final MacroBalance balance;
  final bool hasWholeDishWithoutYield;

  const MenuSummary({
    required this.totalGrams,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
    required this.totalKcal,
    required this.balance,
    required this.hasWholeDishWithoutYield,
  });
}

MenuSummary computeMenuSummary(List<MenuItemDraft> items) {
  double grams = 0;
  double p = 0;
  double f = 0;
  double c = 0;
  double kcal = 0;
  var hasNoYield = false;

  for (final item in items) {
    final m = item.macros;
    p = CalculationMath.round2(p + m.protein);
    f = CalculationMath.round2(f + m.fat);
    c = CalculationMath.round2(c + m.carbs);
    kcal = CalculationMath.round1(kcal + m.kcal);
    if (item.usesWholeDish || !item.calc.hasYield) {
      hasNoYield = true;
    } else {
      grams = CalculationMath.round1(grams + item.portionGrams);
    }
  }

  return MenuSummary(
    totalGrams: grams,
    totalProtein: p,
    totalFat: f,
    totalCarbs: c,
    totalKcal: kcal,
    balance: MacroBalance.fromMacros(protein: p, fat: f, carbs: c),
    hasWholeDishWithoutYield: hasNoYield,
  );
}

String formatMenuPlainText(List<MenuItemDraft> items, MenuSummary summary) {
  final m = CalculationEngine.formatMacro;
  final k = CalculationEngine.formatKcal;
  final g = CalculationEngine.formatGrams;
  final buf = StringBuffer()
    ..writeln('Набор блюд (${items.length}):');
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final title = item.dish.title.trim().isEmpty
        ? 'Блюдо без названия'
        : item.dish.title.trim();
    final macros = item.macros;
    final weightLabel = item.usesWholeDish || !item.calc.hasYield
        ? 'всё блюдо'
        : '${g(item.portionGrams)} г';
    buf.writeln(
      '${i + 1}. $title ($weightLabel) — Б ${m(macros.protein)} · '
      'Ж ${m(macros.fat)} · У ${m(macros.carbs)} г · ${k(macros.kcal)} ккал',
    );
  }
  buf.writeln('');
  buf.writeln(
    'Итого: Б ${m(summary.totalProtein)} г · Ж ${m(summary.totalFat)} г · '
    'У ${m(summary.totalCarbs)} г · ${k(summary.totalKcal)} ккал',
  );
  if (summary.balance.hasEnergy) {
    buf.writeln(
      'Баланс КБЖУ: Б ${summary.balance.proteinPct}% · '
      'Ж ${summary.balance.fatPct}% · У ${summary.balance.carbsPct}%',
    );
  }
  return buf.toString().trimRight();
}

/// Шторка конструктора набора блюд / рациона из выбранных рецептов.
class MenuBuilderSheet extends StatefulWidget {
  final List<Dish> dishes;

  const MenuBuilderSheet({super.key, required this.dishes});

  static Future<void> show(
    BuildContext context, {
    required List<Dish> dishes,
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
      builder: (_) => MenuBuilderSheet(dishes: dishes),
    );
  }

  @override
  State<MenuBuilderSheet> createState() => _MenuBuilderSheetState();
}

class _MenuBuilderSheetState extends State<MenuBuilderSheet> {
  static const List<int> _portionPresets = [100, 150, 200, 250, 300];

  late final List<MenuItemDraft> _items;
  int _invalidCount = 0;

  @override
  void initState() {
    super.initState();
    _items = <MenuItemDraft>[];
    for (final d in widget.dishes) {
      final calc = CalculationEngine.tryCalculate(d);
      if (calc == null) {
        _invalidCount++;
        continue;
      }
      if (!calc.hasYield) {
        _items.add(
          MenuItemDraft(
            dish: d,
            calc: calc,
            portionGrams: 0,
            usesWholeDish: true,
          ),
        );
      } else {
        final defaultGrams = calc.yieldGrams <= 300
            ? CalculationMath.round1(calc.yieldGrams)
            : 200.0;
        _items.add(
          MenuItemDraft(
            dish: d,
            calc: calc,
            portionGrams: math.max(10.0, defaultGrams),
            usesWholeDish: false,
          ),
        );
      }
    }
  }

  void _setPortion(int index, double grams) {
    final safe = CalculationMath.round1(grams.clamp(1.0, 9999999.0));
    AppHaptics.key();
    setState(() {
      _items[index] = _items[index].copyWith(portionGrams: safe);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final summary = computeMenuSummary(_items);
    final m = CalculationEngine.formatMacro;
    final k = CalculationEngine.formatKcal;
    final g = CalculationEngine.formatGrams;

    return SizedBox(
      key: const ValueKey('menu-builder-sheet'),
      height: size.height * 0.9,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Набор блюд (меню)',
                style: AppTypography.title.copyWith(color: p.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Укажите массу порции каждого блюда — итог пересчитается автоматически.',
                style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
              if (_invalidCount > 0) ...[
                const SizedBox(height: Space.x2),
                Container(
                  padding: const EdgeInsets.all(Space.x3),
                  decoration: BoxDecoration(
                    color: p.dangerSoft,
                    borderRadius: Radii.fieldAll,
                  ),
                  child: Text(
                    'Пропущено блюд с ошибкой расчёта: $_invalidCount.',
                    style: AppTypography.caption.copyWith(color: p.danger),
                  ),
                ),
              ],
              if (_items.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                InstrumentSlab(
                  key: const ValueKey('menu-total-card'),
                  padding: const EdgeInsets.all(Space.x3 + 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const SignalDot(size: 6),
                          const SizedBox(width: Space.x2),
                          Expanded(
                            child: Text(
                              summary.totalGrams > 0 &&
                                      !summary.hasWholeDishWithoutYield
                                  ? 'Итого по меню (${g(summary.totalGrams)} г)'
                                  : 'Итого по меню',
                              style:
                                  AppTypography.label.copyWith(color: p.slabInk),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.x2),
                      Wrap(
                        spacing: Space.x4,
                        runSpacing: Space.x2,
                        children: [
                          InlineMacroCell(
                            type: NutrientType.protein,
                            label: 'Белки',
                            value: m(summary.totalProtein),
                            unit: 'г',
                            stacked: true,
                            onDarkSlab: true,
                          ),
                          InlineMacroCell(
                            type: NutrientType.fat,
                            label: 'Жиры',
                            value: m(summary.totalFat),
                            unit: 'г',
                            stacked: true,
                            onDarkSlab: true,
                          ),
                          InlineMacroCell(
                            type: NutrientType.carbs,
                            label: 'Углеводы',
                            value: m(summary.totalCarbs),
                            unit: 'г',
                            stacked: true,
                            onDarkSlab: true,
                          ),
                          InlineMacroCell(
                            type: NutrientType.kcal,
                            label: 'Энергия',
                            value: k(summary.totalKcal),
                            unit: 'ккал',
                            stacked: true,
                            onDarkSlab: true,
                          ),
                        ],
                      ),
                      if (summary.balance.hasEnergy) ...[
                        const SizedBox(height: Space.x3),
                        MacroBalanceBar(
                          key: const ValueKey('menu-macro-balance'),
                          balance: summary.balance,
                          onDarkSlab: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.x3),
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) Divider(color: p.divider, height: Space.x4),
                  Builder(
                    builder: (context) {
                      final item = _items[i];
                      final title = item.dish.title.trim().isEmpty
                          ? 'Блюдо без названия'
                          : item.dish.title.trim();
                      final macros = item.macros;
                      final yieldRounded =
                          CalculationMath.round1(item.calc.yieldGrams);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: AppTypography.body.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.usesWholeDish
                                ? 'Целое блюдо (выход не указан) · '
                                    'Б ${m(macros.protein)} · Ж ${m(macros.fat)} · '
                                    'У ${m(macros.carbs)} г · ${k(macros.kcal)} ккал'
                                : '${g(item.portionGrams)} г · '
                                    'Б ${m(macros.protein)} · Ж ${m(macros.fat)} · '
                                    'У ${m(macros.carbs)} г · ${k(macros.kcal)} ккал',
                            style: AppTypography.numSm
                                .copyWith(color: p.inkSecondary),
                          ),
                          if (!item.usesWholeDish) ...[
                            const SizedBox(height: Space.x2),
                            Row(
                              children: [
                                IconButton(
                                  key: ValueKey('menu-dec-${item.dish.id}'),
                                  tooltip: 'Уменьшить на 50 г',
                                  onPressed: () => _setPortion(
                                    i,
                                    math.max(10.0, item.portionGrams - 50),
                                  ),
                                  icon: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: p.inkSecondary,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${g(item.portionGrams)} г',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.num.copyWith(
                                      color: p.ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey('menu-inc-${item.dish.id}'),
                                  tooltip: 'Увеличить на 50 г',
                                  onPressed: () =>
                                      _setPortion(i, item.portionGrams + 50),
                                  icon: Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: p.accent,
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: Space.x2,
                              runSpacing: Space.x1,
                              children: [
                                for (final preset in _portionPresets)
                                  ChoiceChip(
                                    label: Text('$preset г'),
                                    selected: (item.portionGrams - preset).abs() <
                                        0.05,
                                    showCheckmark: false,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    onSelected: (_) =>
                                        _setPortion(i, preset.toDouble()),
                                  ),
                                ChoiceChip(
                                  label: Text('Всё (${g(yieldRounded)} г)'),
                                  selected:
                                      (item.portionGrams - yieldRounded).abs() <
                                          0.05,
                                  showCheckmark: false,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.padded,
                                  onSelected: (_) =>
                                      _setPortion(i, yieldRounded),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: Space.x4),
                FilledButton.icon(
                  key: const ValueKey('menu-copy-text-btn'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                  ),
                  onPressed: () async {
                    final text = formatMenuPlainText(_items, summary);
                    await Clipboard.setData(ClipboardData(text: text));
                    AppHaptics.commit();
                    if (!context.mounted) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    Navigator.pop(context);
                    messenger
                      ?..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Сводка меню скопирована'),
                        ),
                      );
                  },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Скопировать меню текстом'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
