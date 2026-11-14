import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/food_classifier.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/loss_group.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import '../widgets/app_buttons.dart';
import '../widgets/calc_error_banner.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/ingredient_card.dart';
import '../widgets/loss_clarity_hints.dart';
import '../widgets/macro_summary_bar.dart';
import '../widgets/persistence_error_banner.dart';
import '../widgets/yield_density_warning.dart';
import 'blank_preview_screen.dart';
import 'search_product_modal.dart';

class RecipeEditorScreen extends ConsumerStatefulWidget {
  const RecipeEditorScreen({super.key});

  @override
  ConsumerState<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

enum _ExitChoice { stay, discard, saveAndExit }

class _RecipeEditorScreenState extends ConsumerState<RecipeEditorScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _yieldCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final dish = ref.read(dishProvider);
    _syncControllers(dish);
  }

  void _syncControllers(Dish dish) {
    if (_titleCtrl.text != dish.title) {
      _titleCtrl.text = dish.title;
    }
    final expectedYield = dish.customYieldGrams != null
        ? CalculationEngine.formatGrams(dish.customYieldGrams!)
        : '';
    if (_yieldCtrl.text != expectedYield) {
      _yieldCtrl.text = expectedYield;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _yieldCtrl.dispose();
    super.dispose();
  }

  String? _yieldError;
  bool _yieldDetailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final calcError = ref.watch(calculationErrorProvider);
    final persistenceError = ref.watch(persistenceErrorProvider);
    final media = MediaQuery.sizeOf(context);
    final gutter = Space.gutter(media.width);
    final listHPad = math.max(gutter, (media.width - Space.maxWidth) / 2);

    ref.listen<Dish>(dishProvider, (previous, next) {
      if (previous?.id != next.id) {
        _syncControllers(next);
        setState(() => _yieldError = null);
      } else {
        if (previous?.title != next.title && _titleCtrl.text != next.title) {
          _titleCtrl.text = next.title;
        }
        if (previous?.customYieldGrams != next.customYieldGrams &&
            CalculationEngine.parseInputDouble(_yieldCtrl.text) !=
                next.customYieldGrams) {
          _yieldCtrl.text = next.customYieldGrams == null
              ? ''
              : CalculationEngine.formatGrams(next.customYieldGrams!);
        }
      }
    });

    final actions = _buildActions(dish);
    final isDirty = ref.read(dishProvider.notifier).isDirty;

    // Защита от тихой потери работы (аудит P0-3): системный «назад»,
    // жестовый back и кнопка в AppBar проходят через один и тот же вопрос.
    return PopScope(
      canPop: !isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscardChanges();
        if (!mounted || !leave) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          // Экран смонтирован как корень (домашняя) — «выйти» некуда,
          // но и терять нечего: сохраняем в библиотеку и сообщаем.
          try {
            await ref.read(dishProvider.notifier).saveCurrentToLibrary();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Черновик сохранён')),
            );
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Не удалось сохранить блюдо. Повторите попытку.'),
              ),
            );
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            dish.title.trim().isEmpty ? 'Новое блюдо' : dish.title.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          titleSpacing: 0,
          actions: actions,
        ),
        body: Column(
          children: [
            if (persistenceError != null)
              AppContentFrame(
                child: PersistenceErrorBanner(
                  margin: EdgeInsets.fromLTRB(gutter, Space.x2, gutter, Space.x1),
                  onRetry: () =>
                      ref.read(dishProvider.notifier).retryPersistence(),
                ),
              ),
            // STATE-01: баннер ошибки расчёта закреплён над лентой, поэтому
            // виден на любом скролле и при компактном экране.
            if (calcError != null)
              AppContentFrame(child: CalcErrorBanner(detail: calcError)),
            Expanded(
              child: ReorderableListView.builder(
                padding: EdgeInsets.fromLTRB(
                    listHPad, Space.x3, listHPad, Space.x6),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildParameters(dish, calc),
                    const SizedBox(height: Space.x5),
                    Text(
                      'Ингредиенты · ${dish.ingredients.length}',
                      style: AppTypography.headline.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: Space.x1),
                    if (dish.ingredients.isNotEmpty)
                      Text(
                        '⟷ перетащить · ← смахнуть, чтобы удалить',
                        style: AppTypography.caption.copyWith(color: p.inkMuted),
                      ),
                    const SizedBox(height: Space.x3),
                    if (dish.ingredients.isEmpty) _buildEmptyState(context),
                  ],
                ),
                itemCount: dish.ingredients.length,
                onReorder: (a, b) => ref
                    .read(dishProvider.notifier)
                    .reorderIngredients(a, b),
                itemBuilder: (context, index) {
                  final ing = dish.ingredients[index];
                  return Dismissible(
                    key: ValueKey(ing.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.all(Space.x6),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: Radii.cardAll,
                      ),
                      child: Icon(Icons.delete_outline, color: p.danger),
                    ),
                    onDismissed: (_) => _removeIngredient(ing, index),
                    child: IngredientCard(
                      index: index + 1,
                      ingredient: ing,
                      dragHandleIndex: index,
                      lossLabel: dish.process.isLegacy
                          ? null
                          : lossLabelFor(ing, dish.process),
                      onLossTap: dish.process.isLegacy
                          ? null
                          : () => _editIngredientLoss(context, ing.id),
                      onTap: () => _editIngredient(context, ing),
                      onDelete: () => _removeIngredient(ing, index),
                    ),
                  );
                },
              ),
            ),
            // Плоский нижний док: итоги + «Бланк» + «Добавить продукт».
            _buildBottomDock(calc, dish),
          ],
        ),
      ),
    );
  }

  /// Плоский нижний док редактора: краткий итог «После т.о.» + действия.
  Widget _buildBottomDock(CalculationResult? calc, Dish dish) {
    final p = Palette.of(context);
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackActions =
        (media.width < 380 && textScale > 1.3) || media.width < 300;
    final shortLandscape = media.height < 460 && media.width >= 560;
    final landscapeInline = shortLandscape;

    final summaryWidget = calc == null
        ? Text(
            'После т.о. · — Б — Ж — У — ккал',
            style: AppTypography.numSm.copyWith(color: p.inkMuted),
          )
        : MacroSummaryBar(
            key: ValueKey(dish.id),
            result: calc,
            compact: true,
          );

    final compactPad = landscapeInline
        ? const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          )
        : null;

    final blankBtn = OutlinedButton(
      onPressed: _openBlank,
      style: compactPad != null
          ? OutlinedButton.styleFrom(padding: compactPad)
          : null,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 18),
          SizedBox(width: Space.x2),
          Flexible(
            child: Text(
              'Бланк',
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );

    final addBtn = FilledButton(
      onPressed: () async {
        AppHaptics.commit();
        await SearchProductModal.show(
          context,
          mode: SearchMode.pickForRecipe,
        );
      },
      style:
          compactPad != null ? FilledButton.styleFrom(padding: compactPad) : null,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_rounded, size: 20),
          SizedBox(width: Space.x2),
          Flexible(
            child: Text(
              'Добавить продукт',
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );

    return AppBottomBar(
      padding: shortLandscape
          ? EdgeInsets.symmetric(
              horizontal: Space.gutter(media.width),
              vertical: Space.x1,
            )
          : null,
      child: landscapeInline
          ? Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: summaryWidget,
                  ),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  flex: 5,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        blankBtn,
                        const SizedBox(width: Space.x2),
                        Expanded(child: addBtn),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summaryWidget,
                const SizedBox(height: Space.x1),
                if (stackActions) ...[
                  addBtn,
                  const SizedBox(height: Space.x2),
                  blankBtn,
                ] else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        blankBtn,
                        const SizedBox(width: Space.x2),
                        Expanded(child: addBtn),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  List<Widget> _buildActions(Dish dish) {
    return [
      IconButton(
        icon: const Icon(Icons.tune_rounded),
        tooltip: 'Параметры',
        onPressed: () => _showRetentionSettingsDialog(context, dish),
      ),
      PopupMenuButton<String>(
        tooltip: 'Другие действия',
        onSelected: (value) async {
          if (value == 'save') {
            try {
              await ref.read(dishProvider.notifier).saveCurrentToLibrary();
              if (!mounted) return;
              AppHaptics.commit();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Блюдо сохранено в список рецептов')));
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Не удалось сохранить блюдо. Повторите попытку.')));
            }
          } else if (value == 'clear') {
            _showClearConfirmation(context);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'save', child: Text('Сохранить в мои блюда')),
          PopupMenuItem(value: 'clear', child: Text('Очистить рецепт')),
        ],
      ),
    ];
  }

  void _openBlank() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const BlankPreviewScreen()));
  }

  void _removeIngredient(Ingredient ingredient, int index) {
    final dishId = ref.read(dishProvider).id;
    ref.read(dishProvider.notifier).removeIngredient(ingredient.id);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Удалён: ${ingredient.product.name}'),
      action: SnackBarAction(
          label: 'Отменить',
          onPressed: () {
            if (ref.read(dishProvider).id == dishId) {
              ref
                  .read(dishProvider.notifier)
                  .restoreIngredient(ingredient, index);
            }
          }),
    ));
  }

  /// Группа таблицы потерь и способ обработки одного ингредиента.
  ///
  /// «Автоматически» — группа классификатора ([FoodClassifier.classify]),
  /// «Как у блюда» — способ блюда. Изменения применяются сразу
  /// (`setIngredientGroup` / `setIngredientProcess`) и сохраняются в документе.
  void _editIngredientLoss(BuildContext context, String ingredientId) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final dish = ref.watch(dishProvider);
        final matches = dish.ingredients.where((i) => i.id == ingredientId);
        if (matches.isEmpty) {
          return AlertDialog(
            content: const Text('Ингредиент удалён из блюда.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть')),
            ],
          );
        }
        final ing = matches.first;
        final notifier = ref.read(dishProvider.notifier);
        final auto = FoodClassifier.classify(ing.product);
        final process = ing.processIn(dish.process);
        final loss = LossTable.lossFor(ing.lossGroup, process);
        return AlertDialog(
          title: Text(ing.product.name,
              maxLines: 3, overflow: TextOverflow.ellipsis),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<LossGroup?>(
                  key: const ValueKey('ingredient-group'),
                  value: ing.groupOverride,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Группа продукта'),
                  items: [
                    DropdownMenuItem<LossGroup?>(
                        value: null,
                        child: Text('Автоматически: ${auto.label}',
                            softWrap: true)),
                    for (final g in LossGroup.values)
                      DropdownMenuItem<LossGroup?>(
                          value: g, child: Text(g.label, softWrap: true)),
                  ],
                  onChanged: (g) => notifier.setIngredientGroup(ing.id, g),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<HeatProcess?>(
                  key: const ValueKey('ingredient-process'),
                  value: ing.processOverride,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Способ обработки'),
                  items: [
                    DropdownMenuItem<HeatProcess?>(
                        value: null,
                        child: Text(
                            ing.product.isDishOnly
                                ? 'Готовое блюдо: без обработки'
                                : 'Как у блюда: ${dish.process.label}',
                            softWrap: true)),
                    for (final p in HeatProcess.ingredientChoices)
                      DropdownMenuItem<HeatProcess?>(
                          value: p, child: Text(p.label, softWrap: true)),
                  ],
                  onChanged: (p) => notifier.setIngredientProcess(ing.id, p),
                ),
                const SizedBox(height: 12),
                Text(
                  lossLabelFor(ing, dish.process),
                  key: const ValueKey('ingredient-loss-summary'),
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Источник: ${loss.source.title}'
                  '${loss.isVerified ? '' : '. Не подтверждено таблицей источника — ближайший аналог (${loss.note})'}.',
                  style: AppTypography.caption.copyWith(
                    color: Palette.of(ctx).inkSecondary,
                  ),
                ),
                if (LossClarityHints.forIngredient(
                      group: ing.lossGroup,
                      process: process,
                    )
                    case final String clarityHint) ...[
                  const SizedBox(height: Space.x2),
                  Container(
                    key: const ValueKey('ingredient-loss-clarity-hint'),
                    padding: const EdgeInsets.all(Space.x2),
                    decoration: BoxDecoration(
                      color: Palette.of(ctx).accentSoft,
                      borderRadius: Radii.fieldAll,
                      border: Border.all(color: Palette.of(ctx).borderStatic),
                    ),
                    child: Text(
                      clarityHint,
                      style: AppTypography.caption.copyWith(
                        color: Palette.of(ctx).ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Готово')),
          ],
        );
      }),
    );
  }

  double _cookedMacroMass(Dish dish,
      {double? protein, double? fat, double? carbs}) {
    final probe = dish.copyWith(
      customYieldGrams: 999999,
      retentionProtein: protein,
      retentionFat: fat,
      retentionCarbs: carbs,
    );
    final r = CalculationEngine.calculate(probe);
    return CalculationMath.sumRounded(
        [r.cookedProtein, r.cookedFat, r.cookedCarbs], 2);
  }

  /// Ввод веса готового блюда.
  ///
  /// Порог — [CalculationValidation.minCustomYieldGrams] (1 г): тот же, что у
  /// валидатора и [Dish.hasCustomYield] (реаудит RA-13/RA-23 — раньше поле
  /// принимало 0,1 г, а валидатор отвергал всё меньше 1 г).
  /// Новый расчёт (способ не legacy): пустое поле — «вес не указан», итог
  /// показывается на всё блюдо; приложение вес не угадывает.
  void _onYieldChanged(String value) {
    final dish = ref.read(dishProvider);
    final notifier = ref.read(dishProvider.notifier);
    if (!dish.process.isLegacy && value.trim().isEmpty) {
      setState(() => _yieldError = null);
      notifier.setCustomYield(null);
      return;
    }
    final parsed = CalculationEngine.parseInputDouble(value);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < CalculationValidation.minCustomYieldGrams ||
        parsed > CalculationValidation.maxCustomYieldGrams) {
      setState(() => _yieldError =
          'Введите выход не менее 1 г. Сохранён прежний выход.');
      return;
    }
    final macroMass = _cookedMacroMass(dish);
    if (parsed < macroMass) {
      setState(() => _yieldError =
          'Выход меньше суммарной массы БЖУ после т.о. '
          '(${CalculationEngine.formatMacro(macroMass)} г). '
          '${dish.process.isLegacy ? 'Сохранён прежний выход — увеличьте выход или уменьшите сохранность.' : 'Сохранён прежний выход — проверьте вес готового блюда.'}');
      return;
    }
    setState(() => _yieldError = null);
    notifier.setCustomYield(parsed);
  }

  static double _safeGrams(double Function() read) {
    try {
      final v = read();
      return v.isFinite ? v : 0;
    } on ArgumentError {
      return 0;
    }
  }

  Widget _buildParameters(Dish dish, CalculationResult? calc) {
    final p = Palette.of(context);
    final legacy = dish.process.isLegacy;
    final custom = dish.customYieldGrams != null;
    // Новый расчёт: поле веса готового блюда видно всегда (вес вводит повар).
    // Старый расчёт (legacy): прежний переключатель «Задать фактический выход».
    final showYieldField = custom || !legacy;
    final rawNet = _safeGrams(() => dish.totalRawNetGrams);
    final effYield = _safeGrams(() => dish.effectiveYieldGrams);
    final explanation = YieldExplanation(rawNet, effYield);

    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) => ref.read(dishProvider.notifier).setTitle(value),
            decoration: const InputDecoration(
              labelText: 'Название блюда',
              hintText: 'Например, борщ с капустой и картофелем',
            ),
          ),
          const SizedBox(height: Space.x2),
          InkWell(
            key: const ValueKey('heat-process-row'),
            onTap: () => _showRetentionSettingsDialog(context, dish),
            borderRadius: Radii.fieldAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_outlined,
                      size: 18, color: p.inkSecondary),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      'Обработка: ${dish.process.label}',
                      style: AppTypography.bodySm.copyWith(color: p.ink),
                    ),
                  ),
                  Text(
                    'Изменить',
                    style: AppTypography.label.copyWith(color: p.inkSecondary),
                  ),
                  const SizedBox(width: Space.x1),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: p.inkMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x1),
          Text(
            legacy || dish.hasCustomYield
                ? 'Выход готового блюда: ${CalculationEngine.formatGrams(effYield)} г'
                : 'Вес готового блюда не указан',
            style: AppTypography.headline.copyWith(color: p.ink),
          ),
          if (legacy)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              title: const Text('Задать фактический выход'),
              subtitle: Text(
                custom
                    ? 'Ручной выход • нетто сырья ${CalculationEngine.formatGrams(rawNet)} г'
                    : 'Автоматически: сумма нетто ингредиентов',
                style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
              value: custom,
              onChanged: (enabled) {
                if (enabled && rawNet <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Сначала добавьте ингредиенты')));
                  return;
                }
                ref
                    .read(dishProvider.notifier)
                    .setCustomYield(enabled ? effYield : null);
                _yieldCtrl.text = enabled
                    ? CalculationEngine.formatGrams(effYield)
                    : '';
                setState(() => _yieldError = null);
              },
            ),
          if (showYieldField) ...[
            const SizedBox(height: Space.x2),
            TextField(
              key: const ValueKey('actual-yield'),
              controller: _yieldCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.num.copyWith(color: p.ink),
              decoration: InputDecoration(
                labelText: legacy
                    ? 'Фактический выход готового блюда'
                    : 'Вес готового блюда',
                hintText: legacy ? null : 'Взвесьте готовое блюдо',
                helperText: legacy
                    ? null
                    : 'Нужен для расчёта на 100 г и на порцию',
                helperMaxLines: 2,
                suffixText: 'г',
                errorMaxLines: 3,
                errorText: _yieldError,
              ),
              onChanged: _onYieldChanged,
            ),
          ],
          if (calc != null &&
              CalculationValidation.warnsImpossiblePer100g(calc)) ...[
            const SizedBox(height: Space.x2),
            YieldDensityWarning(
              key: const ValueKey('yield-density-warning'),
              result: calc,
            ),
          ],
          if (showYieldField && (legacy || rawNet > 0)) ...[
            const SizedBox(height: Space.x2),
            InkWell(
              key: const ValueKey('yield-explanation'),
              onTap: () => setState(
                () => _yieldDetailsExpanded = !_yieldDetailsExpanded,
              ),
              borderRadius: Radii.fieldAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTapTarget),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x3,
                    vertical: Space.x2,
                  ),
                  decoration: BoxDecoration(
                    color: p.sunken,
                    borderRadius: Radii.fieldAll,
                    border: Border.all(color: p.borderStatic),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              explanation.badge,
                              style: AppTypography.label.copyWith(color: p.ink),
                            ),
                          ),
                          Icon(
                            _yieldDetailsExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: p.inkMuted,
                          ),
                        ],
                      ),
                      if (_yieldDetailsExpanded) ...[
                        const SizedBox(height: Space.x1),
                        Text(
                          explanation.description,
                          style: AppTypography.bodySm
                              .copyWith(color: p.inkSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x5,
        vertical: Space.x6,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: p.sunken,
              borderRadius: Radii.cardAll,
            ),
            child: Icon(
              Icons.restaurant_menu_rounded,
              size: 28,
              color: p.ink,
            ),
          ),
          const SizedBox(height: Space.x3),
          Text(
            'Рецепт пока пуст',
            style: AppTypography.title.copyWith(color: p.ink),
          ),
          const SizedBox(height: Space.x2),
          Text(
            'Нажмите «Добавить продукт», чтобы выбрать ингредиенты из '
            'справочника Скурихина и базы BLS 4.0.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: p.inkSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _editIngredient(BuildContext context, Ingredient ing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomNumpadSheet(
        product: ing.product,
        initialGrams: ing.weightGrams,
        initialIsGross: ing.isGross,
        isEditing: true,
        onProductUpdated: (updatedProduct) {
          ref.read(dishProvider.notifier).updateIngredient(
                ing.id,
                ing.weightGrams,
                isGross: ing.isGross,
                product: updatedProduct,
              );
        },
        onConfirm: (grams, isGross) {
          ref.read(dishProvider.notifier).updateIngredient(
                ing.id,
                grams,
                isGross: isGross,
              );
        },
      ),
    );
  }

  /// Подтверждение выхода с несохранёнными правками (аудит P0-3).
  Future<bool> _confirmDiscardChanges() async {
    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Не сохранять изменения?'),
        content: const Text(
          'В блюде есть несохранённые правки. Если выйти сейчас, они пропадут.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitChoice.stay),
            child: const Text('Продолжить редактирование'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitChoice.discard),
            child: const Text('Выйти без сохранения'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(dishProvider.notifier).saveCurrentToLibrary();
                if (ctx.mounted) Navigator.pop(ctx, _ExitChoice.saveAndExit);
              } catch (_) {
                if (ctx.mounted) Navigator.pop(ctx, _ExitChoice.stay);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Не удалось сохранить блюдо. Изменения не закрыты — повторите попытку.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Сохранить и выйти'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _ExitChoice.stay) return false;
    AppHaptics.commit();
    return true;
  }

  void _showRetentionSettingsDialog(BuildContext context, Dish dish) {
    final pCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(dish.retentionProtein),
    );
    final fCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(dish.retentionFat),
    );
    final cCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(dish.retentionCarbs),
    );
    bool showPer100g = dish.showPer100gRowInExport;
    bool showTitleInExport = dish.showTitleInExport;
    BlankMode blankMode = dish.blankMode;
    String? retentionError;

    void fillRetention(double protein, double fat, double carbs) {
      pCtrl.text = CalculationEngine.formatPercent(protein);
      fCtrl.text = CalculationEngine.formatPercent(fat);
      cCtrl.text = CalculationEngine.formatPercent(carbs);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final p = Palette.of(ctx);
          final currentProcess = ref.read(dishProvider).process;
          final legacy = currentProcess.isLegacy;
          final processNote = LossClarityHints.forDishProcess(currentProcess);
          final denseDialog = MediaQuery.textScalerOf(ctx).scale(1) <= 1.2;
          return AlertDialog(
            title: const Text('Параметры расчета и бланка'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Способ тепловой обработки',
                    style: AppTypography.label.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: Space.x2),
                  DropdownButtonFormField<HeatProcess>(
                    key: const ValueKey('heat-process'),
                    isDense: denseDialog,
                    itemHeight: null,
                    value: ref.read(dishProvider).process,
                    isExpanded: true,
                    decoration: InputDecoration(isDense: denseDialog),
                    items: HeatProcess.values
                        .map((proc) => DropdownMenuItem(
                            value: proc,
                            child: Text(proc.label, softWrap: true)))
                        .toList(),
                    onChanged: (proc) {
                      if (proc == null) return;
                      ref.read(dishProvider.notifier).setHeatProcess(proc);
                      setDialogState(() {
                        retentionError = null;
                        final s = ref.read(dishProvider);
                        if (s.process.isLegacy) {
                          fillRetention(s.retentionProtein, s.retentionFat,
                              s.retentionCarbs);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: Space.x1),
                  Text(
                    legacy
                        ? 'Старый расчёт: одна тройка сохранности на всё '
                            'блюдо (по умолчанию 94/88/91 %), выход = сумма '
                            'нетто, если вес готового блюда не указан.'
                        : 'Потери белков, жиров и углеводов — по таблице '
                            'потерь для группы каждого продукта (МР '
                            '2.3.0419-26). Вес готового блюда вводите сами.',
                    key: const ValueKey('process-hint'),
                    style: AppTypography.caption.copyWith(
                      color: p.inkSecondary,
                    ),
                  ),
                  if (processNote != null) ...[
                    const SizedBox(height: Space.x2),
                    Container(
                      key: const ValueKey('process-clarity-hint'),
                      padding: const EdgeInsets.all(Space.x2),
                      decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: Radii.fieldAll,
                        border: Border.all(color: p.borderStatic),
                      ),
                      child: Text(
                        processNote,
                        style: AppTypography.caption.copyWith(color: p.ink),
                      ),
                    ),
                  ],
                  if (legacy) ...[
                    const SizedBox(height: Space.x4),
                    Text(
                      'Коэффициенты сохранности нутриентов при т.о. (%)',
                      style: AppTypography.label.copyWith(color: p.ink),
                    ),
                    const SizedBox(height: Space.x1),
                    Text(
                      'Одна тройка на всё блюдо — так считались рецептуры '
                      'до 03.11.2026. 94/88/91 % — средние потери 6/12/9 % '
                      '(МР 2.3.0419-26, прил. 5).',
                      style: AppTypography.caption.copyWith(
                        color: p.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: Space.x2),
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x2,
                      children: [
                        ActionChip(
                          label: const Text('Старый расчёт (94/88/91%)'),
                          onPressed: () => setDialogState(() => fillRetention(
                              kLegacyRetentionProtein,
                              kLegacyRetentionFat,
                              kLegacyRetentionCarbs)),
                        ),
                        ActionChip(
                          label: const Text('Без потерь (100%)'),
                          onPressed: () =>
                              setDialogState(() => fillRetention(1, 1, 1)),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x3),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Белки %',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: TextField(
                            controller: fCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Жиры %',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: TextField(
                            controller: cCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Углев. %',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (retentionError != null) ...[
                      const SizedBox(height: Space.x2),
                      Text(
                        retentionError!,
                        style: AppTypography.caption.copyWith(color: p.danger),
                      ),
                    ],
                  ],
                  const SizedBox(height: Space.x4),
                  DropdownButtonFormField<BlankMode>(
                    isDense: denseDialog,
                    itemHeight: null,
                    value: blankMode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Режим бланка'),
                    items: BlankMode.values
                        .map((mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(mode.shortName, softWrap: true)))
                        .toList(),
                    onChanged: (mode) {
                      if (mode != null) {
                        setDialogState(() => blankMode = mode);
                      }
                    },
                  ),
                  const SizedBox(height: Space.x2),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    title: Text(
                      'Печатать название в заголовке бланка',
                      style: AppTypography.bodySm.copyWith(color: p.ink),
                    ),
                    value: showTitleInExport,
                    onChanged: (val) =>
                        setDialogState(() => showTitleInExport = val),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    title: Text(
                      'Строка «В 100 г блюда» в бланке',
                      style: AppTypography.bodySm.copyWith(color: p.ink),
                    ),
                    subtitle: Text(
                      'По умолчанию скрыта для 1:1 совпадения с типовым бланком',
                      style: AppTypography.caption.copyWith(
                        color: p.inkSecondary,
                      ),
                    ),
                    value: showPer100g,
                    onChanged: (val) => setDialogState(() => showPer100g = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  final notifier = ref.read(dishProvider.notifier);
                  final current = ref.read(dishProvider);
                  if (!current.process.isLegacy) {
                    notifier.setBlankMode(blankMode);
                    notifier.toggleShowTitle(showTitleInExport);
                    notifier.toggleShowPer100gRow(showPer100g);
                    Navigator.pop(ctx);
                    return;
                  }
                  final values = [pCtrl.text, fCtrl.text, cCtrl.text]
                      .map(CalculationEngine.parseInputDouble)
                      .toList();
                  // B1.2: сохранность 0 % физически невозможна (весь нутриент
                  // исчез), поэтому нижняя граница — 1 %, как в валидаторе.
                  if (values.any((v) => v == null || v < 1 || v > 100)) {
                    setDialogState(() => retentionError =
                        'Введите каждый процент от 1 до 100.');
                    return;
                  }
                  final pVal = values[0]! / 100;
                  final fVal = values[1]! / 100;
                  final cVal = values[2]! / 100;
                  final mass = _cookedMacroMass(current,
                      protein: pVal, fat: fVal, carbs: cVal);
                  if (mass > current.effectiveYieldGrams) {
                    setDialogState(() => retentionError =
                        'При этих коэффициентах масса БЖУ после т.о. '
                        '${CalculationEngine.formatMacro(mass)} г превышает выход '
                        '${CalculationEngine.formatGrams(current.effectiveYieldGrams)} г. '
                        'Увеличьте выход или уменьшите сохранность.');
                    return;
                  }
                  notifier.setRetention(
                    protein: pVal,
                    fat: fVal,
                    carbs: cVal,
                  );
                  notifier.setBlankMode(blankMode);
                  notifier.toggleShowTitle(showTitleInExport);
                  notifier.toggleShowPer100gRow(showPer100g);
                  Navigator.pop(ctx);
                },
                child: const Text('Применить'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showClearConfirmation(BuildContext context) {
    final p = Palette.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить рецепт?'),
        content: const Text(
            'Все добавленные ингредиенты будут удалены из текущего бланка.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              ref.read(dishProvider.notifier).clearAll();
              _titleCtrl.clear();
              _yieldCtrl.clear();
              Navigator.pop(ctx);
            },
            child: Text('Очистить', style: TextStyle(color: p.danger)),
          ),
        ],
      ),
    );
  }
}

