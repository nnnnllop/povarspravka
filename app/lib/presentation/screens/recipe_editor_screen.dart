import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/masters_recipes.dart';
import '../providers/dish_provider.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/ingredient_card.dart';
import '../widgets/macro_summary_bar.dart';
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
          // но и терять нечего: сохраняем черновик и сообщаем.
          await ref.read(dishProvider.notifier).saveCurrentToLibrary();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Черновик сохранён')));
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
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, Space.x3, Space.x4, Space.x6 + 72),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildParameters(dish, isDark),
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
                      onTap: () => _editIngredient(context, ing),
                      onDelete: () => _removeIngredient(ing, index),
                    ),
                  );
                },
              ),
            ),
            // Закреплённая итоговая полоса: цифры не уезжают за край ленты
            // и не прячутся под клавиатурой (аудит P1-6).
            _buildSummaryRail(calc, dish),
          ],
        ),
        // FAB в зоне большого пальца — над итоговой полосой.
        floatingActionButton: FloatingActionButton.extended(
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
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
  Widget _buildSummaryRail(CalculationResult calc, Dish dish) {
    final p = Palette.of(context);
    return Material(
      elevation: 8,
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.divider)),
          ),
          child: MacroSummaryBar(
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

  Widget _buildParameters(Dish dish, bool isDark) {
    final custom = dish.customYieldGrams != null;
    final explanation =
        YieldExplanation(dish.totalRawNetGrams, dish.effectiveYieldGrams);

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
          const SizedBox(height: 6),
          Text(
            dish.blankMode == BlankMode.photoCross
                ? 'Типовой бланк с крестом: калорийность только в строке «После т.о.».'
                : 'Построчный расчёт калорийности каждого продукта.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Выход готового блюда: ${CalculationEngine.formatGrams(dish.effectiveYieldGrams)} г',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            title: const Text('Задать фактический выход'),
            subtitle: Text(
              custom
                  ? 'Ручной выход • нетто сырья ${CalculationEngine.formatGrams(dish.totalRawNetGrams)} г'
                  : 'Автоматически: сумма нетто ингредиентов',
              style: AppTypography.bodySmall,
            ),
            value: custom,
            onChanged: (enabled) {
              if (enabled && dish.totalRawNetGrams <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сначала добавьте ингредиенты')));
                return;
              }
              ref
                  .read(dishProvider.notifier)
                  .setCustomYield(enabled ? dish.effectiveYieldGrams : null);
              _yieldCtrl.text = enabled
                  ? CalculationEngine.formatGrams(dish.effectiveYieldGrams)
                  : '';
              setState(() => _yieldError = null);
            },
          ),
          if (custom) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('actual-yield'),
              controller: _yieldCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.numeric,
              decoration: InputDecoration(
                labelText: 'Фактический выход готового блюда',
                suffixText: 'г',
                errorMaxLines: 3,
                errorText: _yieldError,
              ),
              onChanged: (value) {
                final parsed = CalculationEngine.parseInputDouble(value);
                if (parsed == null ||
                    !parsed.isFinite ||
                    parsed < 0.1 ||
                    parsed > 9999999) {
                  setState(() => _yieldError =
                      'Введите выход не менее 0,1 г. Сохранён прежний выход.');
                } else if (parsed < _cookedMacroMass(dish)) {
                  setState(() => _yieldError =
                      'Выход меньше суммарной массы БЖУ после т.о. '
                      '(${CalculationEngine.formatMacro(_cookedMacroMass(dish))} г). '
                      'Сохранён прежний выход — увеличьте выход или уменьшите '
                      'сохранность.');
                } else {
                  setState(() => _yieldError = null);
                  ref.read(dishProvider.notifier).setCustomYield(parsed);
                }
              },
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
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
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
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
            'Скурихина и базе USDA, или откройте готовую раскладку мастера '
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
              await ref.read(dishProvider.notifier).saveCurrentToLibrary();
              if (ctx.mounted) Navigator.pop(ctx, _ExitChoice.saveAndExit);
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Параметры расчета и бланка'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Коэффициенты сохранности нутриентов при т.о. (%)',
                    style: AppTypography.bodySmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Усреднённые коэффициенты сохранности по ГОСТ/Скурихину:',
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
                        label: const Text('Варка / припускание (94/88/91%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '94';
                            fCtrl.text = '88';
                            cCtrl.text = '91';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Жарка (92/95/93%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '92';
                            fCtrl.text = '95';
                            cCtrl.text = '93';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Запекание (92/90/95%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '92';
                            fCtrl.text = '90';
                            cCtrl.text = '95';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Фритюр (90/100/95%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '90';
                            fCtrl.text = '100';
                            cCtrl.text = '95';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Без т.о. (100%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '100';
                            fCtrl.text = '100';
                            cCtrl.text = '100';
                          });
                        },
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
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
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
                  final values = [pCtrl.text, fCtrl.text, cCtrl.text]
                      .map(CalculationEngine.parseInputDouble)
                      .toList();
                  if (values.any((v) => v == null || v < 0 || v > 100)) {
                    setDialogState(() =>
                        retentionError = 'Введите каждый процент от 0 до 100.');
                    return;
                  }
                  final pVal = values[0]! / 100;
                  final fVal = values[1]! / 100;
                  final cVal = values[2]! / 100;
                  final mass = _cookedMacroMass(dish,
                      protein: pVal, fat: fVal, carbs: cVal);
                  if (mass > dish.effectiveYieldGrams) {
                    setDialogState(() => retentionError =
                        'При этих коэффициентах масса БЖУ после т.о. '
                        '${CalculationEngine.formatMacro(mass)} г превышает выход '
                        '${CalculationEngine.formatGrams(dish.effectiveYieldGrams)} г. '
                        'Увеличьте выход или уменьшите сохранность.');
                    return;
                  }
                  final notifier = ref.read(dishProvider.notifier);
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

