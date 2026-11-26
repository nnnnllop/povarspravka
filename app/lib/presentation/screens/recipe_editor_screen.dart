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
import '../providers/search_provider.dart';
import '../widgets/app_buttons.dart';
import '../widgets/calc_error_banner.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/custom_product_form_sheet.dart';
import '../widgets/ingredient_card.dart';
import '../widgets/instrument_widgets.dart';
import '../widgets/loss_clarity_hints.dart';
import '../widgets/macro_summary_bar.dart';
import '../widgets/persistence_error_banner.dart';
import '../widgets/share_recipe_sheet.dart';
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
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final dish = ref.read(dishProvider);
    _syncControllers(dish);
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final offset = _scrollCtrl.offset;
    if (!_showCollapsedKcal && offset > 168) {
      setState(() => _showCollapsedKcal = true);
    } else if (_showCollapsedKcal && offset < 152) {
      setState(() => _showCollapsedKcal = false);
    }
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
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _titleCtrl.dispose();
    _yieldCtrl.dispose();
    super.dispose();
  }

  String? _yieldError;
  bool _yieldDetailsExpanded = false;
  bool _showCollapsedKcal = false;
  bool _isReordering = false;

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

    final isDirty = ref.read(dishProvider.notifier).isDirty;
    final actions = _buildActions(dish, isDirty, calc);

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
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, prefix: 'Не удалось сохранить блюдо'),
                ),
              ),
            );
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: Motion.fast,
            child: (_showCollapsedKcal && calc != null)
                ? Row(
                    key: const ValueKey('appbar-collapsed-kcal'),
                    children: [
                      Expanded(
                        child: Text(
                          dish.title.trim().isEmpty
                              ? 'Техкарта'
                              : dish.title.trim(),
                          style: AppTypography.headline.copyWith(color: p.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (media.width >= 340) ...[
                        const SizedBox(width: Space.x2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.x2 + 2,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: p.slab,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            calc.hasYield
                                ? '${CalculationEngine.formatKcal(calc.per100gKcal)} / 100 г'
                                : '${CalculationEngine.formatKcal(calc.cookedKcal)} ккал',
                            style: AppTypography.caption.copyWith(
                              color: p.slabInk,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ],
                  )
                : Align(
                    key: const ValueKey('appbar-idle-title'),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Техкарта',
                      style: AppTypography.headline
                          .copyWith(color: p.inkSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                scrollController: _scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                    listHPad, Space.x1, listHPad, Space.x6),
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Material(
                        color: p.surface,
                        elevation: 6,
                        shadowColor: Colors.black.withOpacity(0.18),
                        borderRadius: Radii.cardAll,
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTypography.title.copyWith(
                        color: p.ink,
                        fontSize: 19,
                      ),
                      onChanged: (value) =>
                          ref.read(dishProvider.notifier).setTitle(value),
                      decoration: InputDecoration(
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Название блюда',
                        hintStyle: AppTypography.title.copyWith(
                          color: p.inkMuted,
                          fontSize: 19,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 2),
                      ),
                    ),
                    const SizedBox(height: Space.x1 + 2),
                    if (calc != null)
                      MacroSummaryBar(
                        key: ValueKey(dish.id),
                        result: calc,
                        hero: true,
                        ingredients: dish.ingredients,
                      ),
                    if (calc != null) const SizedBox(height: Space.x4),
                    _buildParameters(dish, calc),
                    const SizedBox(height: Space.x4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'Ингредиенты · ${dish.ingredients.length}',
                                style:
                                    AppTypography.headline.copyWith(color: p.ink),
                              ),
                            ),
                            if (dish.ingredients.length > 1)
                              TextButton.icon(
                                key: const ValueKey('toggle-reorder-btn'),
                                onPressed: () {
                                  AppHaptics.toggle();
                                  setState(
                                      () => _isReordering = !_isReordering);
                                },
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, kMinTapTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: Space.x2),
                                ),
                                icon: Icon(
                                  _isReordering
                                      ? Icons.check_rounded
                                      : Icons.reorder_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _isReordering ? 'Готово' : 'Порядок',
                                ),
                              ),
                          ],
                        ),
                        if (!dish.process.isLegacy &&
                            dish.ingredients.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'КБЖУ в строках указано до готовки (по нетто сырья)',
                              style: AppTypography.caption
                                  .copyWith(color: p.inkMuted),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                    if (dish.ingredients.isEmpty) _buildEmptyState(context),
                  ],
                ),
                itemCount: dish.ingredients.length,
                onReorder: (a, b) => ref
                    .read(dishProvider.notifier)
                    .reorderIngredients(a, b),
                itemBuilder: (context, index) {
                  final ing = dish.ingredients[index];
                  String? inlineLossLabel;
                  if (!dish.process.isLegacy) {
                    final proc = ing.processIn(dish.process);
                    final loss = LossTable.lossFor(ing.lossGroup, proc);
                    final isCustomOrUnverified = ing.groupOverride != null ||
                        ing.processOverride != null ||
                        !loss.isVerified;
                    if (isCustomOrUnverified) {
                      inlineLossLabel = lossLabelFor(ing, dish.process);
                    }
                  }
                  return Dismissible(
                    key: ValueKey(ing.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.all(Space.x6),
                      decoration: BoxDecoration(
                        color: p.dangerSoft,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(index == 0 ? Radii.card : 0),
                          bottom: Radius.circular(
                            index == dish.ingredients.length - 1
                                ? Radii.card
                                : 0,
                          ),
                        ),
                      ),
                      child: Icon(Icons.delete_outline, color: p.danger),
                    ),
                    onDismissed: (_) => _removeIngredient(ing, index),
                    child: IngredientCard(
                      index: index + 1,
                      ingredient: ing,
                      dragHandleIndex: _isReordering ? index : null,
                      isFirst: index == 0,
                      isLast: index == dish.ingredients.length - 1,
                      lossLabel: inlineLossLabel,
                      onLossTap: dish.process.isLegacy
                          ? null
                          : () => _editIngredientLoss(context, ing.id),
                      onTap: () => _editIngredient(context, ing, index),
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

  /// Парящий нижний док редактора: компактные действия «Бланк» + «Добавить продукт».
  Widget _buildBottomDock(CalculationResult? calc, Dish dish) {
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackActions =
        (media.width < 380 && textScale > 1.3) || media.width < 300;
    final shortLandscape = media.height < 460 && media.width >= 560;
    final compactDock = shortLandscape || (stackActions && media.height < 640);
    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(stackActions ? Radii.field : 999),
    );

    final compactPad = compactDock
        ? const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          )
        : null;

    final blankBtn = OutlinedButton(
      onPressed: _openBlank,
      style: OutlinedButton.styleFrom(
        padding: compactPad,
        shape: pillShape,
      ),
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
      style: FilledButton.styleFrom(
        padding: compactPad,
        shape: pillShape,
      ),
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

    final p = Palette.of(context);
    final buttonsWidget = stackActions
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              addBtn,
              SizedBox(height: compactDock ? Space.x1 : Space.x2),
              blankBtn,
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: blankBtn),
                const SizedBox(width: Space.x2),
                Expanded(flex: 3, child: addBtn),
              ],
            ),
          );

    // STATE-01: при невычислимом сохранённом документе показываем прочерки
    // вместо нуля или молчаливого скрытия, закреплённые в доке при любом скролле.
    final showNullSummary = calc == null && dish.ingredients.isNotEmpty;

    return AppBottomBar(
      floating: !compactDock,
      padding: compactDock
          ? EdgeInsets.symmetric(
              horizontal: Space.gutter(media.width),
              vertical: Space.x1,
            )
          : null,
      child: showNullSummary
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'После готовки · — Б — Ж — У — ккал',
                  style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: Space.x2),
                buttonsWidget,
              ],
            )
          : buttonsWidget,
    );
  }

  Future<void> _saveToLibrary() async {
    try {
      await ref.read(dishProvider.notifier).saveCurrentToLibrary();
      if (!mounted) return;
      AppHaptics.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Блюдо сохранено в «Мои блюда»')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(e, prefix: 'Не удалось сохранить блюдо'),
          ),
        ),
      );
    }
  }

  List<Widget> _buildActions(
    Dish dish,
    bool isDirty,
    CalculationResult? calc,
  ) {
    final p = Palette.of(context);
    final isSavedInLibrary =
        ref.watch(savedDishesProvider).any((d) => d.id == dish.id);
    final hasContent =
        dish.ingredients.isNotEmpty || dish.title.trim().isNotEmpty;
    final needsSave = (isDirty || !isSavedInLibrary) && hasContent;

    return [
      IconButton(
        key: const ValueKey('save-recipe-btn'),
        icon: Icon(
          needsSave ? Icons.bookmark_add_outlined : Icons.bookmark_added_rounded,
          color: needsSave ? p.accent : null,
        ),
        tooltip: 'Сохранить в мои блюда',
        onPressed: hasContent ? _saveToLibrary : null,
      ),
      PopupMenuButton<String>(
        tooltip: 'Другие действия',
        onSelected: (value) {
          if (value == 'params') {
            _showRetentionSettingsDialog(context, dish);
          } else if (value == 'reorder') {
            AppHaptics.toggle();
            setState(() => _isReordering = !_isReordering);
          } else if (value == 'scale') {
            _openScaleDialog(dish);
          } else if (value == 'semi') {
            _saveAsSemiFinished(dish);
          } else if (value == 'share-recipe') {
            ShareRecipeSheet.show(
              context,
              dish: dish,
              customProducts: ref.read(customProductsProvider),
            );
          } else if (value == 'clear') {
            _showClearConfirmation(context);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'params',
            child: Text('Параметры обработки и бланка'),
          ),
          if (dish.ingredients.length > 1)
            PopupMenuItem(
              value: 'reorder',
              child: Text(_isReordering
                  ? 'Закончить сортировку'
                  : 'Изменить порядок ингредиентов'),
            ),
          PopupMenuItem(
            value: 'scale',
            enabled: dish.ingredients.isNotEmpty,
            child: const Text('Масштабировать веса'),
          ),
          PopupMenuItem(
            value: 'semi',
            enabled: dish.ingredients.isNotEmpty,
            child: const Text('Сохранить как полуфабрикат'),
          ),
          PopupMenuItem(
            value: 'share-recipe',
            enabled: hasContent,
            child: const Text('Поделиться рецептом'),
          ),
          PopupMenuItem(
            value: 'clear',
            enabled: hasContent,
            child: const Text('Очистить рецепт'),
          ),
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

  static double _cookedMacroMass(Dish dish,
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
          'Выход меньше суммарной массы БЖУ после готовки '
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

  Widget _buildParameters(
    Dish dish,
    CalculationResult? calc,
  ) {
    final p = Palette.of(context);
    final legacy = dish.process.isLegacy;
    final custom = dish.customYieldGrams != null;
    // Новый расчёт: поле веса готового блюда видно всегда (вес вводит повар).
    // Старый расчёт (legacy): прежний переключатель «Задать фактический выход».
    final showYieldField = custom || !legacy;
    final rawNet = _safeGrams(() => dish.totalRawNetGrams);
    final effYield = _safeGrams(() => dish.effectiveYieldGrams);
    final explanation = YieldExplanation(rawNet, effYield);
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackYieldRow = media.width < 340 || textScale > 1.35;
    final catLabel = DishCategories.labelOf(dish.category);

    final yieldInput = TextField(
      key: const ValueKey('actual-yield'),
      controller: _yieldCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: stackYieldRow ? TextAlign.start : TextAlign.end,
      style: AppTypography.num.copyWith(color: p.ink),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: 9,
        ),
        hintText: '—',
        suffixText: ' г',
        suffixIcon: IconButton(
          key: const ValueKey('yield-numpad-btn'),
          tooltip: 'Ввести на цифровой клавиатуре',
          icon: Icon(Icons.dialpad_rounded, size: 19, color: p.inkSecondary),
          onPressed: () => _openYieldNumpad(dish),
        ),
      ),
      onChanged: _onYieldChanged,
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('heat-process-row'),
          onTap: () => _showRetentionSettingsDialog(context, dish),
          borderRadius: Radii.fieldAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_outlined,
                      size: 18, color: p.accent),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      catLabel == null
                          ? 'Обработка: ${dish.process.label}'
                          : 'Обработка: ${dish.process.label} · $catLabel',
                      style: AppTypography.bodySm.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.inkMuted),
                ],
              ),
            ),
          ),
        ),
        Divider(color: p.divider, height: Space.x2),
        if (legacy) ...[
          if (!custom)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x1),
              child: Text(
                'Выход готового блюда: ${CalculationEngine.formatGrams(effYield)} г',
                style: AppTypography.bodySm.copyWith(
                  color: p.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            title: const Text('Задать фактический выход'),
            subtitle: Text(
              custom
                  ? 'Ручной выход · нетто сырья ${CalculationEngine.formatGrams(rawNet)} г'
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
        ],
        if (showYieldField) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: stackYieldRow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        legacy ? 'Фактический выход' : 'Вес готового блюда',
                        style: AppTypography.bodySm.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Space.x1),
                      yieldInput,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              legacy
                                  ? 'Фактический выход'
                                  : 'Вес готового блюда',
                              style: AppTypography.bodySm.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!legacy && rawNet > 0)
                              Text(
                                'Сырьё нетто ${CalculationEngine.formatGrams(rawNet)} г',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkMuted),
                              )
                            else if (!legacy && !dish.hasCustomYield)
                              Text(
                                'Для расчёта на 100 г и на порцию',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkMuted),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      SizedBox(width: 148, child: yieldInput),
                    ],
                  ),
          ),
          if (_yieldError != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: Space.x1),
              child: Text(
                _yieldError!,
                style: AppTypography.caption.copyWith(color: p.danger),
              ),
            ),
        ],
        if (calc != null &&
            CalculationValidation.warnsImpossiblePer100g(calc)) ...[
          const SizedBox(height: Space.x1),
          YieldDensityWarning(
            key: const ValueKey('yield-density-warning'),
            result: calc,
          ),
        ],
        if (showYieldField && (legacy || rawNet > 0)) ...[
          const SizedBox(height: Space.x1),
          Divider(color: p.divider, height: 1),
          InkWell(
            key: const ValueKey('yield-explanation'),
            onTap: () => setState(
              () => _yieldDetailsExpanded = !_yieldDetailsExpanded,
            ),
            borderRadius: Radii.fieldAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
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
    );

    return GroupedSurface(
      padding: const EdgeInsets.all(Space.x3),
      child: body,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final p = Palette.of(context);
    return GroupedSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x5,
        vertical: Space.x6,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: Icon(
              Icons.restaurant_menu_rounded,
              size: 26,
              color: p.accent,
            ),
          ),
          const SizedBox(height: Space.x3),
          Text(
            'Рецепт пока пуст',
            style: AppTypography.title.copyWith(color: p.ink),
          ),
          const SizedBox(height: Space.x1),
          Text(
            'Нажмите «Добавить продукт», чтобы выбрать ингредиенты.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: p.inkSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  void _openYieldNumpad(Dish dish) {
    FocusManager.instance.primaryFocus?.unfocus();
    final macroMass = _cookedMacroMass(dish);
    final minGrams = math.max(
      CalculationValidation.minCustomYieldGrams,
      macroMass,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: MediaQuery.sizeOf(context).height >= 460,
      backgroundColor: Palette.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => SimpleGramsNumpadSheet(
        title: dish.process.isLegacy
            ? 'Фактический выход'
            : 'Вес готового блюда',
        subtitle: macroMass > 0
            ? 'Минимум ${CalculationEngine.formatMacro(macroMass)} г (сумма БЖУ после готовки)'
            : 'Для расчёта на 100 г и на порцию',
        initialGrams: dish.customYieldGrams,
        minGrams: minGrams,
        maxGrams: CalculationValidation.maxCustomYieldGrams,
        onClearValue: dish.process.isLegacy
            ? null
            : () {
                _yieldCtrl.clear();
                ref.read(dishProvider.notifier).setCustomYield(null);
                setState(() => _yieldError = null);
              },
        onConfirm: (grams) {
          final formatted = CalculationEngine.formatGrams(grams);
          _yieldCtrl.text = formatted;
          setState(() => _yieldError = null);
          ref.read(dishProvider.notifier).setCustomYield(grams);
        },
      ),
    );
  }

  void _editIngredient(BuildContext context, Ingredient ing, int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: MediaQuery.sizeOf(context).height >= 460,
      backgroundColor: Palette.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
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
        onEditLoss: ref.read(dishProvider).process.isLegacy
            ? null
            : () {
                Navigator.pop(context);
                _editIngredientLoss(context, ing.id);
              },
        onReplaceProduct: () => _replaceIngredientProduct(ing),
        onDelete: () => _removeIngredient(ing, index),
      ),
    );
  }

  Future<void> _replaceIngredientProduct(Ingredient ing) async {
    final replacement = await SearchProductModal.pickReplacement(
      context,
      replacingName: ing.product.name,
    );
    if (!mounted || replacement == null) return;
    final dishId = ref.read(dishProvider).id;
    final prevProduct = ing.product;
    final prevGroup = ing.groupOverride;
    final ok = ref
        .read(dishProvider.notifier)
        .replaceIngredientProduct(ing.id, replacement);
    if (!ok) return;
    recordRecentProduct(ref, replacement);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Заменено: ${prevProduct.name} → ${replacement.name}'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () {
              if (ref.read(dishProvider).id != dishId) return;
              final notifier = ref.read(dishProvider.notifier);
              notifier.replaceIngredientProduct(ing.id, prevProduct);
              if (prevGroup != null) {
                notifier.setIngredientGroup(ing.id, prevGroup);
              }
            },
          ),
        ),
      );
  }

  /// Подтверждение выхода с несохранёнными правками (аудит P0-3).
  Future<bool> _confirmDiscardChanges() async {
    final p = Palette.of(context);
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
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExitChoice.discard),
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Выйти без сохранения'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(dishProvider.notifier).saveCurrentToLibrary();
                if (ctx.mounted) Navigator.pop(ctx, _ExitChoice.saveAndExit);
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx, _ExitChoice.stay);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        friendlyErrorMessage(
                          e,
                          prefix: 'Не удалось сохранить блюдо',
                        ),
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
    if (choice == _ExitChoice.discard) {
      ref.read(dishProvider.notifier).discardChanges();
    }
    AppHaptics.commit();
    return true;
  }

  void _showRetentionSettingsDialog(BuildContext context, Dish dish) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => _RecipeSettingsDialog(initialDish: dish),
    );
  }

  Future<void> _saveAsSemiFinished(Dish dish) async {
    final calc = ref.read(calculationResultProvider);
    if (calc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала исправьте ошибки в параметрах блюда'),
        ),
      );
      return;
    }
    if (!calc.hasYield) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Укажите вес готового блюда для пересчёта на 100 г',
          ),
        ),
      );
      return;
    }
    final created = await CustomProductFormSheet.show(
      context,
      initialName: dish.title.trim().isNotEmpty
          ? dish.title.trim()
          : 'Полуфабрикат',
      initialProtein: calc.per100gProtein,
      initialFat: calc.per100gFat,
      initialCarbs: calc.per100gCarbs,
      initialKcal: calc.per100gKcal,
      initialWastePct: 0.0,
      initialIsDish: true,
      sheetTitle: 'Сохранить как полуфабрикат',
      sheetSubtitle:
          'Пищевая ценность на 100 г готового блюда сохранится в «Свои продукты».',
    );
    if (!mounted || created == null) return;
    recordRecentProduct(ref, created);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Сохранено в «Свои продукты»: ${created.name}'),
        ),
      );
  }

  Future<void> _openScaleDialog(Dish dish) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    final res = await showModalBottomSheet<({double factor, bool scaleYield})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => _ScaleRecipeSheet(dish: dish),
    );
    if (!mounted || res == null) return;
    final previous = ref.read(dishProvider);
    final ok = ref.read(dishProvider.notifier).scaleIngredients(
          res.factor,
          scaleCustomYield: res.scaleYield,
        );
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось масштабировать: веса выходят за допустимые границы',
          ),
        ),
      );
      return;
    }
    AppHaptics.commit();
    final factorLabel = CalculationEngine.formatGrams(res.factor);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Вес ингредиентов изменён в $factorLabel×'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () {
              ref.read(dishProvider.notifier).restoreIngredientsSnapshot(
                    dishId: previous.id,
                    ingredients: previous.ingredients,
                    customYieldGrams: previous.customYieldGrams,
                  );
            },
          ),
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

