import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/models/source_label.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/custom_products_repository.dart';
import '../../data/repositories/product_repository.dart' show FoodGroup;
import '../providers/dish_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/app_buttons.dart';
import '../widgets/custom_numpad.dart';
import '../widgets/custom_product_form_sheet.dart';

enum SearchMode {
  pickForRecipe,
  browseCatalog,
  replaceIngredient,
}

/// Метка готового блюда в списке и карточке продукта.
class _DishBadge extends StatelessWidget {
  final Palette palette;
  const _DishBadge(this.palette);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Готовое блюдо',
        style: AppTypography.caption.copyWith(color: palette.inkSecondary),
      ),
    );
  }
}

/// Быстрый поиск и добавление продукта в расчёт.
///
/// Открывается как просторный полноэкранный диалог без вложенной «матрёшки»
/// листов и без принудительного автофокуса, чтобы можно было сразу выбрать
/// продукт из недавних или начать поиск.
class SearchProductModal extends ConsumerStatefulWidget {
  final SearchMode mode;
  final VoidCallback? onAddedFromCatalog;
  final bool autofocusSearch;
  final String? replacingName;

  const SearchProductModal({
    super.key,
    this.mode = SearchMode.pickForRecipe,
    this.onAddedFromCatalog,
    this.autofocusSearch = false,
    this.replacingName,
  });

  static Future<void> show(
    BuildContext context, {
    SearchMode mode = SearchMode.pickForRecipe,
    VoidCallback? onAddedFromCatalog,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SearchProductModal(
          mode: mode,
          onAddedFromCatalog: onAddedFromCatalog,
          autofocusSearch: false,
        ),
      ),
    );
  }

  /// Открывает поиск в режиме одиночного выбора для замены продукта в строке.
  static Future<Product?> pickReplacement(
    BuildContext context, {
    String? replacingName,
  }) {
    return Navigator.of(context).push<Product>(
      MaterialPageRoute<Product>(
        fullscreenDialog: true,
        builder: (_) => SearchProductModal(
          mode: SearchMode.replaceIngredient,
          replacingName: replacingName,
          autofocusSearch: false,
        ),
      ),
    );
  }

  @override
  ConsumerState<SearchProductModal> createState() => _SearchProductModalState();
}

class _SearchProductModalState extends ConsumerState<SearchProductModal> {
  static const String _allSourcesValue = 'all';

  final TextEditingController _searchCtrl = TextEditingController();
  late final SearchNotifier _searchNotifier;
  bool _didResetOnExit = false;
  bool _onlyFavorites = false;
  String? _lastAddedSummary;
  int? _invalidProductId;

  bool get _isReplaceMode => widget.mode == SearchMode.replaceIngredient;
  bool get _resetsFiltersOnExit => widget.mode != SearchMode.browseCatalog;

