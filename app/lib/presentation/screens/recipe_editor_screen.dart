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
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/masters_recipes.dart';
import '../providers/dish_provider.dart';
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

enum _MasterLoadChoice { copy, replace, cancel }

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

  @override
  Widget build(BuildContext context) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final calcError = ref.watch(calculationErrorProvider);
    final persistenceError = ref.watch(persistenceErrorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    final separateActions = MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;
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
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          titleSpacing: 0,
          // Единственная точка входа к мастерам — эта кнопка в AppBar.
          actions: separateActions ? null : actions,
          bottom: separateActions
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                    child: Row(children: actions),
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            if (persistenceError != null)
              PersistenceErrorBanner(
                margin: const EdgeInsets.symmetric(
                    horizontal: Space.x4, vertical: Space.x2),
                onRetry: () =>
                    ref.read(dishProvider.notifier).retryPersistence(),
              ),
            Expanded(
              child: Stack(
                children: [
                  ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, Space.x3, Space.x4, Space.x6 + 72),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // STATE-01: невычислимое блюдо не роняет экран — над
                    // параметрами появляется понятный баннер.
                    if (calcError != null) CalcErrorBanner(detail: calcError),
                    _buildParameters(dish, calc, isDark),
                    const SizedBox(height: Space.x5),
                    Text(
                      'Ингредиенты · ${dish.ingredients.length}',
                      style: AppTypography.headline.copyWith(
                        color: isDark ? AppColors.inkDark : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: Space.x1),
                    if (dish.ingredients.isNotEmpty)
                      Text(
                        '⟷ перетащить · ← смахнуть, чтобы удалить',
                        style: AppTypography.caption.copyWith(
                          color: isDark
                              ? AppColors.inkMutedDark
                              : AppColors.inkMuted,
                        ),
                      ),
                    const SizedBox(height: Space.x3),
                    if (dish.ingredients.isEmpty)
                      _buildEmptyState(context, isDark),
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
                        color: AppColors.dangerSoft,
                        borderRadius: Radii.cardAll,
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: AppColors.danger),
                    ),
                    onDismissed: (_) => _removeIngredient(ing, index),
                    child: IngredientCard(
                      index: index + 1,
                      ingredient: ing,
                      // Явная ручка перестановки, а не «удерживайте карточку»:
                      // жест перетаскивания больше не конкурирует с тапом
                      // «изменить» и свайпом «удалить» (аудит P1-6).
                      dragHandleIndex: index,
                      // Новый расчёт: группа и способ обработки ингредиента
                      // видны в карточке и меняются вручную. Старый расчёт
                      // (legacy) — одна тройка на блюдо, строки нет.
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
                  Positioned(
                    right: Space.x4,
                    bottom: Space.x4,
                    child: FloatingActionButton.extended(
                      onPressed: () async {
                        AppHaptics.commit();
                        await SearchProductModal.show(
                          context,
                          mode: SearchMode.pickForRecipe,
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text('Добавить продукт'),
                    ),
                  ),
                ],
              ),
            ),
            // Закреплённая итоговая полоса: цифры не уезжают за край ленты
            // и не прячутся под клавиатурой (аудит P1-6).
            _buildSummaryRail(calc, dish),
          ],
        ),
      ),
    );
  }

  /// Нижний док итогов (аудит P1-6).
  ///
  /// Всегда компактный: одна строка «После т.о. · Б Ж У · ккал» + кнопка
  /// «Инспектор расчёта», которая открывает те же три ступени
  /// (Сырьё → После т.о. → Порция) полностью. Развёрнутая карточка в доке
  /// на экране 640 dp отнимала треть высоты и выталкивала ингредиенты из
  /// ленты — цена, которую не стоит платить за повтор уже посчитанных цифр.
  Widget _buildSummaryRail(CalculationResult? calc, Dish dish) {
    final p = Palette.of(context);
    // STATE-01: без результата показываем прочерки, а не падаем.
    return Material(
      elevation: 8,
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.divider)),
          ),
          child: calc == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.x4, vertical: Space.x3),
                  child: Text(
                    'После т.о. · — Б — Ж — У — ккал',
                    style: AppTypography.num.copyWith(color: p.inkMuted),
                  ),
                )
              : MacroSummaryBar(
                  key: ValueKey(dish.id),
                  result: calc,
                  compact: true,
                ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(Dish dish) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      // Единственная кнопка каталога мастеров в AppBar (остальные удалены).
      IconButton(
        icon: const Icon(Icons.auto_stories_outlined),
        tooltip: 'Рецептуры мастеров',
        onPressed: () => _showMastersCatalogSheet(context),
      ),
      IconButton(
        icon: const Icon(Icons.tune_rounded),
        tooltip: 'Параметры',
        onPressed: () => _showRetentionSettingsDialog(context, dish),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: FilledButton(
          onPressed: _openBlank,
          // `styleFrom` перекрывает тему целиком, поэтому минимум 48 dp
          // задаём явно (WCAG 2.5.5).
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
            foregroundColor:
                isDark ? AppColors.backgroundDark : Colors.white,
            minimumSize: const Size(0, kMinTapTarget),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          ),
          child: const Text('Бланк'),
        ),
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
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondaryLight,
                    fontSize: 11,
                  ),
                ),
                if (LossClarityHints.forIngredient(
                      group: ing.lossGroup,
                      process: process,
                    )
                    case final String clarityHint) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('ingredient-loss-clarity-hint'),
                    padding: const EdgeInsets.all(Space.x2),
                    decoration: BoxDecoration(
                      color: Palette.of(ctx).accentSoft,
                      borderRadius: Radii.fieldAll,
                      border: Border.all(
                        color: Palette.of(ctx).accent.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      clarityHint,
                      style: AppTypography.bodySmall.copyWith(
                        color: Palette.of(ctx).ink,
                        fontSize: 11.5,
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

  Widget _buildParameters(Dish dish, CalculationResult? calc, bool isDark) {
    final legacy = dish.process.isLegacy;
    final custom = dish.customYieldGrams != null;
    // Новый расчёт: поле веса готового блюда видно всегда (вес вводит повар).
    // Старый расчёт (legacy): прежний переключатель «Задать фактический выход».
    final showYieldField = custom || !legacy;
    // Сохранённый документ может содержать значения, которые валидатор
    // отвергает (например, отход 100 %): тогда сумма нетто и выход не
    // вычисляются, а экран не должен падать — показываем 0 и баннер ошибки.
    final rawNet = _safeGrams(() => dish.totalRawNetGrams);
    final effYield = _safeGrams(() => dish.effectiveYieldGrams);
    final explanation =
        YieldExplanation(rawNet, effYield);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
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
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            // 48 dp цель (WCAG 2.5.5): `dense: true` давала только 40 dp.
            materialTapTargetSize: MaterialTapTargetSize.padded,
            title: const Text('Печатать название в заголовке бланка'),
            value: dish.showTitleInExport,
            onChanged: (value) =>
                ref.read(dishProvider.notifier).toggleShowTitle(value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<BlankMode>(
            isDense: MediaQuery.textScalerOf(context).scale(1) <= 1.2,
            itemHeight: null,
            value: dish.blankMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Режим бланка'),
            items: BlankMode.values
                .map((mode) => DropdownMenuItem(
                    value: mode, child: Text(mode.shortName, softWrap: true)))
                .toList(),
            onChanged: (mode) {
              if (mode != null) ref.read(dishProvider.notifier).setBlankMode(mode);
            },
          ),
          const SizedBox(height: 4),
          Text(
            legacy || dish.hasCustomYield
                ? 'Выход готового блюда: ${CalculationEngine.formatGrams(effYield)} г'
                : 'Вес готового блюда не указан',
            style: Theme.of(context).textTheme.titleMedium,
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
                style: AppTypography.bodySmall,
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
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('actual-yield'),
              controller: _yieldCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.numeric,
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
            const SizedBox(height: 10),
            YieldDensityWarning(
              key: const ValueKey('yield-density-warning'),
              result: calc,
            ),
          ],
          if (showYieldField) ...[
            if (legacy || rawNet > 0) ...[
              const SizedBox(height: 10),
              Container(
                key: const ValueKey('yield-explanation'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(explanation.badge,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      explanation.description,
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.restaurant_menu_rounded,
              size: 28,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Рецепт пока пуст',
            style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Нажмите «Добавить продукт», чтобы найти ингредиенты в справочнике '
            'Скурихина и базе BLS 4.0, или откройте готовую раскладку мастера '
            'кнопкой «Рецептуры мастеров» в шапке.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: isDark ? AppColors.inkSecondaryDark : AppColors.inkSecondary,
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

  void _showMastersCatalogSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сборник рецептур мастеров',
                          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Официальные эталонные раскладки (Ф. Л. Марчук, ГОСТ)',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: MastersRecipesCatalog.recipes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final recipe = MastersRecipesCatalog.recipes[idx];
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                recipe.name,
                                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.accentDark : AppColors.accentLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                recipe.standardCode,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppColors.accentLight : AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recipe.description,
                                style: AppTypography.bodySmall.copyWith(
                                  fontSize: 11,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    'Выход: ${CalculationEngine.formatGrams(recipe.expectedYieldGrams)} г · ${recipe.ingredients.length} инг.',
                                    style: AppTypography.numericSmall.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  Text(
                                    recipe.culinaryProcess,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        onTap: () {
                          Navigator.pop(ctx);
                          _loadMasterRecipe(recipe);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Загрузка эталонной рецептуры (аудит P0-3).
  ///
  /// Раньше мастер молча заменял текущее блюдо: `loadDish(newDish)` поверх
  /// всех ингредиентов. Теперь, если в блюде уже что-то есть, сначала
  /// спрашиваем: «Открыть как копию в черновик» / «Заменить текущий» /
  /// «Отмена». Ни один из путей не уничтожает данные молча.
  Future<void> _loadMasterRecipe(MasterRecipe master) async {
    final current = ref.read(dishProvider);
    final hasContent =
        current.ingredients.isNotEmpty || current.title.trim().isNotEmpty;

    var openAsCopy = true;
    if (hasContent) {
      final choice = await showDialog<_MasterLoadChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Открыть рецептуру мастера?'),
          content: Text(
            'В текущем блюде ${current.ingredients.length} ингр. '
            '(«${current.title.trim().isEmpty ? 'Без названия' : current.title.trim()}»).\n\n'
            'Рецептура «${master.name}» может открыться как новый черновик '
            'или заменить текущую раскладку.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _MasterLoadChoice.cancel),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _MasterLoadChoice.replace),
              child: const Text('Заменить текущий'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _MasterLoadChoice.copy),
              child: const Text('Открыть как копию в черновик'),
            ),
          ],
        ),
      );
      if (choice == null || choice == _MasterLoadChoice.cancel) return;
      openAsCopy = choice == _MasterLoadChoice.copy;
    }

    if (!mounted) return;
    final notifier = ref.read(dishProvider.notifier);
    final newDish = master.toDish();
    if (openAsCopy) {
      notifier.loadDishAsCopy(newDish);
    } else {
      notifier.loadDish(newDish);
    }
    final loaded = ref.read(dishProvider);
    _syncControllers(loaded);
    AppHaptics.commit();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Загружена эталонная рецептура: «${master.name}»'
          '${openAsCopy ? ' (как копия)' : ''}',
        ),
        duration: const Duration(seconds: 3),
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
          // Тройка сохранности существует только у старого расчёта (legacy).
          // Новый расчёт берёт потери из таблицы по группе каждого
          // продукта (lib/core/calculation/loss_table.dart), поля «Белки / Жиры /
          // Углев. %» для него не показываются.
          final currentProcess = ref.read(dishProvider).process;
          final legacy = currentProcess.isLegacy;
          final processNote = LossClarityHints.forDishProcess(currentProcess);
          return AlertDialog(
            title: const Text('Параметры расчета и бланка'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ГОСТ-01/02/03: способ обработки — главный переключатель
                  // расчёта. Он здесь, а не в шапке редактора: шапка уже
                  // занимает весь экран, и любая добавленная строка уводит
                  // список ингредиентов за нижний край.
                  Text(
                    'Способ тепловой обработки',
                    style: AppTypography.bodySmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<HeatProcess>(
                    key: const ValueKey('heat-process'),
                    isDense: true,
                    value: ref.read(dishProvider).process,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: HeatProcess.values
                        .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.label, softWrap: true)))
                        .toList(),
                    onChanged: (p) {
                      if (p == null) return;
                      ref.read(dishProvider.notifier).setHeatProcess(p);
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
                  const SizedBox(height: 4),
                  Text(
                    legacy
                        ? 'Старый расчёт: одна тройка сохранности на всё '
                            'блюдо (по умолчанию 94/88/91 %), выход = сумма '
                            'нетто, если вес готового блюда не указан.'
                        : 'Потери белков, жиров и углеводов — по таблице '
                            'потерь для группы каждого продукта (МР '
                            '2.3.0419-26). Вес готового блюда вводите сами.',
                    key: const ValueKey('process-hint'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                  if (processNote != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      key: const ValueKey('process-clarity-hint'),
                      padding: const EdgeInsets.all(Space.x2),
                      decoration: BoxDecoration(
                        color: Palette.of(ctx).accentSoft,
                        borderRadius: Radii.fieldAll,
                        border: Border.all(
                          color: Palette.of(ctx).accent.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        processNote,
                        style: AppTypography.bodySmall.copyWith(
                          color: Palette.of(ctx).ink,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                  if (legacy) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Коэффициенты сохранности нутриентов при т.о. (%)',
                      style: AppTypography.bodySmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Одна тройка на всё блюдо — так считались рецептуры '
                      'до 03.11.2026. 94/88/91 % — средние потери 6/12/9 % '
                      '(МР 2.3.0419-26, прил. 5).',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondaryLight,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
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
                    const SizedBox(height: 12),
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
                        const SizedBox(width: 8),
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
                        const SizedBox(width: 8),
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
                      const SizedBox(height: 8),
                      Text(
                        retentionError!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    title: const Text(
                      'Строка «В 100 г блюда» в бланке',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: const Text(
                      'По умолчанию скрыта для 1:1 совпадения с типовым бланком',
                      style: TextStyle(fontSize: 11.5),
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
              ElevatedButton(
                onPressed: () {
                  final notifier = ref.read(dishProvider.notifier);
                  final current = ref.read(dishProvider);
                  if (!current.process.isLegacy) {
                    // Новый расчёт: тройки нет, применяется только бланк.
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
            child:
                const Text('Очистить', style: TextStyle(color: AppColors.kcal)),
          ),
        ],
      ),
    );
  }
}

