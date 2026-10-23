import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/nutrient_chip.dart';

enum SearchMode {
  pickForRecipe,
  browseCatalog,
}

/// Поиск и выбор продукта (аудит P1-5).
///
/// Главное решение — **combo-pick**: тап по строке не закрывает поиск, а
/// раскрывает её на месте (`AnimatedSize`), внутри появляется ввод массы с
/// сегментом `Брутто | Нетто` и кнопкой добавления. Модалка закрывается
/// только после подтверждения, поэтому пользователь в любой момент может
/// вернуться к списку и взять другой продукт.
///
/// Путь «Картофель, 250 г брутто»: тап по FAB → ввод «Картофель» → тап по
/// строке → `250` на клавиатуре → тап «Брутто» → «Добавить в блюдо».
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

  /// Продукт, строка которого сейчас раскрыта для ввода массы.
  int? _expandedProductId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(searchProvider).query;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final isCatalog = widget.mode == SearchMode.browseCatalog;
    final media = MediaQuery.of(context);

    return Padding(
      // Системная клавиатура больше не выжимает список до двух строк:
      // шит поднимается над `viewInsets`.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: media.size.height * 0.92,
          minHeight: media.size.height * 0.5,
        ),
        decoration: BoxDecoration(
          color: Palette.of(context).surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeader(context, isCatalog),
              _buildSourceSegment(context),
              _buildSearchField(context),
              Divider(height: 1, color: Palette.of(context).divider),
              Expanded(
                child: searchState.isLoading && searchState.results.isEmpty
                    ? const Center(child: CircularProgressIndicator.adaptive())
                    : searchState.results.isEmpty
                        ? _buildEmpty(context)
                        : _buildResults(context, isCatalog),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isCatalog) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x1, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isCatalog ? 'Справочник продуктов' : 'Добавить продукт',
              style: AppTypography.title.copyWith(color: p.ink),
              maxLines: 2,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Закрыть',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Источник — сегментированный фильтр в шапке с количеством продуктов.
  /// Раньше источник показывался 10-px плашкой в каждой строке из 9235
  /// продуктов — невидимый шум. Теперь это одно решение на весь поиск.
  Widget _buildSourceSegment(BuildContext context) {
    final p = Palette.of(context);
    final current = ref.watch(searchProvider).selectedSource;
    final counts = ref.watch(sourceCountsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const SourceCounts(),
        );
    final autoFocus = ref.watch(searchProvider.select((s) => s.query.isEmpty)) &&
        mounted;

    String label(String name, int count) =>
        count == 0 ? name : '$name · ${_spaced(count)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String?>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, kMinTapTarget),
            backgroundColor: p.surface,
            foregroundColor: p.inkSecondary,
            selectedBackgroundColor: p.accentSoft,
            selectedForegroundColor: p.accent,
            side: BorderSide(color: p.border),
            shape: RoundedRectangleBorder(borderRadius: Radii.fieldAll),
            textStyle: AppTypography.label,
          ),
          segments: [
            const ButtonSegment(
              value: null,
              label: Text('Все', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: 'skurikhin',
              label: Text(label('Скурихин', counts.skurikhin),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ButtonSegment(
              value: 'usda',
              label: Text(label('USDA', counts.usda),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
          selected: {current},
          onSelectionChanged: (value) {
            AppHaptics.toggle();
            ref.read(searchProvider.notifier).setSourceFilter(value.single);
            setState(() => _expandedProductId = null);
          },
        ),
      ),
    ).unfocusSuffix(autoFocus);
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        onChanged: (val) {
          setState(() {});
          ref.read(searchProvider.notifier).search(val);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Картофель, говядина, молоко…',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Очистить запрос',
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
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: p.inkMuted),
          const SizedBox(height: Space.x3),
          Text('Ничего не найдено',
              style: AppTypography.headline.copyWith(color: p.inkSecondary)),
          const SizedBox(height: Space.x1),
          Text('Попробуйте изменить запрос или снять фильтры',
              style: AppTypography.bodySm.copyWith(color: p.inkMuted)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context, bool isCatalog) {
    final results = ref.watch(searchProvider).results;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.x6),
      itemCount: results.length,
      itemBuilder: (context, idx) {
        final product = results[idx];
        if (isCatalog) return _buildCatalogRow(context, product);
        return _buildPickRow(context, product);
      },
    );
  }

  /// Строка поиска с раскрытием на месте (combo-pick).
  Widget _buildPickRow(BuildContext context, Product product) {
    final p = Palette.of(context);
    final expanded = _expandedProductId == product.id;
    final valid = _isValid(product);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: expanded ? p.sunken : Colors.transparent,
          child: InkWell(
            onTap: () {
              AppHaptics.key();
              setState(() {
                _expandedProductId = expanded ? null : product.id;
              });
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              padding: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x4, Space.x2),
              child: Row(
                children: [
                  // Тонкая полоска источника (3 dp) вместо цветного бейджа.
                  Container(
                    width: 3,
                    height: 32,
                    margin: const EdgeInsets.only(right: Space.x3),
                    decoration: BoxDecoration(
                      color: p.sourceLine,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.body.copyWith(
                            color: valid ? p.ink : p.inkSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: Space.x3,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              product.source.toLowerCase() == 'skurikhin'
                                  ? 'Скурихин'
                                  : 'USDA',
                              style: AppTypography.caption
                                  .copyWith(color: p.sourceInk),
                            ),
                            NutrientChip(
                              type: NutrientType.kcal,
                              value:
                                  CalculationEngine.formatKcal(product.kcal),
                              compact: true,
                            ),
                            NutrientChip(
                              type: NutrientType.protein,
                              value: CalculationEngine.formatMacro(
                                  product.protein),
                              compact: true,
                            ),
                            if (product.wastePct > 0)
                              Text(
                                'отходы ${CalculationEngine.formatWastePercent(product.wastePct)}%',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkSecondary),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 22,
                    color: valid ? p.accent : p.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Раскрытие на месте, без закрытия модалки.
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.ease,
          alignment: Alignment.topCenter,
          child: expanded
              ? (valid
                  ? _buildInlineEditor(context, product)
                  : _buildInvalidNotice(context, product))
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, color: p.divider),
      ],
    );
  }

  Widget _buildInlineEditor(BuildContext context, Product product) {
    // Тот же кейпад, что и в отдельном шите — единый компонент. Модалка
    // поиска при этом не закрывается, контекст не теряется.
    return Material(
      color: Palette.of(context).surface,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.x2),
        child: CustomNumpadSheet(
          key: ValueKey('numpad-${product.id}'),
          product: product,
          initialGrams: 100,
          onProductUpdated: (updated) {},
          onConfirm: (grams, isGross) {
            _addToRecipe(product, grams, isGross);
          },
        ),
      ),
    );
  }

  Widget _buildInvalidNotice(BuildContext context, Product product) {
    final p = Palette.of(context);
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: p.inkMuted),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              'Продукт «${product.name}» недоступен для расчёта '
              '(сумма БЖУ превышает 100 г в исходных данных USDA).',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogRow(BuildContext context, Product product) {
    final p = Palette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              AppHaptics.key();
              _openProductInfoCard(product);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              padding: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x4, Space.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: AppTypography.body.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  NutrientChip(
                    type: NutrientType.kcal,
                    value: CalculationEngine.formatKcal(product.kcal),
                    compact: true,
                  ),
                  const SizedBox(width: Space.x2),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: p.inkMuted),
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: p.divider),
      ],
    );
  }

  bool _isValid(Product product) {
    try {
      CalculationValidation.product(product);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _addToRecipe(Product product, double grams, bool isGross) {
    ref.read(dishProvider.notifier).addIngredient(
          product,
          grams,
          isGross: isGross,
        );
    widget.onAddedFromCatalog?.call();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _expandedProductId = null);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Добавлено: ${product.name} · ${CalculationEngine.formatGrams(grams)} г',
        ),
        duration: const Duration(seconds: 2),
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
          Navigator.pop(context);
          // Карточку закрыли — раскрываем строку на месте, а не уводим на
          // отдельный кейпад: контекст поиска сохраняется.
          if (widget.mode == SearchMode.pickForRecipe) {
            setState(() => _expandedProductId = product.id);
          } else {
            widget.onAddedFromCatalog?.call();
          }
        },
      ),
    );
  }

  /// 6 402 → «6 402» (узкий неразрывный пробел — не разрывается переносом).
  static String _spaced(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('\u2009');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Счётчики продуктов по источникам для сегментированного фильтра.
class SourceCounts {
  final int skurikhin;
  final int usda;
  const SourceCounts({this.skurikhin = 0, this.usda = 0});
}

final sourceCountsProvider = FutureProvider<SourceCounts>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final all = await repo.searchProducts(query: '', limit: 100000);
  return SourceCounts(
    skurikhin: all.where((p) => p.source.toLowerCase() == 'skurikhin').length,
    usda: all.where((p) => p.source.toLowerCase() == 'usda').length,
  );
});

