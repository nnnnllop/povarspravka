import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/product.dart';
import '../../data/repositories/custom_products_repository.dart';
import '../../data/repositories/product_repository.dart';
import 'dish_provider.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

final customProductsRepositoryProvider = Provider<CustomProductsRepository>((ref) {
  return CustomProductsRepository();
});

final customProductsProvider =
    StateNotifierProvider<CustomProductsNotifier, List<Product>>((ref) {
  final repo = ref.watch(customProductsRepositoryProvider);
  return CustomProductsNotifier(repo);
});

class CustomProductsNotifier extends StateNotifier<List<Product>> {
  final CustomProductsRepository _repo;
  late final Future<void> _ready;
  Future<void> _writeQueue = Future<void>.value();

  CustomProductsNotifier(this._repo) : super(const []) {
    _ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _repo.loadAll();
    if (!mounted || state.isNotEmpty) return;
    state = loaded;
  }

  Future<void> flush() async {
    await _ready;
    await _writeQueue;
  }

  Future<Product> addProduct({
    required String name,
    required double protein,
    required double fat,
    required double carbs,
    required double kcal,
    double wastePct = 0.0,
    bool isDish = false,
  }) async {
    await _ready;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Введите название продукта');
    }
    final nextId = CustomProductsRepository.nextId(state);
    final product = Product(
      id: nextId,
      code: 'USER-${nextId.abs()}',
      name: trimmed,
      nameNorm: CustomProductsRepository.normalizeText(trimmed),
      groupId: 0,
      source: 'custom',
      wastePct: wastePct,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kcal: kcal,
      isDish: isDish,
    );
    CalculationValidation.product(product);
    final updated = [product, ...state];
    state = updated;
    await _enqueueSave(updated);
    return product;
  }

  Future<Product> updateProduct(Product updatedProduct) async {
    await _ready;
    final trimmed = updatedProduct.name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Введите название продукта');
    }
    final normalized = updatedProduct.copyWith(
      name: trimmed,
      nameNorm: CustomProductsRepository.normalizeText(trimmed),
      source: 'custom',
    );
    CalculationValidation.product(normalized);
    final updated = [
      for (final item in state)
        if (item.id == normalized.id) normalized else item,
    ];
    state = updated;
    await _enqueueSave(updated);
    return normalized;
  }

  Future<void> deleteProduct(int id) async {
    await _ready;
    final updated = state.where((p) => p.id != id).toList();
    state = updated;
    await _enqueueSave(updated);
  }

  /// Импортирует свои продукты из резервной копии (слияние или замена).
  Future<int> importProducts(
    List<Product> imported, {
    required bool replaceExisting,
  }) async {
    await _ready;
    final List<Product> next;
    int addedCount;
    if (replaceExisting) {
      next = <Product>[];
      final usedIds = <int>{};
      for (final p in imported) {
        if (!CalculationValidation.isValidProduct(p)) continue;
        final id = (p.id < 0 && !usedIds.contains(p.id))
            ? p.id
            : CustomProductsRepository.nextId(next);
        usedIds.add(id);
        next.add(p.copyWith(
          id: id,
          code: 'USER-${id.abs()}',
          nameNorm: CustomProductsRepository.normalizeText(p.name),
          source: 'custom',
        ));
      }
      addedCount = next.length;
    } else {
      next = List<Product>.from(state);
      final existingById = <int, Product>{for (final p in next) p.id: p};
      String sig(Product p) =>
          '${CustomProductsRepository.normalizeText(p.name)}|'
          '${p.protein}|${p.fat}|${p.carbs}|${p.kcal}|${p.wastePct}|${p.isDishOnly}';
      final existingSigs = {for (final p in next) sig(p)};
      addedCount = 0;
      for (final p in imported) {
        if (!CalculationValidation.isValidProduct(p)) continue;
        final signature = sig(p);
        if (existingSigs.contains(signature)) continue;
        final candidateId =
            (p.id < 0 && !existingById.containsKey(p.id))
                ? p.id
                : CustomProductsRepository.nextId(next);
        final item = p.copyWith(
          id: candidateId,
          code: 'USER-${candidateId.abs()}',
          nameNorm: CustomProductsRepository.normalizeText(p.name),
          source: 'custom',
        );
        next.add(item);
        existingById[candidateId] = item;
        existingSigs.add(signature);
        addedCount++;
      }
    }
    state = next;
    await _enqueueSave(next);
    return addedCount;
  }

  Future<void> _enqueueSave(List<Product> snapshot) {
    final next = _writeQueue.then((_) => _repo.saveAll(snapshot));
    _writeQueue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

final foodGroupsProvider = FutureProvider<List<FoodGroup>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final selectedSource = ref.watch(
    searchProvider.select((s) => s.selectedSource),
  );
  if (selectedSource == 'custom') {
    return const <FoodGroup>[];
  }
  final allGroups = await repo.getFoodGroups();

  if (selectedSource == 'skurikhin') {
    return allGroups.where((g) => g.id >= 1 && g.id <= 12).toList();
  } else if (selectedSource == 'bls' || selectedSource == 'usda') {
    // BLS 4.0: 20 категорий, группы 101…120
    return allGroups.where((g) => g.id >= 101 && g.id <= 120).toList();
  }
  return allGroups;
});