class _RecipeSettingsDialog extends ConsumerStatefulWidget {
  final Dish initialDish;

  const _RecipeSettingsDialog({required this.initialDish});

  @override
  ConsumerState<_RecipeSettingsDialog> createState() =>
      _RecipeSettingsDialogState();
}

class _RecipeSettingsDialogState extends ConsumerState<_RecipeSettingsDialog> {
  late final TextEditingController _pCtrl;
  late final TextEditingController _fCtrl;
  late final TextEditingController _cCtrl;
  late HeatProcess _process;
  String? _category;
  late bool _showPer100g;
  late bool _showTitleInExport;
  late BlankMode _blankMode;
  String? _retentionError;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDish;
    _process = d.process;
    _category = d.category;
    _showPer100g = d.showPer100gRowInExport;
    _showTitleInExport = d.showTitleInExport;
    _blankMode = d.blankMode;
    _pCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(d.retentionProtein),
    );
    _fCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(d.retentionFat),
    );
    _cCtrl = TextEditingController(
      text: CalculationEngine.formatPercent(d.retentionCarbs),
    );
  }

  @override
  void dispose() {
    _pCtrl.dispose();
    _fCtrl.dispose();
    _cCtrl.dispose();
    super.dispose();
  }

  void _fillRetention(double protein, double fat, double carbs) {
    _pCtrl.text = CalculationEngine.formatPercent(protein);
    _fCtrl.text = CalculationEngine.formatPercent(fat);
    _cCtrl.text = CalculationEngine.formatPercent(carbs);
  }

  void _apply() {
    final notifier = ref.read(dishProvider.notifier);
    final current = ref.read(dishProvider);

    if (!_process.isLegacy) {
      if (_process != current.process) {
        notifier.setHeatProcess(_process);
      }
      notifier.setCategory(_category);
      notifier.setBlankMode(_blankMode);
      notifier.toggleShowTitle(_showTitleInExport);
      notifier.toggleShowPer100gRow(_showPer100g);
      Navigator.pop(context);
      return;
    }

    final values = [_pCtrl.text, _fCtrl.text, _cCtrl.text]
        .map(CalculationEngine.parseInputDouble)
        .toList();
    // B1.2: сохранность 0 % физически невозможна (весь нутриент
    // исчез), поэтому нижняя граница — 1 %, как в валидаторе.
    if (values.any((v) => v == null || v < 1 || v > 100)) {
      setState(
        () => _retentionError = 'Введите каждый процент от 1 до 100.',
      );
      return;
    }

    final pVal = values[0]! / 100;
    final fVal = values[1]! / 100;
    final cVal = values[2]! / 100;
    final probedDish = current.copyWith(process: _process);
    final mass = _RecipeEditorScreenState._cookedMacroMass(
      probedDish,
      protein: pVal,
      fat: fVal,
      carbs: cVal,
    );
    if (mass > probedDish.effectiveYieldGrams) {
      setState(() => _retentionError =
          'При этих коэффициентах масса БЖУ после готовки '
          '${CalculationEngine.formatMacro(mass)} г превышает выход '
          '${CalculationEngine.formatGrams(probedDish.effectiveYieldGrams)} г. '
          'Увеличьте выход или уменьшите сохранность.');
      return;
    }

    if (_process != current.process) {
      notifier.setHeatProcess(_process);
    }
    notifier.setRetention(
      protein: pVal,
      fat: fVal,
      carbs: cVal,
    );
    notifier.setCategory(_category);
    notifier.setBlankMode(_blankMode);
    notifier.toggleShowTitle(_showTitleInExport);
    notifier.toggleShowPer100gRow(_showPer100g);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final legacy = _process.isLegacy;
    final processNote = LossClarityHints.forDishProcess(_process);
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final denseDialog = textScale <= 1.2;
    final stackFooter =
        (size.width < 360 && textScale > 1.35) || size.width < 300;
    final stackRetentionFields = size.width < 360 || textScale > 1.35;

    final cancelBtn = TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Отмена'),
    );
    final applyBtn = FilledButton(
      onPressed: _apply,
      child: const Text('Применить', textAlign: TextAlign.center),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.9),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, 0, Space.x1, Space.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Параметры расчета и бланка',
                        style: AppTypography.title.copyWith(color: p.ink),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Закрыть',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.divider),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      Space.x4, Space.x3, Space.x4, Space.x4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Категория блюда',
                        style: AppTypography.label.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: Space.x2),
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('dish-category-field'),
                        isDense: denseDialog,
                        itemHeight: null,
                        value: _category,
                        isExpanded: true,
                        decoration: InputDecoration(isDense: denseDialog),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Без категории', softWrap: true),
                          ),
                          for (final item in DishCategories.all)
                            DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text(item.label, softWrap: true),
                            ),
                        ],
                        onChanged: (cat) => setState(() => _category = cat),
                      ),
                      const SizedBox(height: Space.x4),
                      Text(
                        'Способ тепловой обработки',
                        style: AppTypography.label.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: Space.x2),
                      DropdownButtonFormField<HeatProcess>(
                        key: const ValueKey('heat-process'),
                        isDense: denseDialog,
                        itemHeight: null,
                        value: _process,
                        isExpanded: true,
                        decoration: InputDecoration(isDense: denseDialog),
                        items: HeatProcess.values
                            .map(
                              (proc) => DropdownMenuItem(
                                value: proc,
                                child: Text(proc.label, softWrap: true),
                              ),
                            )
                            .toList(),
                        onChanged: (proc) {
                          if (proc == null) return;
                          setState(() {
                            _process = proc;
                            _retentionError = null;
                            if (proc.isLegacy) {
                              if (widget.initialDish.process.isLegacy) {
                                _fillRetention(
                                  widget.initialDish.retentionProtein,
                                  widget.initialDish.retentionFat,
                                  widget.initialDish.retentionCarbs,
                                );
                              } else {
                                _fillRetention(
                                  kLegacyRetentionProtein,
                                  kLegacyRetentionFat,
                                  kLegacyRetentionCarbs,
                                );
                              }
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
                        style: AppTypography.caption
                            .copyWith(color: p.inkSecondary),
                      ),
                      if (processNote != null) ...[
                        const SizedBox(height: Space.x2),
                        Container(
                          key: const ValueKey('process-clarity-hint'),
                          padding: const EdgeInsets.all(Space.x2),
                          decoration: BoxDecoration(
                            color: p.accentSoft,
                            borderRadius: Radii.fieldAll,
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
                          'Коэффициенты сохранности нутриентов при готовке (%)',
                          style: AppTypography.label.copyWith(color: p.ink),
                        ),
                        const SizedBox(height: Space.x1),
                        Text(
                          'Одна тройка на всё блюдо — так считались рецептуры '
                          'до 03.11.2026. 94/88/91 % — средние потери 6/12/9 % '
                          '(МР 2.3.0419-26, прил. 5).',
                          style: AppTypography.caption
                              .copyWith(color: p.inkSecondary),
                        ),
                        const SizedBox(height: Space.x2),
                        Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x2,
                          children: [
                            ActionChip(
                              label: const Text('Старый расчёт (94/88/91%)'),
                              onPressed: () => setState(
                                () => _fillRetention(
                                  kLegacyRetentionProtein,
                                  kLegacyRetentionFat,
                                  kLegacyRetentionCarbs,
                                ),
                              ),
                            ),
                            ActionChip(
                              label: const Text('Без потерь (100%)'),
                              onPressed: () =>
                                  setState(() => _fillRetention(1, 1, 1)),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.x3),
                        if (stackRetentionFields) ...[
                          TextField(
                            controller: _pCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Белки %',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: Space.x2),
                          TextField(
                            controller: _fCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Жиры %',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: Space.x2),
                          TextField(
                            controller: _cCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Углев. %',
                              isDense: true,
                            ),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pCtrl,
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
                                  controller: _fCtrl,
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
                                  controller: _cCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Углев. %',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_retentionError != null) ...[
                          const SizedBox(height: Space.x2),
                          Text(
                            _retentionError!,
                            style:
                                AppTypography.caption.copyWith(color: p.danger),
                          ),
                        ],
                      ],
                      const SizedBox(height: Space.x4),
                      DropdownButtonFormField<BlankMode>(
                        isDense: denseDialog,
                        itemHeight: null,
                        value: _blankMode,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Режим бланка'),
                        items: BlankMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(mode.shortName, softWrap: true),
                              ),
                            )
                            .toList(),
                        onChanged: (mode) {
                          if (mode != null) {
                            setState(() => _blankMode = mode);
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
                        value: _showTitleInExport,
                        onChanged: (val) =>
                            setState(() => _showTitleInExport = val),
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
                          style: AppTypography.caption
                              .copyWith(color: p.inkSecondary),
                        ),
                        value: _showPer100g,
                        onChanged: (val) => setState(() => _showPer100g = val),
                      ),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.divider)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.x4, Space.x2, Space.x4, Space.x2),
                  child: stackFooter
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            applyBtn,
                            const SizedBox(height: Space.x1),
                            cancelBtn,
                          ],
                        )
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              cancelBtn,
                              const SizedBox(width: Space.x2),
                              Expanded(child: applyBtn),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScaleRecipeSheet extends StatefulWidget {
  final Dish dish;

  const _ScaleRecipeSheet({required this.dish});

  @override
  State<_ScaleRecipeSheet> createState() => _ScaleRecipeSheetState();
}

class _ScaleRecipeSheetState extends State<_ScaleRecipeSheet> {
  static const List<double> _presets = [0.5, 1.5, 2.0, 3.0, 5.0];
  static const List<int> _targetPresets = [500, 1000, 2000, 5000];

  late final TextEditingController _ctrl;
  late final TextEditingController _targetCtrl;
  bool _byTargetWeight = false;
  bool _targetYieldBasis = true;
  double _factor = 2.0;
  bool _scaleYield = true;
  String? _error;
  String? _targetError;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '2');
    _targetYieldBasis = widget.dish.customYieldGrams != null &&
        widget.dish.customYieldGrams! >= CalculationValidation.minCustomYieldGrams;
    _targetCtrl = TextEditingController(text: '1000');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(double factor) {
    final text = CalculationEngine.formatGrams(factor);
    setState(() {
      _factor = factor;
      _error = null;
      _ctrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _selectTargetPreset(int grams) {
    final text = grams.toString();
    setState(() {
      _targetError = null;
      _targetCtrl.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackFooter =
        (size.width < 360 && textScale > 1.35) || size.width < 300;
    final rawNet = _RecipeEditorScreenState._safeGrams(
      () => widget.dish.totalRawNetGrams,
    );
    final hasCustomYield = widget.dish.customYieldGrams != null &&
        widget.dish.customYieldGrams! >=
            CalculationValidation.minCustomYieldGrams;
    final currentYield = widget.dish.customYieldGrams ?? 0.0;
    final useYieldBasis = hasCustomYield && _targetYieldBasis;
    final targetBaseGrams = useYieldBasis ? currentYield : rawNet;

    double? effectiveFactor;
    String? computedTargetError;
    if (_byTargetWeight) {
      final targetVal = CalculationEngine.parseInputDouble(_targetCtrl.text);
      if (targetBaseGrams <= 0) {
        computedTargetError = 'Нет базовой массы для расчёта';
      } else if (targetVal == null ||
          !targetVal.isFinite ||
          targetVal < 1 ||
          targetVal > CalculationValidation.maxCustomYieldGrams) {
        computedTargetError = 'Введите массу от 1 до 9 999 999 г';
      } else {
        final candidate = targetVal / targetBaseGrams;
        if (!candidate.isFinite || candidate <= 0 || candidate > 1000) {
          computedTargetError = 'Множитель выходит за пределы 0,01–1000×';
        } else {
          effectiveFactor = candidate;
        }
      }
    } else {
      final parsed = CalculationEngine.parseInputDouble(_ctrl.text);
      if (parsed != null &&
          parsed.isFinite &&
          parsed > 0 &&
          parsed <= 1000 &&
          _error == null) {
        effectiveFactor = parsed;
      }
    }

    final valid = effectiveFactor != null;
    final applyScaleYield =
        (_byTargetWeight && useYieldBasis) ? true : _scaleYield;

    final cancelBtn = TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Отмена'),
    );
    final applyBtn = FilledButton(
      key: const ValueKey('scale-apply-btn'),
      onPressed: valid
          ? () => Navigator.pop(
                context,
                (factor: effectiveFactor!, scaleYield: applyScaleYield),
              )
          : null,
      child: const Text('Применить масштаб', textAlign: TextAlign.center),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.9),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Масштабировать рецепт',
                  style: AppTypography.title.copyWith(color: p.ink),
                ),
                const SizedBox(height: Space.x1),
                Text(
                  'Пропорционально изменит вес всех ингредиентов.',
                  style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: Space.x3),
                SegmentedButton<bool>(
                  key: const ValueKey('scale-mode-segmented'),
                  showSelectedIcon: false,
                  style: AppSegmentedStyle.of(p, compact: true),
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Множитель'),
                      ),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Целевой вес'),
                      ),
                    ),
                  ],
                  selected: {_byTargetWeight},
                  onSelectionChanged: (sel) {
                    if (sel.isEmpty) return;
                    AppHaptics.toggle();
                    setState(() => _byTargetWeight = sel.first);
                  },
                ),
                const SizedBox(height: Space.x3),
                if (!_byTargetWeight) ...[
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [
                      for (final preset in _presets)
                        ChoiceChip(
                          key: ValueKey('scale-preset-$preset'),
                          label:
                              Text('×${CalculationEngine.formatGrams(preset)}'),
                          selected: (_factor - preset).abs() < 0.001 &&
                              _error == null,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) => _selectPreset(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.x3),
                  TextField(
                    key: const ValueKey('scale-factor-field'),
                    controller: _ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppTypography.num.copyWith(color: p.ink),
                    decoration: InputDecoration(
                      labelText: 'Множитель',
                      hintText: 'Например, 2 или 0,5',
                      errorText: _error,
                    ),
                    onChanged: (text) {
                      final v = CalculationEngine.parseInputDouble(text);
                      setState(() {
                        if (v == null || !v.isFinite || v <= 0 || v > 1000) {
                          _error = 'Введите множитель от 0,01 до 1000';
                        } else {
                          _factor = v;
                          _error = null;
                        }
                      });
                    },
                  ),
                ] else ...[
                  if (hasCustomYield) ...[
                    Wrap(
                      spacing: Space.x2,
                      runSpacing: Space.x1,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('scale-target-basis-yield'),
                          label: Text(
                            'Выход блюда (${CalculationEngine.formatGrams(currentYield)} г)',
                          ),
                          selected: _targetYieldBasis,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) =>
                              setState(() => _targetYieldBasis = true),
                        ),
                        ChoiceChip(
                          key: const ValueKey('scale-target-basis-raw'),
                          label: Text(
                            'Сырьё нетто (${CalculationEngine.formatGrams(rawNet)} г)',
                          ),
                          selected: !_targetYieldBasis,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) =>
                              setState(() => _targetYieldBasis = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.x2),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x2),
                      child: Text(
                        'Пересчёт по нетто сырья (${CalculationEngine.formatGrams(rawNet)} г), так как выход не указан.',
                        style: AppTypography.caption
                            .copyWith(color: p.inkSecondary),
                      ),
                    ),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [
                      for (final preset in _targetPresets)
                        ChoiceChip(
                          key: ValueKey('scale-target-preset-$preset'),
                          label: Text('$preset г'),
                          selected:
                              CalculationEngine.parseInputDouble(
                                        _targetCtrl.text,
                                      ) ==
                                      preset.toDouble() &&
                                  computedTargetError == null,
                          showCheckmark: false,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          onSelected: (_) => _selectTargetPreset(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.x3),
                  TextField(
                    key: const ValueKey('scale-target-field'),
                    controller: _targetCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppTypography.num.copyWith(color: p.ink),
                    decoration: InputDecoration(
                      labelText: useYieldBasis
                          ? 'Нужный выход блюда, г'
                          : 'Нужное сырьё нетто, г',
                      hintText: 'Например, 1000',
                      suffixText: 'г',
                      errorText: _targetError ?? computedTargetError,
                    ),
                    onChanged: (_) => setState(() => _targetError = null),
                  ),
                ],
                if (hasCustomYield && !(_byTargetWeight && useYieldBasis)) ...[
                  const SizedBox(height: Space.x2),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    title: Text(
                      'Масштабировать и вес готового блюда',
                      style: AppTypography.bodySm.copyWith(color: p.ink),
                    ),
                    value: _scaleYield,
                    onChanged: (v) => setState(() => _scaleYield = v),
                  ),
                ],
                if (valid && rawNet > 0) ...[
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
                        if (_byTargetWeight)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'Коэффициент: ×${CalculationEngine.formatMacro(effectiveFactor)}',
                              key: const ValueKey('scale-computed-factor'),
                              style: AppTypography.numSm.copyWith(
                                color: p.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Text(
                          'Сырьё нетто: ${CalculationEngine.formatGrams(rawNet)} г → '
                          '${CalculationEngine.formatGrams(CalculationMath.round1(rawNet * effectiveFactor))} г',
                          style: AppTypography.numSm.copyWith(color: p.ink),
                        ),
                        if (hasCustomYield && applyScaleYield)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Выход блюда: ${CalculationEngine.formatGrams(currentYield)} г → '
                              '${CalculationEngine.formatGrams(CalculationMath.round1(currentYield * effectiveFactor))} г',
                              style: AppTypography.numSm
                                  .copyWith(color: p.inkSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.x3),
                if (stackFooter) ...[
                  applyBtn,
                  const SizedBox(height: Space.x1),
                  cancelBtn,
                ] else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cancelBtn,
                        const SizedBox(width: Space.x2),
                        Expanded(child: applyBtn),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

