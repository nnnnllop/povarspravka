import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/models/product.dart';
import '../../data/repositories/product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

final foodGroupsProvider = FutureProvider<List<FoodGroup>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final allGroups = await repo.getFoodGroups();
  final selectedSource = ref.watch(
    searchProvider.select((s) => s.selectedSource),
  );

  if (selectedSource == 'skurikhin') {
    return allGroups.where((g) => g.id >= 1 && g.id <= 12).toList();
  } else if (selectedSource == 'usda') {
    return allGroups.where((g) => g.id >= 101 && g.id <= 128).toList();
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
  final String? selectedSource; // 'skurikhin' or 'usda' or null
  final List<Product> results;
  final bool isLoading;

  const SearchState({
    this.query = '',
    this.selectedGroupId,
    this.selectedSource,
    this.results = const [],
    this.isLoading = false,
  });

  SearchState copyWith({
    String? query,
    int? selectedGroupId,
    bool clearGroupId = false,
    String? selectedSource,
    bool clearSource = false,
    List<Product>? results,
    bool? isLoading,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedGroupId:
          clearGroupId ? null : (selectedGroupId ?? this.selectedGroupId),
      selectedSource:
          clearSource ? null : (selectedSource ?? this.selectedSource),
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.watch(productRepositoryProvider);
  return SearchNotifier(repo);
});

class SearchNotifier extends StateNotifier<SearchState> {
  final ProductRepository _repo;
  Timer? _debounceTimer;
  int _requestId = 0;

  SearchNotifier(this._repo) : super(const SearchState()) {
    search('', immediate: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> search(String query, {bool immediate = false}) async {
    _debounceTimer?.cancel();
    final reqId = ++_requestId;
    state = state.copyWith(query: query, isLoading: true);

    if (immediate || query.trim().isEmpty) {
      await _executeSearch(query, reqId);
    } else {
      final completer = Completer<void>();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
        await _executeSearch(query, reqId);
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      return completer.future;
    }
  }

  Future<void> _executeSearch(String query, int reqId) async {
    try {
      final results = await _repo.searchProducts(
        query: query,
        groupId: state.selectedGroupId,
        source: state.selectedSource,
        limit: 60,
      );
      if (!mounted || reqId != _requestId) return;
      state = state.copyWith(results: results, isLoading: false);
    } catch (_) {
      if (!mounted || reqId != _requestId) return;
      state = state.copyWith(results: const [], isLoading: false);
    }
  }

  void setGroupFilter(int? groupId) {
    if (state.selectedGroupId == groupId) {
      state = state.copyWith(clearGroupId: true);
    } else {
      state = state.copyWith(selectedGroupId: groupId);
    }
    search(state.query, immediate: true);
  }

  void setSourceFilter(String? source) {
    final nextSource = state.selectedSource == source ? null : source;
    bool shouldClearGroup = false;
    final currentGroup = state.selectedGroupId;
    if (currentGroup != null) {
      if (nextSource == 'skurikhin' && (currentGroup < 1 || currentGroup > 12)) {
        shouldClearGroup = true;
      } else if (nextSource == 'usda' &&
          (currentGroup < 101 || currentGroup > 128)) {
        shouldClearGroup = true;
      }
    }

    state = state.copyWith(
      selectedSource: nextSource,
      clearSource: nextSource == null,
      clearGroupId: shouldClearGroup,
    );
    search(state.query, immediate: true);
  }
}
