import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import 'recipe_editor_screen.dart';
import 'search_product_modal.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Поварская справка')),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Приветственный баннер
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                      : [const Color(0xFFFEF3C7), const Color(0xFFFFFBEB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? AppColors.borderDark
                      : AppColors.primary.withOpacity(0.2),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '100% ОФЛАЙН',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Скурихин 2002 + USDA',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Расчет пищевой и энергетической ценности блюд',
                    style: AppTypography.headline.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Официальный справочник И. М. Скурихина (2002 г.) + расширенная база USDA FoodData Central. Готовые бланки 1:1 к печатной форме в PDF, DOCX и XLSX.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
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
                            MaterialPageRoute(
                                builder: (_) => const RecipeEditorScreen()),
                          );
                        },
                        icon: Icon(
                          activeDish.ingredients.isNotEmpty
                              ? Icons.edit_note_rounded
                              : Icons.add_task_rounded,
                          size: 18,
                        ),
                        label: Text(
                          activeDish.ingredients.isNotEmpty
                              ? 'Продолжить расчет (${activeDish.ingredients.length} инг.)'
                              : 'Создать расчет блюда',
                        ),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                      ),
                      if (activeDish.ingredients.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () {
                            ref
                                .read(dishProvider.notifier)
                                .saveCurrentToLibrary();
                            ref.read(dishProvider.notifier).createNewDish();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RecipeEditorScreen()),
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
            const SizedBox(height: 16),

            // Быстрые карточки
            Row(
              children: [
                Expanded(
                  child: _buildActionTile(
                    context: context,
                    icon: Icons.search_rounded,
                    title: 'Справочник продуктов',
                    subtitle: 'Полный хим. состав, витамины, минералы',
                    color: AppColors.carbs,
                    onTap: () => SearchProductModal.show(
                      context,
                      mode: SearchMode.browseCatalog,
                      onAddedFromCatalog: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecipeEditorScreen()),
                        );
                      },
                    ),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionTile(
                    context: context,
                    icon: Icons.calculate_rounded,
                    title: 'Формула расчета',
                    subtitle: 'ЭЦ = Б×4 + Ж×9 + У×4',
                    color: AppColors.protein,
                    onTap: () => _showFormulaInfo(context),
                    isDark: isDark,
                  ),
                ),
              ],
            ),

            // Список сохраненных рецептов (если есть)
            if (savedDishes.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Сохраненные блюда (${savedDishes.length})',
                    style: AppTypography.titleMedium
                        .copyWith(fontWeight: FontWeight.w700),
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
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Коэффициенты сохранности нутриентов',
              description:
                  'По умолчанию приняты коэффициенты сохранности:\n• Белки (Б): 94%\n• Жиры (Ж): 88%\n• Углеводы (У): 91%\nЭто настраиваемое допущение, а не универсальная норма ГОСТ. Для блюд без т.о. выберите 100 / 100 / 100%.',
              icon: Icons.thermostat_rounded,
              color: AppColors.fat,
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Два режима бланка',
              description:
                  '1. «Бланк с крестом (учебный)»: диагональный крест в колонке ккал сырья, итоговая калорийность только после т.о.\n2. «Подробный расчёт»: калории рассчитаны для каждого продукта.',
              icon: Icons.splitscreen_rounded,
              color: AppColors.primary,
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            _buildInfoCard(
              title: 'Форматы экспорта',
              description:
                  'Экспорт в векторный PDF (идентично типовому бланку), Microsoft Word (.docx) и Microsoft Excel (.xlsx) с живыми формулами и печатью с телефона.',
              icon: Icons.file_download_outlined,
              color: AppColors.kcal,
              isDark: isDark,
            ),
          ],
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
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            color: AppColors.primary,
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
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                '${dish.ingredients.length} инг.',
                style: AppTypography.bodySmall.copyWith(fontSize: 11.5),
              ),
              Text(
                'Выход: ${CalculationEngine.formatGrams(calc.yieldGrams)} г',
                style: AppTypography.bodySmall.copyWith(fontSize: 11.5),
              ),
              Text(
                '${CalculationEngine.formatKcal(calc.cookedKcal)} ккал',
                style: AppTypography.numericSmall.copyWith(
                  color: AppColors.kcal,
                  fontWeight: FontWeight.w700,
                ),
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
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.kcal),
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
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
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
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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
