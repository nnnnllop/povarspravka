import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/dish.dart';
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

  @override
  Widget build(BuildContext context) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Калькулятор блюда'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Сохранить в мои блюда',
            onPressed: () {
              ref.read(dishProvider.notifier).saveCurrentToLibrary();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Блюдо сохранено в список рецептов'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Коэффициенты сохранности и параметры бланка',
            onPressed: () => _showRetentionSettingsDialog(context, dish),
          ),
          IconButton(
            icon: const Icon(Icons.table_view_rounded),
            tooltip: 'Просмотр бланка',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BlankPreviewScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'settings') {
                _showRetentionSettingsDialog(context, dish);
              } else if (val == 'clear') {
                _showClearConfirmation(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Параметры бланка и сохранность'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        color: AppColors.kcal, size: 20),
                    SizedBox(width: 8),
                    Text('Очистить рецепт'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Верхняя панель параметров блюда
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? AppColors.surfaceDark : Colors.white,
            child: Column(
              children: [
                // Название блюда
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        onChanged: (val) =>
                            ref.read(dishProvider.notifier).setTitle(val),
                        decoration: const InputDecoration(
                          hintText: 'Название блюда (например: Борщ сибирский)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          prefixIcon: Icon(Icons.restaurant_rounded, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: dish.showTitleInExport
                          ? 'Название будет напечатано в бланке'
                          : 'Название скрыто в бланке (как на типовом бланке)',
                      child: FilterChip(
                        label: Text(dish.showTitleInExport
                            ? 'В бланке: Да'
                            : 'В бланке: Нет'),
                        selected: dish.showTitleInExport,
                        onSelected: (val) => ref
                            .read(dishProvider.notifier)
                            .toggleShowTitle(val),
                        labelStyle: AppTypography.bodySmall.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Режим бланка и Выход блюда
                Row(
                  children: [
                    // Переключатель режима бланка
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<BlankMode>(
                            value: dish.blankMode,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 20),
                            onChanged: (mode) {
                              if (mode != null) {
                                ref
                                    .read(dishProvider.notifier)
                                    .setBlankMode(mode);
                              }
                            },
                            items: BlankMode.values.map((mode) {
                              return DropdownMenuItem(
                                value: mode,
                                child: Text(
                                  mode.shortName,
                                  style: AppTypography.bodyMedium
                                      .copyWith(fontSize: 12.5),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Выход готового блюда
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _yieldCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (val) {
                          final parsed = CalculationEngine.parseInputDouble(val);
                          ref
                              .read(dishProvider.notifier)
                              .setCustomYield(parsed);
                        },
                        decoration: InputDecoration(
                          hintText:
                              '${CalculationEngine.formatGrams(dish.totalRawNetGrams)} г',
                          labelText: 'Выход (г)',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          suffixText: 'г',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Список ингредиентов
          Expanded(
            child: dish.ingredients.isEmpty
                ? _buildEmptyState(context, isDark)
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: dish.ingredients.length,
                    onReorder: (oldIdx, newIdx) => ref
                        .read(dishProvider.notifier)
                        .reorderIngredients(oldIdx, newIdx),
                    itemBuilder: (context, idx) {
                      final ing = dish.ingredients[idx];
                      return IngredientCard(
                        key: ValueKey(ing.id),
                        index: idx + 1,
                        ingredient: ing,
                        onTap: () => _editIngredient(context, ing),
                        onDelete: () => ref
                            .read(dishProvider.notifier)
                            .removeIngredient(ing.id),
                      );
                    },
                  ),
          ),
        ],
      ),

      // Нижняя панель в bottomNavigationBar (чтобы клавиатура не поднимала ее поверх экрана)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Живая плашка КБЖУ
              MacroSummaryBar(result: calc),
              const SizedBox(height: 10),

              // Кнопки действий: "Добавить продукт" и "Бланк"
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () => SearchProductModal.show(
                        context,
                        mode: SearchMode.pickForRecipe,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Добавить продукт'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const BlankPreviewScreen()),
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Бланк'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
              style:
                  AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите «Добавить продукт», чтобы найти ингредиенты в справочнике Скурихина и базе USDA.\nОграничений по числу ингредиентов нет.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
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

  void _editIngredient(BuildContext context, ing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomNumpadSheet(
        product: ing.product,
        initialGrams: ing.weightGrams,
        initialIsGross: ing.isGross,
        isEditing: true,
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
      text: (dish.retentionProtein * 100).round().toString(),
    );
    final fCtrl = TextEditingController(
      text: (dish.retentionFat * 100).round().toString(),
    );
    final cCtrl = TextEditingController(
      text: (dish.retentionCarbs * 100).round().toString(),
    );
    bool showPer100g = dish.showPer100gRowInExport;

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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('Стандарт (94 / 88 / 91%)'),
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
                  final pVal = (CalculationEngine.parseInputDouble(pCtrl.text) ??
                          94.0)
                      .clamp(1.0, 100.0) /
                      100.0;
                  final fVal = (CalculationEngine.parseInputDouble(fCtrl.text) ??
                          88.0)
                      .clamp(1.0, 100.0) /
                      100.0;
                  final cVal = (CalculationEngine.parseInputDouble(cCtrl.text) ??
                          91.0)
                      .clamp(1.0, 100.0) /
                      100.0;
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
