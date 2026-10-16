import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/source_badge.dart';

enum SearchMode {
  pickForRecipe,
  browseCatalog,
}

class SearchProductModal extends ConsumerStatefulWidget {
  final SearchMode mode;
  final VoidCallback? onAddedFromCatalog;

  const SearchProductModal({
    super.key,
    this.mode = SearchMode.pickForRecipe,
    this.onAddedFromCatalog,
  });

  static Future<void> show(
    BuildContext context, {
    SearchMode mode = SearchMode.pickForRecipe,
    VoidCallback? onAddedFromCatalog,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchProductModal(
        mode: mode,
        onAddedFromCatalog: onAddedFromCatalog,
      ),
    );
  }

  @override
  ConsumerState<SearchProductModal> createState() => _SearchProductModalState();
}

class _SearchProductModalState extends ConsumerState<SearchProductModal> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final currentQuery = ref.read(searchProvider).query;
    _searchCtrl.text = currentQuery;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final groupsAsync = ref.watch(foodGroupsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCatalog = widget.mode == SearchMode.browseCatalog;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Шапка модального окна
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      isCatalog ? 'Справочник продуктов' : 'Поиск продуктов',
                      style: AppTypography.titleLarge
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Поле ввода поиска
                TextField(
                  controller: _searchCtrl,
                  autofocus: !isCatalog,
                  textInputAction: TextInputAction.search,
                  onChanged: (val) {
                    setState(() {});
                    ref.read(searchProvider.notifier).search(val);
                  },
                  decoration: InputDecoration(
                    hintText: 'Поиск: картофель, говядина, молоко...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                              ref
                                  .read(searchProvider.notifier)
                                  .search('', immediate: true);
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),

                // Фильтры по источнику (Все / Скурихин / USDA)
                Row(
                  children: [
                    _buildSourceChip(null, 'Все источники', isDark),
                    const SizedBox(width: 6),
                    _buildSourceChip('skurikhin', 'Скурихин', isDark),
                    const SizedBox(width: 6),
                    _buildSourceChip('usda', 'USDA', isDark),
                  ],
                ),
                const SizedBox(height: 6),

                // Категории продуктов (горизонтальный скролл с фильтрацией по источнику)
                groupsAsync.when(
                  data: (groups) => SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: groups.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, idx) {
                        final g = groups[idx];
                        final isSelected = searchState.selectedGroupId == g.id;
                        return FilterChip(
                          label: Text(g.name),
                          selected: isSelected,
                          onSelected: (_) => ref
                              .read(searchProvider.notifier)
                              .setGroupFilter(g.id),
                          labelStyle: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : null,
                          ),
                          selectedColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      },
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Список найденных продуктов
          Expanded(
            child: searchState.isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : searchState.results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: isDark
                                  ? AppColors.textMutedDark
                                  : AppColors.textMutedLight,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ничего не найдено',
                              style: AppTypography.titleMedium.copyWith(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Попробуйте изменить запрос или снять фильтры',
                              style: AppTypography.bodySmall.copyWith(
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: searchState.results.length,
                        itemBuilder: (context, idx) {
                          final product = searchState.results[idx];
                          return _buildProductListItem(product, isDark);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(String? sourceKey, String label, bool isDark) {
    final searchState = ref.watch(searchProvider);
    final isSelected = searchState.selectedSource == sourceKey;

    return InkWell(
      onTap: () => ref.read(searchProvider.notifier).setSourceFilter(sourceKey),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.cardDark : AppColors.backgroundLight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.borderDark : AppColors.borderLight),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : null,
          ),
        ),
      ),
    );
  }

  Widget _buildProductListItem(Product p, bool isDark) {
    final isCatalog = widget.mode == SearchMode.browseCatalog;

    return ListTile(
      onTap: () {
        if (isCatalog) {
          _openProductInfoCard(p);
        } else {
          _pickProductForRecipe(p);
        }
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Row(
        children: [
          Expanded(
            child: Text(
              p.name,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SourceBadge(source: p.source, compact: true),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Б: ${CalculationEngine.formatMacro(p.protein)}г',
              style:
                  AppTypography.numericSmall.copyWith(color: AppColors.protein),
            ),
            Text(
              'Ж: ${CalculationEngine.formatMacro(p.fat)}г',
              style: AppTypography.numericSmall.copyWith(color: AppColors.fat),
            ),
            Text(
              'У: ${CalculationEngine.formatMacro(p.carbs)}г',
              style:
                  AppTypography.numericSmall.copyWith(color: AppColors.carbs),
            ),
            Text(
              '${CalculationEngine.formatKcal(p.kcal)} ккал',
              style: AppTypography.numericSmall.copyWith(
                color: AppColors.kcal,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (p.wastePct > 0)
              Text(
                'отходы ${p.wastePct.toInt()}%',
                style: AppTypography.bodySmall.copyWith(fontSize: 10),
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isCatalog)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              tooltip: 'Состав продукта',
              onPressed: () => _openProductInfoCard(p),
            ),
          Icon(
            isCatalog
                ? Icons.chevron_right_rounded
                : Icons.add_circle_outline_rounded,
            size: 22,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  void _pickProductForRecipe(Product product) {
    // Захватываем dishNotifier и родительский контекст ДО закрытия модального окна,
    // чтобы избежать StateError: Bad state: Cannot use ref after the widget was disposed.
    final dishNotifier = ref.read(dishProvider.notifier);
    final navContext = Navigator.of(context).context;
    final onAddedCallback = widget.onAddedFromCatalog;

    Navigator.pop(context);

    showModalBottomSheet(
      context: navContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomNumpadSheet(
        product: product,
        initialGrams: 100,
        initialIsGross: false,
        isEditing: false,
        onConfirm: (grams, isGross) {
          dishNotifier.addIngredient(
            product,
            grams,
            isGross: isGross,
          );
          onAddedCallback?.call();
        },
      ),
    );
  }

  void _openProductInfoCard(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductInfoCardSheet(
        product: product,
        onAddToRecipe: () {
          Navigator.pop(context); // закрыть карточку продукта
          _pickProductForRecipe(product);
        },
      ),
    );
  }
}

class ProductInfoCardSheet extends ConsumerWidget {
  final Product product;
  final VoidCallback onAddToRecipe;

  const ProductInfoCardSheet({
    super.key,
    required this.product,
    required this.onAddToRecipe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nutrientsAsync = ref.watch(productNutrientsProvider(product.id));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Шапка карточки
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[700] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: AppTypography.titleLarge.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SourceBadge(source: product.source),
                                Text(
                                  'Код: ${product.code}',
                                  style: AppTypography.bodySmall,
                                ),
                                if (product.pageNum != null &&
                                    product.pageNum! > 0)
                                  Text(
                                    'Стр. ${product.pageNum}',
                                    style: AppTypography.bodySmall,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Содержимое карточки со скроллом
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Пищевая ценность на 100 г съедобной части',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),

                    // Основные макронутриенты
                    Row(
                      children: [
                        _buildMacroTile(
                          'Белки',
                          '${CalculationEngine.formatMacro(product.protein)} г',
                          AppColors.protein,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildMacroTile(
                          'Жиры',
                          '${CalculationEngine.formatMacro(product.fat)} г',
                          AppColors.fat,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildMacroTile(
                          'Углеводы',
                          '${CalculationEngine.formatMacro(product.carbs)} г',
                          AppColors.carbs,
                          isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildMacroTile(
                          'Калории',
                          '${CalculationEngine.formatKcal(product.kcal)} ккал',
                          AppColors.kcal,
                          isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Общий химический состав (Вода, Пищевые волокна, Зола, Отходы и др.)
                    Text(
                      'Химический состав и технологические показатели',
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.cardDark
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Column(
                        children: [
                          _buildKvRow(
                            'Вода',
                            '${CalculationEngine.formatMacro(product.water)} г',
                          ),
                          _buildKvRow(
                            'Пищевые волокна (клетчатка)',
                            '${CalculationEngine.formatMacro(product.fiber)} г',
                          ),
                          _buildKvRow(
                            'Зола',
                            '${CalculationEngine.formatMacro(product.ash)} г',
                          ),
                          if (product.sugars > 0)
                            _buildKvRow(
                              'Моно- и дисахариды (сахара)',
                              '${CalculationEngine.formatMacro(product.sugars)} г',
                            ),
                          if (product.starch > 0)
                            _buildKvRow(
                              'Крахмал',
                              '${CalculationEngine.formatMacro(product.starch)} г',
                            ),
                          if (product.organicAcids > 0)
                            _buildKvRow(
                              'Органические кислоты',
                              '${CalculationEngine.formatMacro(product.organicAcids)} г',
                            ),
                          if (product.sfa > 0)
                            _buildKvRow(
                              'Насыщенные жирные кислоты',
                              '${CalculationEngine.formatMacro(product.sfa)} г',
                            ),
                          if (product.pufa > 0)
                            _buildKvRow(
                              'Полиненасыщенные жирные кислоты',
                              '${CalculationEngine.formatMacro(product.pufa)} г',
                            ),
                          if (product.chol > 0)
                            _buildKvRow(
                              'Холестерин',
                              '${CalculationEngine.formatGrams(product.chol)} мг',
                            ),
                          _buildKvRow(
                            'Отходы при холодной обработке',
                            '${CalculationEngine.formatGrams(product.wastePct)} %',
                            highlight: product.wastePct > 0,
                          ),
                        ],
                      ),
                    ),

                    // Бытовые меры веса (если есть)
                    if (product.measures.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Масса в бытовых мерах и штуках',
                        style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: product.measures.map((m) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: Text(
                              '${m.name}: ${CalculationEngine.formatGrams(m.grams)} г',
                              style: AppTypography.bodySmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    // Витамины и минералы
                    nutrientsAsync.when(
                      data: (nutrients) {
                        if (nutrients.isEmpty) return const SizedBox.shrink();
                        final minerals =
                            nutrients.where((n) => n.isMineral).toList();
                        final vitamins =
                            nutrients.where((n) => n.isVitamin).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (minerals.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Минеральные вещества (на 100 г)',
                                style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.cardDark
                                      : AppColors.backgroundLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.borderDark
                                        : AppColors.borderLight,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                child: Column(
                                  children: minerals
                                      .map((m) => _buildKvRow(
                                            m.name,
                                            '${CalculationEngine.formatMacro(m.value)} ${m.unit}',
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                            if (vitamins.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'Витамины (на 100 г)',
                                style: AppTypography.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.cardDark
                                      : AppColors.backgroundLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.borderDark
                                        : AppColors.borderLight,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                child: Column(
                                  children: vitamins
                                      .map((v) => _buildKvRow(
                                            v.name,
                                            '${CalculationEngine.formatMacro(v.value)} ${v.unit}',
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: CircularProgressIndicator.adaptive()),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),

            // Кнопка "Добавить в расчет"
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAddToRecipe,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text('Добавить в расчет'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroTile(
      String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              style: AppTypography.numeric.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKvRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(fontSize: 12.5),
            ),
          ),
          Text(
            value,
            style: AppTypography.numericSmall.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}