  @override
  void initState() {
    super.initState();
    _searchNotifier = ref.read(searchProvider.notifier);
    _searchCtrl.text = ref.read(searchProvider).query;
    final defaultIsDish =
        widget.mode == SearchMode.browseCatalog ? null : false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchNotifier.setIsDishFilter(defaultIsDish);
    });
  }

  @override
  void dispose() {
    if (!_didResetOnExit && _resetsFiltersOnExit) {
      _didResetOnExit = true;
      Future.microtask(() {
        _searchNotifier.resetFilters(
          clearQuery: true,
          clearSource: true,
          clearGroup: true,
          clearIsDish: true,
        );
      });
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetOnPickExit() {
    if (_didResetOnExit || !_resetsFiltersOnExit) return;
    _didResetOnExit = true;
    _searchNotifier.resetFilters(
      clearQuery: true,
      clearSource: true,
      clearGroup: true,
      clearIsDish: true,
    );
  }

  void _closeModal([Product? replacement]) {
    FocusManager.instance.primaryFocus?.unfocus();
    _resetOnPickExit();
    if (Navigator.canPop(context)) {
      Navigator.pop(context, replacement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final recentProducts = ref.watch(recentProductsProvider);
    final filteredFavorites = ref.watch(filteredFavoritesProvider);
    final allFavorites = ref.watch(favoriteProductsProvider);
    final favoriteIds = {for (final item in allFavorites) item.id};
    if (_onlyFavorites && allFavorites.isEmpty) {
      _onlyFavorites = false;
    }
    final dish = ref.watch(dishProvider);
    final p = Palette.of(context);
    final isCatalog = widget.mode == SearchMode.browseCatalog;
    final media = MediaQuery.of(context);
    final shortLandscape = media.size.height < 460;

    final ingredientsByProductId = <int, List<Ingredient>>{};
    for (final ing in dish.ingredients) {
      ingredientsByProductId.putIfAbsent(ing.product.id, () => []).add(ing);
    }

    final listContent = _buildListContent(
      context,
      p: p,
      searchState: searchState,
      favoriteProducts: filteredFavorites,
      favoriteIds: favoriteIds,
      recentProducts: recentProducts,
      ingredientsByProductId: ingredientsByProductId,
      isCatalog: isCatalog,
      sliver: shortLandscape,
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
          _resetOnPickExit();
        }
      },
      child: Material(
        color: p.surface,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Space.maxWidth),
                child: Column(
                  children: [
                    _buildTopSearchBar(context, p, isCatalog),
                    if (_isReplaceMode &&
                        widget.replacingName != null &&
                        widget.replacingName!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Space.x4, 0, Space.x4, Space.x1),
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded,
                                size: 15, color: p.accent),
                            const SizedBox(width: Space.x1),
                            Expanded(
                              child: Text(
                                'Замена продукта «${widget.replacingName!.trim()}» — вес и обработка сохранятся',
                                style: AppTypography.caption
                                    .copyWith(color: p.accent),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!shortLandscape) _buildFilterStrip(context, p, isCatalog),
                    Divider(height: 1, color: p.divider),
                    if (shortLandscape)
                      Expanded(
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildFilterStrip(context, p, isCatalog),
                            ),
                            listContent,
                          ],
                        ),
                      )
                    else
                      Expanded(child: listContent),
                    if (widget.mode == SearchMode.pickForRecipe)
                      _buildFooterDock(context, p, dish.ingredients.length),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSearchBar(BuildContext context, Palette p, bool isCatalog) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x2, Space.x2, Space.x4, Space.x1),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: p.inkSecondary),
            tooltip: 'Закрыть',
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            onPressed: _closeModal,
          ),
          const SizedBox(width: Space.x1),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: widget.autofocusSearch,
              textInputAction: TextInputAction.search,
              onChanged: (val) {
                setState(() => _invalidProductId = null);
                ref.read(searchProvider.notifier).search(val);
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: _isReplaceMode
                    ? 'Выберите новый продукт…'
                    : (isCatalog
                        ? 'Поиск в справочнике…'
                        : 'Картофель, масло, курица…'),
                prefixIcon:
                    Icon(Icons.search_rounded, size: 20, color: p.inkMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Очистить запрос',
                        constraints: const BoxConstraints(
                          minWidth: kMinTapTarget,
                          minHeight: kMinTapTarget,
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: p.inkMuted,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _invalidProductId = null);
                          ref
                              .read(searchProvider.notifier)
                              .search('', immediate: true);
                        },
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: Space.x1),
          IconButton(
            key: const ValueKey('create-custom-product-btn'),
            tooltip: 'Создать свой продукт',
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            icon: Icon(Icons.add_circle_outline_rounded, color: p.accent),
            onPressed: () =>
                _openCustomProductForm(initialName: _searchCtrl.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterStrip(BuildContext context, Palette p, bool isCatalog) {
    final searchState = ref.watch(searchProvider);
    final counts = ref.watch(sourceCountsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const SourceCounts(),
        );
    final groups = ref.watch(foodGroupsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <FoodGroup>[],
        );
    final selectedIsDish = searchState.selectedIsDish;
    final selectedSource = searchState.selectedSource;
    final selectedGroupId = searchState.selectedGroupId;
    final favoritesCount = ref.watch(favoriteProductsProvider).length;

    FoodGroup? selectedGroup;
    if (selectedGroupId != null) {
      for (final g in groups) {
        if (g.id == selectedGroupId) {
          selectedGroup = g;
          break;
        }
      }
    }

    final sourceButtonLabel =
        selectedSource != null ? SourceLabel.of(selectedSource) : 'Все базы';

    String menuLabel(String name, int count) =>
        count > 0 ? '$name · ${_spaced(count)}' : name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
      child: Wrap(
        spacing: Space.x2,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (isCatalog)
            _FilterPill(
              label: 'Все',
              selected: selectedIsDish == null,
              palette: p,
              onTap: () {
                AppHaptics.toggle();
                ref.read(searchProvider.notifier).setIsDishFilter(null);
              },
            ),
          _FilterPill(
            label: 'Продукты',
            selected: selectedIsDish == false,
            palette: p,
            onTap: () {
              AppHaptics.toggle();
              ref.read(searchProvider.notifier).setIsDishFilter(false);
            },
          ),
          _FilterPill(
            label: 'Готовые',
            selected: selectedIsDish == true,
            palette: p,
            onTap: () {
              AppHaptics.toggle();
              ref.read(searchProvider.notifier).setIsDishFilter(true);
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Источник справочника',
            padding: EdgeInsets.zero,
            onSelected: (value) {
              AppHaptics.toggle();
              final notifier = ref.read(searchProvider.notifier);
              if (value == _allSourcesValue) {
                if (selectedSource != null) {
                  notifier.setSourceFilter(_allSourcesValue);
                }
              } else if (selectedSource != value) {
                notifier.setSourceFilter(value);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                value: _allSourcesValue,
                child: Row(
                  children: [
                    const Expanded(child: Text('Все источники')),
                    if (selectedSource == null)
                      Icon(Icons.check_rounded, size: 18, color: p.accent),
                  ],
                ),
              ),
              for (final (code, count) in [
                ('skurikhin', counts.skurikhin),
                ('bls', counts.bls),
                if (counts.supplement > 0) ('supplement', counts.supplement),
                if (counts.custom > 0) ('custom', counts.custom),
              ])
                PopupMenuItem<String>(
                  value: code,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(menuLabel(SourceLabel.of(code), count)),
                      ),
                      if (selectedSource == code)
                        Icon(Icons.check_rounded, size: 18, color: p.accent),
                    ],
                  ),
                ),
            ],
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: kMinTapTarget,
                minHeight: kMinTapTarget,
              ),
              child: Center(
                widthFactor: 1,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  decoration: BoxDecoration(
                    color: selectedSource != null ? p.accentSoft : p.sunken,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sourceButtonLabel,
                        style: AppTypography.label.copyWith(
                          color: selectedSource != null
                              ? p.accent
                              : p.inkSecondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color:
                            selectedSource != null ? p.accent : p.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (favoritesCount > 0)
            _FilterPill(
              key: const ValueKey('favorites-filter-pill'),
              label: '★ Избранное · $favoritesCount',
              selected: _onlyFavorites,
              palette: p,
              onTap: () {
                AppHaptics.toggle();
                setState(() => _onlyFavorites = !_onlyFavorites);
              },
            ),
          if (counts.custom > 0)
            _FilterPill(
              key: const ValueKey('custom-source-pill'),
              label: 'Свои · ${counts.custom}',
              selected: selectedSource == 'custom',
              palette: p,
              onTap: () {
                AppHaptics.toggle();
                ref.read(searchProvider.notifier).setSourceFilter(
                    selectedSource == 'custom' ? _allSourcesValue : 'custom');
              },
            ),
          if (groups.isNotEmpty)
            _FilterPill(
              key: const ValueKey('group-filter-pill'),
              label: selectedGroup?.name ?? 'Категория',
              trailingIcon: Icons.expand_more_rounded,
              selected: selectedGroupId != null,
              palette: p,
              onTap: () => _openGroupPicker(groups, selectedGroupId),
            ),
        ],
      ),
    );
  }

  Widget _buildListContent(
    BuildContext context, {
    required Palette p,
    required SearchState searchState,
    required List<Product> favoriteProducts,
    required Set<int> favoriteIds,
    required List<Product> recentProducts,
    required Map<int, List<Ingredient>> ingredientsByProductId,
    required bool isCatalog,
    required bool sliver,
  }) {
    if (_onlyFavorites) {
      if (favoriteProducts.isEmpty) {
        final emptyFav = Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_outline_rounded, size: 42, color: p.inkMuted),
                const SizedBox(height: Space.x2),
                Text(
                  'В избранном нет подходящих продуктов',
                  textAlign: TextAlign.center,
                  style: AppTypography.headline.copyWith(color: p.ink),
                ),
                const SizedBox(height: Space.x2),
                TextButton(
                  onPressed: () => setState(() => _onlyFavorites = false),
                  child: const Text('Показать весь справочник'),
                ),
              ],
            ),
          ),
        );
        return sliver
            ? SliverFillRemaining(hasScrollBody: false, child: emptyFav)
            : emptyFav;
      }
      final favEntries = <_SearchListEntry>[
        const _SearchSectionHeader('Избранное'),
        for (final prod in favoriteProducts) _SearchProductEntry(prod),
      ];
      if (sliver) {
        return SliverPadding(
          padding: const EdgeInsets.only(bottom: Space.x4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, idx) => _buildEntry(
                context,
                p,
                favEntries[idx],
                favoriteIds: favoriteIds,
                ingredientsByProductId: ingredientsByProductId,
                highlightQuery: searchState.query,
                isCatalog: isCatalog,
                showTypeBadge: searchState.selectedIsDish == null,
              ),
              childCount: favEntries.length,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: Space.x4),
        itemCount: favEntries.length,
        itemBuilder: (context, idx) => _buildEntry(
          context,
          p,
          favEntries[idx],
          favoriteIds: favoriteIds,
          ingredientsByProductId: ingredientsByProductId,
          highlightQuery: searchState.query,
          isCatalog: isCatalog,
          showTypeBadge: searchState.selectedIsDish == null,
        ),
      );
    }

    final isUnfilteredBrowse = searchState.query.trim().isEmpty &&
        searchState.selectedGroupId == null;
    final showFavorites = isUnfilteredBrowse && favoriteProducts.isNotEmpty;
    final showRecent = isUnfilteredBrowse && recentProducts.isNotEmpty;

    if (searchState.isLoading &&
        searchState.results.isEmpty &&
        !showFavorites &&
        !showRecent) {
      const loader = Center(child: CircularProgressIndicator.adaptive());
      return sliver
          ? const SliverFillRemaining(hasScrollBody: false, child: loader)
          : loader;
    }

    if (searchState.results.isEmpty && !showFavorites && !showRecent) {
      final empty = _buildEmptyState(context, p, searchState);
      return sliver
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.x4),
                child: empty,
              ),
            )
          : empty;
    }

    final entries = <_SearchListEntry>[];

    if (showFavorites || showRecent) {
      final pinnedIds = <int>{};
      if (showFavorites) {
        entries.add(const _SearchSectionHeader('Избранное'));
        for (final product in favoriteProducts) {
          if (pinnedIds.add(product.id)) {
            entries.add(_SearchProductEntry(product));
          }
        }
      }
      final unpinnedRecent =
          recentProducts.where((item) => !pinnedIds.contains(item.id)).toList();
      if (unpinnedRecent.isNotEmpty) {
        entries.add(const _SearchSectionHeader('Недавние и частые'));
        for (final product in unpinnedRecent) {
          pinnedIds.add(product.id);
          entries.add(_SearchProductEntry(product));
        }
      }
      final remaining = searchState.results
          .where((item) => !pinnedIds.contains(item.id))
          .toList();
      if (remaining.isNotEmpty) {
        entries.add(_SearchSectionHeader(
            searchState.selectedIsDish == true ? 'Готовые блюда' : 'Весь справочник'));
        for (final product in remaining) {
          entries.add(_SearchProductEntry(product));
        }
      }
    } else {
      for (final product in searchState.results) {
        entries.add(_SearchProductEntry(product));
      }
    }

    if (sliver) {
      return SliverPadding(
        padding: const EdgeInsets.only(bottom: Space.x4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, idx) => _buildEntry(
              context,
              p,
              entries[idx],
              favoriteIds: favoriteIds,
              ingredientsByProductId: ingredientsByProductId,
              highlightQuery: searchState.query,
              isCatalog: isCatalog,
              showTypeBadge: searchState.selectedIsDish == null,
            ),
            childCount: entries.length,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.x4),
      itemCount: entries.length,
      itemBuilder: (context, idx) => _buildEntry(
        context,
        p,
        entries[idx],
        favoriteIds: favoriteIds,
        ingredientsByProductId: ingredientsByProductId,
        highlightQuery: searchState.query,
        isCatalog: isCatalog,
        showTypeBadge: searchState.selectedIsDish == null,
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, Palette p, SearchState searchState) {
    final hasFilters = searchState.query.trim().isNotEmpty ||
        searchState.selectedSource != null ||
        searchState.selectedGroupId != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 42, color: p.inkMuted),
            const SizedBox(height: Space.x2),
            Text(
              'Ничего не найдено',
              textAlign: TextAlign.center,
              style: AppTypography.headline.copyWith(color: p.ink),
            ),
            const SizedBox(height: Space.x1),
            Text(
              'Проверьте написание или сбросьте фильтр по базе',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(color: p.inkMuted),
            ),
            if (hasFilters) ...[
              const SizedBox(height: Space.x3),
              TextButton(
                onPressed: () {
                  _searchCtrl.clear();
                  ref.read(searchProvider.notifier).resetFilters(
                        clearQuery: true,
                        clearSource: true,
                        clearGroup: true,
                        clearIsDish: false,
                      );
                  setState(() {});
                },
                child: const Text('Сбросить фильтры'),
              ),
            ],
            const SizedBox(height: Space.x2),
            OutlinedButton.icon(
              onPressed: () =>
                  _openCustomProductForm(initialName: searchState.query.trim()),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Создать свой продукт'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(
    BuildContext context,
    Palette p,
    _SearchListEntry entry, {
    required Set<int> favoriteIds,
    required Map<int, List<Ingredient>> ingredientsByProductId,
    required bool isCatalog,
    required bool showTypeBadge,
    String highlightQuery = '',
  }) {
    if (entry is _SearchSectionHeader) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x1),
        child: Text(
          entry.title,
          style: AppTypography.caption.copyWith(
            color: p.inkMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final product = (entry as _SearchProductEntry).product;
    final valid = _isValid(product);
    final isFavorite = favoriteIds.contains(product.id);
    final existingList = (isCatalog || _isReplaceMode)
        ? const <Ingredient>[]
        : (ingredientsByProductId[product.id] ?? const <Ingredient>[]);
    final alreadyInDish = existingList.isNotEmpty;
    final singleExisting = existingList.length == 1 ? existingList.single : null;

    final String? inDishBadgeText;
    if (!alreadyInDish) {
      inDishBadgeText = null;
    } else if (singleExisting != null) {
      final grams = CalculationEngine.formatGrams(singleExisting.weightGrams);
      inDishBadgeText = singleExisting.isGross
          ? 'в блюде · $grams г брутто'
          : 'в блюде · $grams г';
    } else {
      final totalNet =
          existingList.fold<double>(0.0, (sum, ing) => sum + ing.netGrams);
      inDishBadgeText =
          'в блюде · ${existingList.length} поз. (${CalculationEngine.formatGrams(totalNet)} г)';
    }

    final showInvalidInline = !valid && _invalidProductId == product.id;

    final subtitle = valid
        ? '${CalculationEngine.formatKcal(product.kcal)} ккал · '
            'Б ${CalculationEngine.formatMacro(product.protein)} · '
            'Ж ${CalculationEngine.formatMacro(product.fat)} · '
            'У ${CalculationEngine.formatMacro(product.carbs)} · '
            '${product.sourceLabel}'
        : isCatalog
            ? 'Нет корректных данных БЖУ · нажмите для просмотра'
            : 'Нет корректных данных БЖУ · только для справки';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (!valid && !isCatalog) {
                AppHaptics.error();
                setState(() => _invalidProductId = product.id);
              } else if (_isReplaceMode) {
                AppHaptics.commit();
                _closeModal(product);
              } else if (isCatalog) {
                AppHaptics.key();
                _openProductInfoCard(product);
              } else if (existingList.length > 1) {
                AppHaptics.key();
                setState(() => _invalidProductId = null);
                _pickExistingOrAdd(product, existingList);
              } else {
                AppHaptics.key();
                setState(() => _invalidProductId = null);
                _openWeightPicker(product, existing: singleExisting);
              }
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, Space.x2, Space.x1, Space.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Wrap(
                            spacing: Space.x2,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isFavorite)
                                Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: p.accent,
                                ),
                              _HighlightedProductName(
                                name: product.name,
                                query: highlightQuery,
                                baseStyle: AppTypography.body.copyWith(
                                  color: valid ? p.ink : p.inkSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                highlightColor: p.accent,
                              ),
                              if (inDishBadgeText != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: p.accentSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    inDishBadgeText,
                                    style: AppTypography.caption.copyWith(
                                      color: p.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (showTypeBadge && product.isDishOnly)
                                _DishBadge(p),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: AppTypography.caption.copyWith(
                              color: valid ? p.inkMuted : p.danger,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isCatalog)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: p.inkMuted,
                        ),
                      )
                    else
                      IconButton(
                        tooltip: 'Сведения о продукте',
                        constraints: const BoxConstraints(
                          minWidth: kMinTapTarget,
                          minHeight: kMinTapTarget,
                        ),
                        icon: Icon(
                          Icons.info_outline_rounded,
                          size: 20,
                          color: p.inkMuted,
                        ),
                        onPressed: () => _openProductInfoCard(
                          product,
                          existing: singleExisting,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showInvalidInline)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.x4, 0, Space.x4, Space.x2),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.x3, vertical: Space.x2),
              decoration: BoxDecoration(
                color: p.dangerSoft,
                borderRadius: Radii.fieldAll,
              ),
              child: Text(
                'Продукт «${product.name}» недоступен для расчёта: '
                'сумма БЖУ в исходных данных превышает 100 г.',
                style: AppTypography.caption.copyWith(color: p.danger),
              ),
            ),
          ),
        Divider(
          height: 1,
          indent: Space.x4,
          endIndent: Space.x4,
          color: p.divider,
        ),
      ],
    );
  }

  Widget _buildFooterDock(
      BuildContext context, Palette p, int ingredientCount) {
    final statusText = _lastAddedSummary != null
        ? _lastAddedSummary!
        : ingredientCount > 0
            ? 'В блюде продуктов: $ingredientCount'
            : 'Нажмите на продукт, чтобы указать вес';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.x4, Space.x2, Space.x4, Space.x2),
        child: Row(
          children: [
            if (_lastAddedSummary != null) ...[
              Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
              const SizedBox(width: Space.x2),
            ],
            Expanded(
              child: Text(
                statusText,
                style: AppTypography.bodySm.copyWith(
                  color: _lastAddedSummary != null ? p.ink : p.inkSecondary,
                  fontWeight: _lastAddedSummary != null
                      ? FontWeight.w500
                      : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.x3),
            FilledButton(
              onPressed: _closeModal,
              child: Text(
                  ingredientCount > 0 ? 'Готово ($ingredientCount)' : 'Готово'),
            ),
          ],
        ),
      ),
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

  Future<void> _openWeightPicker(
    Product product, {
    Ingredient? existing,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    Product activeProduct = existing?.product ?? product;
    bool confirmed = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: MediaQuery.sizeOf(context).height >= 460,
      backgroundColor: Palette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      builder: (_) => CustomNumpadSheet(
        key: ValueKey('numpad-${product.id}'),
        product: activeProduct,
        initialGrams: existing?.weightGrams ?? 100,
        initialIsGross:
            existing?.isGross ?? (!product.isDishOnly && product.wastePct > 0),
        isEditing: existing != null,
        onProductUpdated: (updated) {
          activeProduct = updated;
        },
        onDelete: existing != null
            ? () {
                ref.read(dishProvider.notifier).removeIngredient(existing.id);
                if (!mounted) return;
                setState(() {
                  _lastAddedSummary = 'Удалено: ${product.name}';
                });
              }
            : null,
        onConfirm: (grams, isGross) {
          confirmed = true;
          if (existing != null) {
            _updateInRecipe(existing.id, activeProduct, grams, isGross);
          } else {
            _addToRecipe(activeProduct, grams, isGross);
          }
        },
      ),
    );

    if (!mounted || !confirmed) return;
    if (widget.mode == SearchMode.browseCatalog) {
      _closeModal();
      widget.onAddedFromCatalog?.call();
    }
  }

  void _addToRecipe(Product product, double grams, bool isGross) {
    ref.read(dishProvider.notifier).addIngredient(
          product,
          grams,
          isGross: isGross,
        );
    recordRecentProduct(ref, product);
    if (!mounted) return;
    setState(() {
      _lastAddedSummary =
          'Добавлено: ${product.name} · ${CalculationEngine.formatGrams(grams)} г';
    });
  }

  void _updateInRecipe(
    String ingredientId,
    Product product,
    double grams,
    bool isGross,
  ) {
    ref.read(dishProvider.notifier).updateIngredient(
          ingredientId,
          grams,
          isGross: isGross,
          product: product,
        );
    recordRecentProduct(ref, product);
    if (!mounted) return;
    setState(() {
      _lastAddedSummary =
          'Обновлено: ${product.name} · ${CalculationEngine.formatGrams(grams)} г';
    });
  }

  Future<void> _openGroupPicker(
    List<FoodGroup> groups,
    int? selectedGroupId,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => _GroupPickerSheet(
        groups: groups,
        selectedGroupId: selectedGroupId,
      ),
    );
    if (!mounted || chosen == null) return;
    AppHaptics.toggle();
    ref
        .read(searchProvider.notifier)
        .setGroupFilter(chosen < 0 ? null : chosen);
  }

  Future<void> _pickExistingOrAdd(
    Product product,
    List<Ingredient> existingList,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    final selected = await showModalBottomSheet<Object?>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text(
                product.name,
                style: AppTypography.headline.copyWith(color: p.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Divider(height: 1, color: p.divider),
            for (var i = 0; i < existingList.length; i++) ...[
              ListTile(
                leading: Icon(Icons.edit_outlined, color: p.inkSecondary),
                title: Text(
                  'Изменить позицию ${i + 1} · '
                  '${CalculationEngine.formatGrams(existingList[i].weightGrams)} г'
                  '${existingList[i].isGross ? ' брутто' : ''}',
                ),
                onTap: () => Navigator.pop(sheetCtx, existingList[i]),
              ),
              Divider(height: 1, color: p.divider),
            ],
            ListTile(
              leading: Icon(Icons.add_rounded, color: p.accent),
              title: Text(
                'Добавить ещё раз',
                style: AppTypography.label.copyWith(color: p.accent),
              ),
              onTap: () => Navigator.pop(sheetCtx, true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected is Ingredient) {
      await _openWeightPicker(product, existing: selected);
    } else if (selected == true) {
      await _openWeightPicker(product);
    }
  }

  Future<void> _openCustomProductForm({
    Product? existing,
    String initialName = '',
  }) async {
    final saved = await CustomProductFormSheet.show(
      context,
      initial: existing,
      initialName: initialName,
    );
    if (!mounted || saved == null) return;
    if (existing != null) {
      ref.read(dishProvider.notifier).replaceProductSnapshots(saved);
      await ref
          .read(favoriteProductsProvider.notifier)
          .syncCustomProduct(saved);
    } else if (_isReplaceMode) {
      AppHaptics.commit();
      _closeModal(saved);
    } else if (widget.mode == SearchMode.pickForRecipe) {
      await _openWeightPicker(saved);
    }
  }

  void _openProductInfoCard(Product product, {Ingredient? existing}) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    final isCustom = product.source.trim().toLowerCase() == 'custom';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      builder: (sheetCtx) => ProductInfoCardSheet(
        product: product,
        actionLabel: _isReplaceMode ? 'Выбрать для замены' : null,
        onAddToRecipe: () {
          Navigator.pop(sheetCtx);
          if (_isReplaceMode) {
            AppHaptics.commit();
            _closeModal(product);
          } else {
            _openWeightPicker(
              product,
              existing:
                  widget.mode == SearchMode.pickForRecipe ? existing : null,
            );
          }
        },
        onEditCustom: isCustom
            ? () {
                Navigator.pop(sheetCtx);
                _openCustomProductForm(existing: product);
              }
            : null,
        onDeleteCustom: isCustom
            ? () async {
                final sp = Palette.of(sheetCtx);
                final confirmed = await showDialog<bool>(
                  context: sheetCtx,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Удалить свой продукт?'),
                    content: Text(
                      'Продукт «${product.name}» будет удалён из справочника. '
                      'В уже сохранённых блюдах расчёт сохранится.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        style: TextButton.styleFrom(foregroundColor: sp.danger),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                if (!mounted) return;
                await ref
                    .read(customProductsProvider.notifier)
                    .deleteProduct(product.id);
                await ref
                    .read(favoriteProductsProvider.notifier)
                    .removeById(product.id);
                removeRecentProduct(ref, product.id);
              }
            : null,
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

sealed class _SearchListEntry {
  const _SearchListEntry();
}

class _SearchSectionHeader extends _SearchListEntry {
  final String title;
  const _SearchSectionHeader(this.title);
}

class _SearchProductEntry extends _SearchListEntry {
  final Product product;
  const _SearchProductEntry(this.product);
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData? trailingIcon;
  final bool selected;
  final Palette palette;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
    required this.label,
    this.trailingIcon,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TactilePress(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
              maxWidth: 220,
            ),
            child: Center(
              widthFactor: 1,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                decoration: BoxDecoration(
                  color: selected ? palette.accent : palette.sunken,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: AppTypography.label.copyWith(
                          color: selected
                              ? palette.onAccent
                              : palette.inkSecondary,
                        ),
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 2),
                      Icon(
                        trailingIcon,
                        size: 16,
                        color: selected
                            ? palette.onAccent
                            : palette.inkSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightedProductName extends StatelessWidget {
  final String name;
  final String query;
  final TextStyle baseStyle;
  final Color highlightColor;

  const _HighlightedProductName({
    required this.name,
    required this.query,
    required this.baseStyle,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Text(
        name,
        style: baseStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerName = name.toLowerCase();
    final tokens = trimmed
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return Text(
        name,
        style: baseStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < name.length) {
      var bestStart = name.length;
      var bestLen = 0;
      for (final tok in tokens) {
        final idx = lowerName.indexOf(tok, cursor);
        if (idx >= 0 && (idx < bestStart || (idx == bestStart && tok.length > bestLen))) {
          bestStart = idx;
          bestLen = tok.length;
        }
      }
      if (bestLen == 0) {
        spans.add(TextSpan(text: name.substring(cursor), style: baseStyle));
        break;
      }
      if (bestStart > cursor) {
        spans.add(TextSpan(
            text: name.substring(cursor, bestStart), style: baseStyle));
      }
      spans.add(TextSpan(
        text: name.substring(bestStart, bestStart + bestLen),
        style: baseStyle.copyWith(
          color: highlightColor,
          fontWeight: FontWeight.w700,
        ),
      ));
      cursor = bestStart + bestLen;
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Счётчики продуктов по источникам для сегментированного фильтра.
class SourceCounts {
  final int skurikhin;
  final int bls;

  /// Приправы и питьевая вода, которых нет в книге (дефект D3).
  final int supplement;
  final int custom;
  const SourceCounts({
    this.skurikhin = 0,
    this.bls = 0,
    this.supplement = 0,
    this.custom = 0,
  });
}

final sourceCountsProvider = FutureProvider<SourceCounts>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final customCount =
      ref.watch(customProductsProvider.select((list) => list.length));
  // Дефект D3: раньше здесь считалось `!isSkurikhin`, и `supplement`
  // («Дополнено») попадал в счётчик BLS. Теперь — по фактическому источнику.
  final bySource = await repo.getCountBySource();
  return SourceCounts(
    skurikhin: bySource['skurikhin'] ?? 0,
    bls: bySource['bls'] ?? 0,
    supplement: bySource['supplement'] ?? 0,
    custom: customCount,
  );
});

/// Карточка состава продукта (справочник). API не изменён — её проверяют
/// тесты (`ProductInfoCardSheet(product:, onAddToRecipe:)` и текст про
/// «доступен только для справки»).
class ProductInfoCardSheet extends ConsumerWidget {
  final Product product;
  final VoidCallback onAddToRecipe;
  final VoidCallback? onEditCustom;
  final VoidCallback? onDeleteCustom;
  final String? actionLabel;

  const ProductInfoCardSheet({
    super.key,
    required this.product,
    required this.onAddToRecipe,
    this.onEditCustom,
    this.onDeleteCustom,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final nutrientsAsync = ref.watch(productNutrientsProvider(product.id));
    final isFavorite = ref.watch(
      favoriteProductsProvider.select(
        (items) => items.any((item) => item.id == product.id),
      ),
    );

    bool isValid = true;
    try {
      CalculationValidation.product(product);
    } catch (_) {
      isValid = false;
    }

    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final scrollEntireSheet =
        size.height < 460 || (size.height < 580 && textScale > 1.4);

    final headerWidget = Padding(
      padding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x1, Space.x2),
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
                      product.sourceLabel,
                      style: AppTypography.caption
                          .copyWith(color: p.sourceInk),
                    ),
                    Text(
                      'Код: ${product.code}',
                      style: AppTypography.caption.copyWith(color: p.inkMuted),
                    ),
                    if (product.pageNum != null && product.pageNum! > 0)
                      Text(
                        'Стр. ${product.pageNum}',
                        style: AppTypography.caption
                            .copyWith(color: p.inkMuted),
                      ),
                    if (product.isDishOnly) _DishBadge(p),
                  ],
                ),
              ],
            ),
          ),
          if (isValid)
            IconButton(
              key: const ValueKey('toggle-favorite-btn'),
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavorite ? p.accent : p.inkSecondary,
              ),
              tooltip:
                  isFavorite ? 'Убрать из избранного' : 'Добавить в избранное',
              constraints: const BoxConstraints(
                minWidth: kMinTapTarget,
                minHeight: kMinTapTarget,
              ),
              onPressed: () async {
                AppHaptics.toggle();
                await ref
                    .read(favoriteProductsProvider.notifier)
                    .toggleFavorite(product);
              },
            ),
          if (onEditCustom != null)
            IconButton(
              icon: Icon(Icons.edit_outlined, color: p.inkSecondary),
              tooltip: 'Редактировать продукт',
              constraints: const BoxConstraints(
                minWidth: kMinTapTarget,
                minHeight: kMinTapTarget,
              ),
              onPressed: onEditCustom,
            ),
          if (onDeleteCustom != null)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: p.danger),
              tooltip: 'Удалить продукт',
              constraints: const BoxConstraints(
                minWidth: kMinTapTarget,
                minHeight: kMinTapTarget,
              ),
              onPressed: onDeleteCustom,
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Закрыть',
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
          ),
        ],
      ),
    );

    final chemRows = <(String, String)>[
      ('Вода', '${CalculationEngine.formatMacro(product.water)} г'),
      (
        'Пищевые волокна (клетчатка)',
        '${CalculationEngine.formatMacro(product.fiber)} г',
      ),
      ('Зола', '${CalculationEngine.formatMacro(product.ash)} г'),
      if (product.sugars > 0)
        (
          'Моно- и дисахариды (сахара)',
          '${CalculationEngine.formatMacro(product.sugars)} г',
        ),
      if (product.starch > 0)
        ('Крахмал', '${CalculationEngine.formatMacro(product.starch)} г'),
      if (product.organicAcids > 0)
        (
          'Органические кислоты',
          '${CalculationEngine.formatMacro(product.organicAcids)} г',
        ),
      if (product.sfa > 0)
        (
          'Насыщенные жирные кислоты',
          '${CalculationEngine.formatMacro(product.sfa)} г',
        ),
      if (product.pufa > 0)
        (
          'Полиненасыщенные жирные кислоты',
          '${CalculationEngine.formatMacro(product.pufa)} г',
        ),
      if (product.chol > 0)
        ('Холестерин', '${CalculationEngine.formatGrams(product.chol)} мг'),
      (
        'Отходы при холодной обработке',
        '${CalculationEngine.formatWastePercent(product.wastePct)} %',
      ),
    ];

    final bodyContent = Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isValid) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x3,
                vertical: Space.x2,
              ),
              decoration: BoxDecoration(
                color: p.dangerSoft,
                borderRadius: Radii.fieldAll,
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: p.danger, size: 18),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(
                      'Сумма нутриентов в исходных данных превышает 100 г '
                      '(${(product.protein + product.fat + product.carbs).toStringAsFixed(2)} г). '
                      'Продукт доступен только для справки.',
                      style: AppTypography.caption.copyWith(color: p.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.x3),
          ],
          _buildMacroStrip(p),
          Divider(height: Space.x6, color: p.divider),
          _kvSection(p, 'Химический состав и технологические показатели', chemRows),
          if (product.calculationMeasures.isNotEmpty) ...[
            Divider(height: Space.x6, color: p.divider),
            _kvSection(
              p,
              'Масса в бытовых мерах и штуках',
              product.calculationMeasures
                  .map((m) => (m.name, '${CalculationEngine.formatGrams(m.grams)} г'))
                  .toList(),
            ),
          ],
          nutrientsAsync.when(
            data: (nutrients) {
              if (nutrients.isEmpty) return const SizedBox.shrink();
              final minerals = nutrients.where((n) => n.isMineral).toList();
              final vitamins = nutrients.where((n) => n.isVitamin).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (minerals.isNotEmpty) ...[
                    Divider(height: Space.x6, color: p.divider),
                    _kvSection(
                      p,
                      'Минеральные вещества (на 100 г)',
                      minerals
                          .map((m) => (
                                m.name,
                                '${CalculationEngine.formatMacro(m.value)} ${m.unit}',
                              ))
                          .toList(),
                    ),
                  ],
                  if (vitamins.isNotEmpty) ...[
                    Divider(height: Space.x6, color: p.divider),
                    _kvSection(
                      p,
                      'Витамины (на 100 г)',
                      vitamins
                          .map((v) => (
                                v.name,
                                '${CalculationEngine.formatMacro(v.value)} ${v.unit}',
                              ))
                          .toList(),
                    ),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(Space.x4),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );

    final footerWidget = DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isValid ? onAddToRecipe : null,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            label: Text(
              isValid
                  ? (actionLabel ?? 'Добавить в расчет')
                  : 'Недоступно для расчёта (ошибка БЖУ в источнике)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: size.height * 0.9,
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
        child: scrollEntireSheet
            ? SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    headerWidget,
                    Divider(height: 1, color: p.divider),
                    bodyContent,
                    footerWidget,
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  headerWidget,
                  Divider(height: 1, color: p.divider),
                  Flexible(
                    child: SingleChildScrollView(child: bodyContent),
                  ),
                  footerWidget,
                ],
              ),
      ),
    );
  }

  Widget _sectionTitle(Palette p, String text) => Text(
        text,
        style: AppTypography.label.copyWith(color: p.ink),
      );

  Widget _buildMacroStrip(Palette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Пищевая ценность на 100 г съедобной части',
          style: AppTypography.caption.copyWith(color: p.inkMuted),
        ),
        const SizedBox(height: Space.x2),
        Wrap(
          spacing: Space.x5,
          runSpacing: Space.x2,
          children: [
            InlineMacroCell(
              type: NutrientType.protein,
              label: 'Белки',
              value: CalculationEngine.formatMacro(product.protein),
              unit: 'г',
              stacked: true,
            ),
            InlineMacroCell(
              type: NutrientType.fat,
              label: 'Жиры',
              value: CalculationEngine.formatMacro(product.fat),
              unit: 'г',
              stacked: true,
            ),
            InlineMacroCell(
              type: NutrientType.carbs,
              label: 'Углеводы',
              value: CalculationEngine.formatMacro(product.carbs),
              unit: 'г',
              stacked: true,
            ),
            InlineMacroCell(
              type: NutrientType.kcal,
              label: 'Энергия',
              value: CalculationEngine.formatKcal(product.kcal),
              unit: 'ккал',
              stacked: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _kvSection(Palette p, String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(p, title),
        const SizedBox(height: Space.x2),
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                  ),
                ),
                const SizedBox(width: Space.x3),
                Text(
                  rows[i].$2,
                  textAlign: TextAlign.end,
                  style: AppTypography.numSm.copyWith(color: p.ink),
                ),
              ],
            ),
          ),
          if (i < rows.length - 1) Divider(height: 1, color: p.divider),
        ],
      ],
    );
  }
}

