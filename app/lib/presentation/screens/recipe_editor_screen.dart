import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
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
        if (previous?.title != next.title && _titleCtrl.text != next.title)
          _titleCtrl.text = next.title;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Калькулятор',
            softWrap: true, overflow: TextOverflow.visible),
        titleSpacing: 0,
        actions: separateActions ? null : actions,
        bottom: separateActions
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions))
            : null,
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        header:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildParameters(dish),
          const SizedBox(height: 24),
          Text('Ингредиенты · ${dish.ingredients.length}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
              'Удерживайте карточку для перестановки. Смахните влево для удаления.'),
          const SizedBox(height: 12),
          if (dish.ingredients.isEmpty) _buildEmptyState(context, isDark),
        ]),
        footer: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            child: MacroSummaryBar(key: ValueKey(dish.id), result: calc)),
        itemCount: dish.ingredients.length,
        onReorder: (a, b) =>
            ref.read(dishProvider.notifier).reorderIngredients(a, b),
        itemBuilder: (context, index) {
          final ing = dish.ingredients[index];
          return Dismissible(
            key: ValueKey(ing.id),
            direction: DismissDirection.endToStart,
            background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.all(24),
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Icon(Icons.delete_outline)),
            onDismissed: (_) => _removeIngredient(ing, index),
            child: IngredientCard(
                index: index + 1,
                ingredient: ing,
                onTap: () => _editIngredient(context, ing),
                onDelete: () => _removeIngredient(ing, index)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                  onPressed: () => SearchProductModal.show(context,
                      mode: SearchMode.pickForRecipe),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить продукт')))),
    );
  }

  List<Widget> _buildActions(Dish dish) {
    return [
      IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Параметры',
          onPressed: () => _showRetentionSettingsDialog(context, dish)),
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child:
              FilledButton(onPressed: _openBlank, child: const Text('Бланк'))),
      PopupMenuButton<String>(
        tooltip: 'Другие действия',
        onSelected: (value) async {
          if (value == 'save') {
            try {
              await ref.read(dishProvider.notifier).saveCurrentToLibrary();
              if (!mounted) return;
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
            if (ref.read(dishProvider).id == dishId)
              ref
                  .read(dishProvider.notifier)
                  .restoreIngredient(ingredient, index);
          }),
    ));
  }

  /// Масса БЖУ после тепловой обработки — нижняя граница выхода блюда.
  /// Считается на «бесконечном» выходе: масса БЖУ от выхода не зависит, а
  /// инвариант ядра (БЖУ ≤ выход) при этом заведомо выполнен.
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

  Widget _buildParameters(Dish dish) {
    final custom = dish.customYieldGrams != null;
    final explanation =
        YieldExplanation(dish.totalRawNetGrams, dish.effectiveYieldGrams);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _titleCtrl,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (value) => ref.read(dishProvider.notifier).setTitle(value),
        decoration: const InputDecoration(
            labelText: 'Название блюда', hintText: 'Например, борщ сибирский'),
      ),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Печатать название в заголовке бланка'),
          value: dish.showTitleInExport,
          onChanged: (value) =>
              ref.read(dishProvider.notifier).toggleShowTitle(value)),
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
      const SizedBox(height: 8),
      Text(dish.blankMode == BlankMode.photoCross
          ? 'Типовой бланк с крестом: калорийность только в строке «После т.о.».'
          : 'Построчный расчёт калорийности каждого продукта.'),
      const SizedBox(height: 16),
      Text(
          'Выход готового блюда: ${CalculationEngine.formatGrams(dish.effectiveYieldGrams)} г',
          style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Задать фактический выход'),
        subtitle: Text(custom
            ? 'Ручной выход • нетто сырья ${CalculationEngine.formatGrams(dish.totalRawNetGrams)} г'
            : 'Автоматически: сумма нетто ингредиентов'),
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
        TextField(
          key: const ValueKey('actual-yield'),
          controller: _yieldCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Фактический выход готового блюда',
              suffixText: 'г',
              errorMaxLines: 3,
              errorText: _yieldError),
          onChanged: (value) {
            final parsed = CalculationEngine.parseInputDouble(value);
            if (parsed == null ||
                !parsed.isFinite ||
                parsed < 0.1 ||
                parsed > 9999999) {
              setState(() => _yieldError =
                  'Введите выход не менее 0,1 г. Сохранён прежний выход.');
            } else if (parsed < _cookedMacroMass(dish)) {
              // Масса БЖУ не может быть больше массы готового блюда.
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
        const SizedBox(height: 12),
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(.4),
                borderRadius: BorderRadius.circular(8)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(explanation.badge,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(explanation.description),
            ])),
      ],
    ]);
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Рецепт пока пуст',
              style: AppTypography.titleLarge
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите «Добавить продукт», чтобы найти ингредиенты в справочнике Скурихина и базе USDA.\nОграничений по числу ингредиентов нет.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => SearchProductModal.show(
                context,
                mode: SearchMode.pickForRecipe,
              ),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Открыть поиск продуктов'),
            ),
          ],
        ),
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
                    'Усреднённые коэффициенты сохранности по умолчанию (для конкретных блюд см. табл. 13 Скурихина)',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('По умолчанию: усреднённые (94 / 88 / 91%)'),
                        onPressed: () {
                          setDialogState(() {
                            pCtrl.text = '94';
                            fCtrl.text = '88';
                            cCtrl.text = '91';
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
                  if (retentionError != null) Text(retentionError!),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
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
