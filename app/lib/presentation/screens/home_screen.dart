import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/masters_recipes.dart';
import '../providers/dish_provider.dart';
import '../widgets/nutrient_chip.dart';
import 'recipe_editor_screen.dart';
import 'search_product_modal.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeDish = ref.watch(dishProvider);
    final savedDishes = ref.watch(savedDishesProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56 * MediaQuery.textScalerOf(context).scale(1),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Поварская справка',
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Верхний карточный блок (Чистый минимализм без градиентов)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.primaryLight : AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '100% ОФЛАЙН',
                          style: TextStyle(
                            color: isDark ? AppColors.backgroundDark : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        'Справочник Скурихина (2002) · USDA FDC',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Расчет энергетической и пищевой ценности блюд',
                    style: AppTypography.headline.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Официальный нормативный расчет по ГОСТ 1:1 к типовому бланку. Экспорт в PDF, DOCX и XLSX.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                          foregroundColor: isDark ? AppColors.backgroundDark : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        ),
                        icon: Icon(
                          activeDish.ingredients.isNotEmpty
                              ? Icons.edit_note_rounded
                              : Icons.add_rounded,
                          size: 18,
                        ),
                        label: Text(
                          activeDish.ingredients.isNotEmpty
                              ? 'Продолжить расчет (${activeDish.ingredients.length} инг.)'
                              : 'Создать расчет блюда',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (activeDish.ingredients.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () {
                            ref.read(dishProvider.notifier).saveCurrentToLibrary();
                            ref.read(dishProvider.notifier).createNewDish();
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
                            );
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Новый бланк'),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Раздел «Рецептуры мастеров (Марчук)» — быстрый выбор классических блюд
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Рецептуры мастеров (Марчук)',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => _openMastersFullCatalog(context, ref),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isDark ? AppColors.accentLight : AppColors.accent,
                  ),
                  child: const Text('Все 6 рецептур →', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MastersRecipesCatalog.recipes.take(4).map((recipe) {
                  return Container(
                    width: 230,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : AppColors.cardLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _loadMasterRecipe(context, ref, recipe),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                            const SizedBox(height: 6),
                            Text(
                              recipe.name,
                              style: AppTypography.titleMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Выход ${CalculationEngine.formatGrams(recipe.expectedYieldGrams)} г · ${recipe.ingredients.length} инг.',
                              style: AppTypography.numericSmall.copyWith(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Загрузить',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 12,
                                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 18),

            // Быстрые карточки действий
            LayoutBuilder(builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 340;
              final tile1 = _buildActionTile(
                context: context,
                icon: Icons.search_rounded,
                title: 'Справочник продуктов',
                subtitle: 'Полный хим. состав, витамины, минералы',
                onTap: () => SearchProductModal.show(
                  context,
                  mode: SearchMode.browseCatalog,
                  onAddedFromCatalog: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
                    );
                  },
                ),
                isDark: isDark,
              );
              final tile2 = _buildActionTile(
                context: context,
                icon: Icons.calculate_rounded,
                title: 'Формула расчета',
                subtitle: 'ЭЦ = Б×4 + Ж×9 + У×4',
                onTap: () => _showFormulaInfo(context),
                isDark: isDark,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    tile1,
                    const SizedBox(height: 10),
                    tile2,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: tile1),
                  const SizedBox(width: 10),
                  Expanded(child: tile2),
                ],
              );
            }),

            // Список сохраненных рецептов (если есть)
            if (savedDishes.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Сохраненные блюда (${savedDishes.length})',
                    style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...savedDishes.map(
                (dish) => _buildSavedDishCard(context, ref, dish, isDark),
              ),
            ],

            const SizedBox(height: 20),

            // Справочный блок стандартов
            Text(
              'Допущения и правила расчета',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Коэффициенты сохранности нутриентов',
              description:
                  'По умолчанию приняты коэффициенты сохранности:\n• Белки (Б): 94%\n• Жиры (Ж): 88%\n• Углеводы (У): 91%\nЭто настраиваемое допущение по табл. 13 Скурихина. Для блюд без т.о. выберите 100 / 100 / 100%.',
              icon: Icons.thermostat_rounded,
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Два режима бланка',
              description:
                  '1. «Бланк с крестом (учебный)»: диагональный крест в колонке ккал сырья, итоговая калорийность только после т.о.\n2. «Подробный расчёт»: калории рассчитаны для каждого продукта.',
              icon: Icons.splitscreen_rounded,
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Форматы экспорта',
              description:
                  'Экспорт в векторный PDF (идентично типовому бланку), Microsoft Word (.docx) и Microsoft Excel (.xlsx) с живыми формулами и печатью с телефона.',
              icon: Icons.file_download_outlined,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  void _loadMasterRecipe(BuildContext context, WidgetRef ref, MasterRecipe recipe) {
    final dish = recipe.toDish();
    ref.read(dishProvider.notifier).loadDish(dish);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
    );
  }

  void _openMastersFullCatalog(BuildContext context, WidgetRef ref) {
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
                          _loadMasterRecipe(context, ref, recipe);
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

  Widget _buildSavedDishCard(
    BuildContext context,
    WidgetRef ref,
    Dish dish,
    bool isDark,
  ) {
    final calc = CalculationEngine.calculate(dish);
    final displayTitle =
        dish.title.trim().isNotEmpty ? dish.title.trim() : 'Блюдо без названия';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: ListTile(
        onTap: () {
          ref.read(dishProvider.notifier).loadDish(dish);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecipeEditorScreen()),
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 0.8,
            ),
          ),
          child: Icon(
            Icons.receipt_long_rounded,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            size: 20,
          ),
        ),
        title: Text(
          displayTitle,
          style: AppTypography.titleMedium.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                '${dish.ingredients.length} инг.',
                style: AppTypography.bodySmall.copyWith(fontSize: 11),
              ),
              Text(
                '· Выход: ${CalculationEngine.formatGrams(calc.yieldGrams)} г',
                style: AppTypography.bodySmall.copyWith(fontSize: 11),
              ),
              NutrientChip(
                type: NutrientType.kcal,
                value: CalculationEngine.formatKcal(calc.cookedKcal),
                compact: true,
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Дублировать блюдо',
              onPressed: () async {
                try {
                  await ref
                      .read(savedDishesProvider.notifier)
                      .duplicateDish(dish);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка при дублировании: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: isDark ? AppColors.kcalTextDark : AppColors.kcalTextLight),
              tooltip: 'Удалить',
              onPressed: () async {
                try {
                  await ref
                      .read(savedDishesProvider.notifier)
                      .deleteDish(dish.id);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка при удалении: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 11,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? AppColors.primaryContainerDark : AppColors.primaryContainerLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFormulaInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Формула ЭЦ'),
        content: const Text(
          'Энергетическая ценность (ккал) рассчитывается по коэффициентам Этуотера:\n\n'
          '• 1 г белков = 4,0 ккал\n'
          '• 1 г жиров = 9,0 ккал\n'
          '• 1 г углеводов = 4,0 ккал\n\n'
          'Итоговая формула:\nЭЦ = Б × 4 + Ж × 9 + У × 4\n\n'
          'Расчет ведется по нутриентам с учетом выбранной сохранности. Значения по умолчанию 94 / 88 / 91% можно изменить; без т.о. используются 100 / 100 / 100%. Формула 4/9/4 не учитывает отдельный вклад алкоголя, пищевых волокон и органических кислот.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}