final productNutrientsProvider =
    FutureProvider.family<List<ProductNutrient>, int>((ref, productId) async {
  final repo = ref.watch(productRepositoryProvider);
  return repo.getNutrientsForProduct(productId);
});

class SearchState {
  final String query;
  final int? selectedGroupId;
  final String? selectedSource; // 'skurikhin' | 'bls' | null

  /// `false` — только продукты/сырьё, `true` — только готовые блюда,
  /// `null` — без фильтра (этап 6).
  final bool? selectedIsDish;
  final List<Product> results;
  final bool isLoading;
  final Object? error;

  const SearchState({
    this.query = '',
    this.selectedGroupId,
    this.selectedSource,
    this.selectedIsDish,
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  bool get hasError => error != null;

  SearchState copyWith({
    String? query,
    int? selectedGroupId,
    bool clearGroupId = false,
    String? selectedSource,
    bool clearSource = false,
    bool? selectedIsDish,
    bool clearIsDish = false,
    List<Product>? results,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedGroupId:
          clearGroupId ? null : (selectedGroupId ?? this.selectedGroupId),
      selectedSource:
          clearSource ? null : (selectedSource ?? this.selectedSource),
      selectedIsDish:
          clearIsDish ? null : (selectedIsDish ?? this.selectedIsDish),
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.watch(productRepositoryProvider);
  final notifier = SearchNotifier(
    repo,
    () => ref.read(customProductsProvider),
  );
  ref.listen<List<Product>>(customProductsProvider, (_, __) {
    notifier.refresh();
  });
  return notifier;
});

class SearchNotifier extends StateNotifier<SearchState> {
  final ProductRepository _repo;
  final List<Product> Function()? _getCustomProducts;
  Timer? _debounceTimer;
  Completer<void>? _pendingSearch;
  int _requestId = 0;

  SearchNotifier(this._repo, [this._getCustomProducts])
      : super(const SearchState()) {
    search('', immediate: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (_pendingSearch != null && !_pendingSearch!.isCompleted) {
      _pendingSearch!.complete();
    }
    _pendingSearch = null;
    super.dispose();
  }

  /// Повторно запускает текущий поиск (например, после добавления/правки «своего» продукта).
  Future<void> refresh() => search(state.query, immediate: true);

  Future<void> search(String query, {bool immediate = false}) async {
    _debounceTimer?.cancel();
    if (_pendingSearch != null && !_pendingSearch!.isCompleted) {
      _pendingSearch!.complete();
    }
    _pendingSearch = null;
    final reqId = ++_requestId;
    state = state.copyWith(query: query, isLoading: true);

    if (immediate || query.trim().isEmpty) {
      await _executeSearch(query, reqId);
    } else {
      final completer = Completer<void>();
      _pendingSearch = completer;
      _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
        await _executeSearch(query, reqId);
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      return completer.future;
    }
  }

  List<Product> _filterCustomProducts(String query) {
    final all = _getCustomProducts?.call() ?? const <Product>[];
    if (all.isEmpty) return const <Product>[];
    if (state.selectedGroupId != null) return const <Product>[];
    final source = state.selectedSource;
    if (source != null && source != 'custom') return const <Product>[];
    final normQuery = CustomProductsRepository.normalizeText(query);
    final tokens = normQuery.isEmpty
        ? const <String>[]
        : normQuery.split(' ').where((t) => t.isNotEmpty).toList();
    return all.where((p) {
      if (state.selectedIsDish != null && p.isDishOnly != state.selectedIsDish) {
        return false;
      }
      if (tokens.isEmpty) return true;
      final normName = CustomProductsRepository.normalizeText(p.name);
      return tokens.every(normName.contains);
    }).toList();
  }

  Future<void> _executeSearch(String query, int reqId) async {
    try {
      final customMatches = _filterCustomProducts(query);
      final List<Product> dbResults;
      if (state.selectedSource == 'custom') {
        dbResults = const <Product>[];
      } else {
        dbResults = await _repo.searchProducts(
          query: query,
          groupId: state.selectedGroupId,
          source: state.selectedSource,
          isDish: state.selectedIsDish,
          limit: 60,
        );
      }
      if (!mounted || reqId != _requestId) return;
      final combined = customMatches.isEmpty
          ? dbResults
          : <Product>[...customMatches, ...dbResults];
      state =
          state.copyWith(results: combined, isLoading: false, clearError: true);
    } catch (e) {
      if (!mounted || reqId != _requestId) return;
      state = state.copyWith(results: const [], isLoading: false, error: e);
    }
  }

  void setGroupFilter(int? groupId) {
    if (groupId == null) {
      if (state.selectedGroupId == null) return;
      state = state.copyWith(clearGroupId: true);
    } else if (state.selectedGroupId == groupId) {
      state = state.copyWith(clearGroupId: true);
    } else {
      state = state.copyWith(selectedGroupId: groupId);
    }
    search(state.query, immediate: true);
  }

  /// Переключение фильтра «Продукты | Готовые блюда | Все» (этап 6).
  void setIsDishFilter(bool? isDish) {
    if (state.selectedIsDish == isDish) return;
    state = state.copyWith(
      selectedIsDish: isDish,
      clearIsDish: isDish == null,
    );
    search(state.query, immediate: true);
  }

  void setSourceFilter(String? source) {
    final normalized = (source == null || source == 'all') ? null : source;
    final nextSource = normalized == null
        ? null
        : (state.selectedSource == normalized ? null : normalized);
    bool shouldClearGroup = false;
    final currentGroup = state.selectedGroupId;
    if (currentGroup != null) {
      if (nextSource == 'custom') {
        shouldClearGroup = true;
      } else if (nextSource == 'skurikhin' &&
          (currentGroup < 1 || currentGroup > 12)) {
        shouldClearGroup = true;
      } else if ((nextSource == 'bls' || nextSource == 'usda') &&
          (currentGroup < 101 || currentGroup > 120)) {
        shouldClearGroup = true;
      }
    }

    if (nextSource == state.selectedSource && !shouldClearGroup) {
      return;
    }

    state = state.copyWith(
      selectedSource: nextSource,
      clearSource: nextSource == null,
      clearGroupId: shouldClearGroup,
    );
    search(state.query, immediate: true);
  }

  /// Сбрасывает поисковый запрос и временные фильтры при выходе из выбора.
  void resetFilters({
    bool clearQuery = true,
    bool clearSource = true,
    bool clearGroup = true,
    bool clearIsDish = false,
  }) {
    if (!mounted) return;
    final hasAny =
        (clearQuery && state.query.isNotEmpty) ||
        (clearSource && state.selectedSource != null) ||
        (clearGroup && state.selectedGroupId != null) ||
        (clearIsDish && state.selectedIsDish != null);
    if (!hasAny) return;
    _debounceTimer?.cancel();
    _pendingSearch = null;
    _requestId++;
    final nextQuery = clearQuery ? '' : state.query;
    state = state.copyWith(
      query: nextQuery,
      clearSource: clearSource,
      clearGroupId: clearGroup,
      clearIsDish: clearIsDish,
    );
    search(nextQuery, immediate: true);
  }
}

/// Продукты, выбранные пользователем в текущей сессии (в памяти, без записи на диск).
final sessionRecentProductsProvider =
    StateProvider<List<Product>>((ref) => const []);

void recordRecentProduct(WidgetRef ref, Product product) {
  final current = ref.read(sessionRecentProductsProvider);
  final next = <Product>[
    product,
    for (final p in current)
      if (p.id != product.id) p,
  ];
  ref.read(sessionRecentProductsProvider.notifier).state =
      next.length > 8 ? next.sublist(0, 8) : next;
}

void removeRecentProduct(WidgetRef ref, int productId) {
  final current = ref.read(sessionRecentProductsProvider);
  if (!current.any((p) => p.id == productId)) return;
  ref.read(sessionRecentProductsProvider.notifier).state = [
    for (final p in current)
      if (p.id != productId) p,
  ];
}

void syncRecentProduct(WidgetRef ref, Product updated) {
  final current = ref.read(sessionRecentProductsProvider);
  if (!current.any((p) => p.id == updated.id)) return;
  ref.read(sessionRecentProductsProvider.notifier).state = [
    for (final p in current)
      if (p.id == updated.id) updated else p,
  ];
}

/// Чистый вычислитель списка «Недавние и частые» с учётом активных фильтров
/// и актуального состояния пользовательских («своих») продуктов.
List<Product> buildRecentProducts({
  required List<Product> sessionRecent,
  required List<Product> activeIngredients,
  required Iterable<List<Product>> savedDishIngredients,
  List<Product>? customProducts,
  bool? isDishFilter,
  String? selectedSource,
  int limit = 6,
}) {
  final Map<int, Product>? customById = customProducts == null
      ? null
      : <int, Product>{for (final p in customProducts) p.id: p};

  Product? resolveLive(Product p) {
    if (customById != null && p.source.trim().toLowerCase() == 'custom') {
      // Удалённый пользовательский продукт больше не должен всплывать в недавних.
      return customById[p.id];
    }
    return p;
  }

  bool matchesFilter(Product p) {
    if (isDishFilter != null && p.isDishOnly != isDishFilter) return false;
    if (selectedSource != null &&
        selectedSource.isNotEmpty &&
        p.source != selectedSource) {
      return false;
    }
    return true;
  }

  final byId = <int, Product>{};
  final scores = <int, int>{};

  // Свежий выбор в текущей сессии получает высокий приоритет.
  for (var i = 0; i < sessionRecent.length; i++) {
    final p = resolveLive(sessionRecent[i]);
    if (p == null || !matchesFilter(p)) continue;
    byId[p.id] = p;
    scores[p.id] = (scores[p.id] ?? 0) + 100 - i;
  }

  // Продукты из активного черновика.
  for (final raw in activeIngredients) {
    final p = resolveLive(raw);
    if (p == null || !matchesFilter(p)) continue;
    byId.putIfAbsent(p.id, () => p);
    scores[p.id] = (scores[p.id] ?? 0) + 10;
  }

  // Часто встречающиеся продукты из сохранённых блюд.
  for (final list in savedDishIngredients) {
    for (final raw in list) {
      final p = resolveLive(raw);
      if (p == null || !matchesFilter(p)) continue;
      byId.putIfAbsent(p.id, () => p);
      scores[p.id] = (scores[p.id] ?? 0) + 2;
    }
  }

  final sorted = byId.values.toList()
    ..sort((a, b) => (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0));
  return sorted.length > limit ? sorted.sublist(0, limit) : sorted;
}

/// Быстрые продукты для раздела «Недавние и частые» при пустом поиске.
final recentProductsProvider = Provider<List<Product>>((ref) {
  final session = ref.watch(sessionRecentProductsProvider);
  final activeDish = ref.watch(dishProvider);
  final saved = ref.watch(savedDishesProvider);
  final search = ref.watch(searchProvider);
  final custom = ref.watch(customProductsProvider);
  return buildRecentProducts(
    sessionRecent: session,
    activeIngredients: activeDish.ingredients.map((i) => i.product).toList(),
    savedDishIngredients:
        saved.map((d) => d.ingredients.map((i) => i.product).toList()),
    customProducts: custom,
    isDishFilter: search.selectedIsDish,
    selectedSource: search.selectedSource,
  );
});