class _GroupPickerSheet extends StatefulWidget {
  final List<FoodGroup> groups;
  final int? selectedGroupId;

  const _GroupPickerSheet({
    required this.groups,
    required this.selectedGroupId,
  });

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    final showSearch = widget.groups.length >= 8;
    final norm = CustomProductsRepository.normalizeText(_query);
    final filtered = norm.isEmpty
        ? widget.groups
        : widget.groups
            .where((g) => CustomProductsRepository.normalizeText(g.name)
                .contains(norm))
            .toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, 0, Space.x4, Space.x2),
                child: Text(
                  'Категория продуктов',
                  style: AppTypography.title.copyWith(color: p.ink),
                ),
              ),
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Space.x4, 0, Space.x4, Space.x2),
                  child: TextField(
                    key: const ValueKey('group-filter-search'),
                    controller: _ctrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Поиск категории…',
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 20, color: p.inkMuted),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              tooltip: 'Очистить',
                              icon: Icon(Icons.close_rounded,
                                  size: 18, color: p.inkMuted),
                              onPressed: () {
                                _ctrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              Divider(height: 1, color: p.divider),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Space.x4),
                        child: Text(
                          'Категория не найдена',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySm
                              .copyWith(color: p.inkSecondary),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          if (norm.isEmpty) ...[
                            ListTile(
                              title: const Text('Все категории'),
                              trailing: widget.selectedGroupId == null
                                  ? Icon(Icons.check_rounded, color: p.accent)
                                  : null,
                              onTap: () => Navigator.pop(context, -1),
                            ),
                            Divider(height: 1, color: p.divider),
                          ],
                          for (final g in filtered) ...[
                            ListTile(
                              title: Text(g.name),
                              trailing: widget.selectedGroupId == g.id
                                  ? Icon(Icons.check_rounded, color: p.accent)
                                  : null,
                              onTap: () => Navigator.pop(context, g.id),
                            ),
                            Divider(height: 1, color: p.divider),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