/// Карточка состава продукта (справочник). API не изменён — её проверяют
/// тесты (`ProductInfoCardSheet(product:, onAddToRecipe:)` и текст про
/// «доступен только для справки»).
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
    final p = Palette.of(context);
    final nutrientsAsync = ref.watch(productNutrientsProvider(product.id));

    bool isValid = true;
    try {
      CalculationValidation.product(product);
    } catch (_) {
      isValid = false;
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x1, Space.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.title.copyWith(color: p.ink),
                        ),
                        const SizedBox(height: Space.x1),
                        Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              product.source.toLowerCase() == 'skurikhin'
                                  ? 'Скурихин'
                                  : 'USDA',
                              style: AppTypography.caption
                                  .copyWith(color: p.sourceInk),
                            ),
                            Text('Код: ${product.code}',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkMuted)),
                            if (product.pageNum != null &&
                                product.pageNum! > 0)
                              Text('Стр. ${product.pageNum}',
                                  style: AppTypography.caption
                                      .copyWith(color: p.inkMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMacroBlock(p),
                    const SizedBox(height: Space.x4),
                    _sectionTitle(p,
                        'Химический состав и технологические показатели'),
                    const SizedBox(height: Space.x2),
                    _kvBox(p, [
                      (
                        'Вода',
                        '${CalculationEngine.formatMacro(product.water)} г'
                      ),
                      (
                        'Пищевые волокна (клетчатка)',
                        '${CalculationEngine.formatMacro(product.fiber)} г'
                      ),
                      ('Зола', '${CalculationEngine.formatMacro(product.ash)} г'),
                      if (product.sugars > 0)
                        (
                          'Моно- и дисахариды (сахара)',
                          '${CalculationEngine.formatMacro(product.sugars)} г'
                        ),
                      if (product.starch > 0)
                        (
                          'Крахмал',
                          '${CalculationEngine.formatMacro(product.starch)} г'
                        ),
                      if (product.organicAcids > 0)
                        (
                          'Органические кислоты',
                          '${CalculationEngine.formatMacro(product.organicAcids)} г'
                        ),
                      if (product.sfa > 0)
                        (
                          'Насыщенные жирные кислоты',
                          '${CalculationEngine.formatMacro(product.sfa)} г'
                        ),
                      if (product.pufa > 0)
                        (
                          'Полиненасыщенные жирные кислоты',
                          '${CalculationEngine.formatMacro(product.pufa)} г'
                        ),
                      if (product.chol > 0)
                        (
                          'Холестерин',
                          '${CalculationEngine.formatGrams(product.chol)} мг'
                        ),
                      (
                        'Отходы при холодной обработке',
                        '${CalculationEngine.formatWastePercent(product.wastePct)} %'
                      ),
                    ]),
                    if (product.calculationMeasures.isNotEmpty) ...[
                      const SizedBox(height: Space.x4),
                      _sectionTitle(p, 'Масса в бытовых мерах и штуках'),
                      const SizedBox(height: Space.x2),
                      Wrap(
                        spacing: Space.x2,
                        runSpacing: Space.x2,
                        children: product.calculationMeasures.map((m) {
                          return Container(
                            constraints:
                                const BoxConstraints(minHeight: kMinTapTarget),
                            padding: const EdgeInsets.symmetric(
                                horizontal: Space.x3, vertical: Space.x2),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: Radii.chipAll,
                              border: Border.all(color: p.border),
                            ),
                            child: Text(
                              '${m.name}: ${CalculationEngine.formatGrams(m.grams)} г',
                              style: AppTypography.numSm.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
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
                              const SizedBox(height: Space.x4),
                              _sectionTitle(
                                  p, 'Минеральные вещества (на 100 г)'),
                              const SizedBox(height: Space.x2),
                              _kvBox(
                                p,
                                minerals
                                    .map((m) => (
                                          m.name,
                                          '${CalculationEngine.formatMacro(m.value)} ${m.unit}'
                                        ))
                                    .toList(),
                              ),
                            ],
                            if (vitamins.isNotEmpty) ...[
                              const SizedBox(height: Space.x4),
                              _sectionTitle(p, 'Витамины (на 100 г)'),
                              const SizedBox(height: Space.x2),
                              _kvBox(
                                p,
                                vitamins
                                    .map((v) => (
                                          v.name,
                                          '${CalculationEngine.formatMacro(v.value)} ${v.unit}'
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        );
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.all(Space.x4),
                        child:
                            Center(child: CircularProgressIndicator.adaptive()),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            if (!isValid)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.x3, vertical: Space.x2),
                  decoration: BoxDecoration(
                    color: p.dangerSoft,
                    borderRadius: Radii.fieldAll,
                    border: Border.all(color: p.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: p.danger, size: 18),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Text(
                          'Сумма нутриентов в данных USDA превышает 100 г '
                          '(${(product.protein + product.fat + product.carbs).toStringAsFixed(2)} г). '
                          'Продукт доступен только для справки.',
                          style: AppTypography.caption.copyWith(color: p.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.x4, Space.x2, Space.x4, Space.x3),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isValid ? onAddToRecipe : null,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: Text(
                    isValid
                        ? 'Добавить в расчет'
                        : 'Недоступно для расчёта (ошибка БЖУ в USDA)',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(Palette p, String text) =>
      Text(text, style: AppTypography.label.copyWith(color: p.ink));

  /// Числовая строка БЖУ: tabular figures, без цветных заливок (правило R2).
  Widget _buildMacroBlock(Palette p) {
    final cells = <(String, String, Color)>[
      (
        'Белки',
        '${CalculationEngine.formatMacro(product.protein)} г',
        p.protein
      ),
      ('Жиры', '${CalculationEngine.formatMacro(product.fat)} г', p.fat),
      (
        'Углеводы',
        '${CalculationEngine.formatMacro(product.carbs)} г',
        p.carbs
      ),
      ('ккал', CalculationEngine.formatKcal(product.kcal), p.kcal),
    ];
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x3),
      decoration: BoxDecoration(
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Пищевая ценность на 100 г съедобной части',
            style: AppTypography.caption.copyWith(color: p.inkSecondary),
          ),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x6,
            runSpacing: Space.x2,
            children: cells.map((c) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 2,
                    height: 30,
                    color: c.$3,
                    margin: const EdgeInsets.only(right: Space.x2),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$1,
                          style:
                              AppTypography.caption.copyWith(color: p.inkMuted)),
                      Text(c.$2, style: AppTypography.num.copyWith(color: p.ink)),
                    ],
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _kvBox(Palette p, List<(String, String)> rows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
      decoration: BoxDecoration(
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic),
      ),
      child: Column(
        children: rows
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r.$1,
                            style: AppTypography.bodySm
                                .copyWith(color: p.inkSecondary)),
                      ),
                      const SizedBox(width: Space.x2),
                      Text(r.$2,
                          style: AppTypography.numSm.copyWith(color: p.ink)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

extension _UnfocusSuffix on Widget {
  Widget unfocusSuffix(bool _) => this;
}
