import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/product.dart';
import '../../data/repositories/dish_storage_repository.dart';

final dishStorageRepositoryProvider = Provider<DishStorageRepository>((ref) {
  return DishStorageRepository();
});

final savedDishesProvider =
    StateNotifierProvider<SavedDishesNotifier, List<Dish>>((ref) {
  final storage = ref.watch(dishStorageRepositoryProvider);
  return SavedDishesNotifier(storage);
});

final dishProvider = StateNotifierProvider<DishNotifier, Dish>((ref) {
  final storage = ref.watch(dishStorageRepositoryProvider);
  final savedNotifier = ref.read(savedDishesProvider.notifier);
  return DishNotifier(storage: storage, savedDishesNotifier: savedNotifier);
});

final calculationResultProvider = Provider<CalculationResult>((ref) {
  final dish = ref.watch(dishProvider);
  return CalculationEngine.calculate(dish);
});

class SavedDishesNotifier extends StateNotifier<List<Dish>> {
  final DishStorageRepository _storage;
  Dish? _latestDraft;

  SavedDishesNotifier(this._storage) : super(const []);

  void setInitialDishes(List<Dish> dishes, Dish? draft) {
    _latestDraft = draft;
    state = dishes;
  }

  Future<void> updateDraftReference(Dish draft) async {
    _latestDraft = draft;
    final idx = state.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      final updated = List<Dish>.from(state);
      updated[idx] = draft;
      state = updated;
    }
    await _storage.saveAll(activeDraft: _latestDraft, savedDishes: state);
  }

  void saveDish(Dish dish) {
    _latestDraft = dish;
    final existingIdx = state.indexWhere((d) => d.id == dish.id);
    final updated = List<Dish>.from(state);
    if (existingIdx >= 0) {
      updated[existingIdx] = dish;
    } else {
      updated.insert(0, dish);
    }
    state = updated;
    _storage.saveAll(activeDraft: _latestDraft, savedDishes: state).catchError(
      (Object error, StackTrace stack) {
        debugPrint('Failed to save library: $error');
      },
    );
  }

  void deleteDish(String id) {
    state = state.where((d) => d.id != id).toList();
    _storage.saveAll(activeDraft: _latestDraft, savedDishes: state).catchError(
      (Object error, StackTrace stack) {
        debugPrint('Failed to save library: $error');
      },
    );
  }

  Dish duplicateDish(Dish dish) {
    final now = DateTime.now();
    final copyTitle =
        dish.title.trim().isEmpty ? 'Блюдо (копия)' : '${dish.title} (копия)';
    final duplicated = dish.copyWith(
      id: '${now.millisecondsSinceEpoch}_copy',
      title: copyTitle,
      createdAt: now,
      updatedAt: now,
    );
    final updated = [duplicated, ...state];
    state = updated;
    _storage.saveAll(activeDraft: _latestDraft, savedDishes: state).catchError(
      (Object error, StackTrace stack) {
        debugPrint('Failed to save library: $error');
      },
    );
    return duplicated;
  }
}

class DishNotifier extends StateNotifier<Dish> {
  final DishStorageRepository? _storage;
  final SavedDishesNotifier? _savedDishesNotifier;
  late final Future<void> _ready;
  Future<void> _saveQueue = Future<void>.value();
  bool _editedBeforeLoad = false;
  Object? lastPersistenceError;

  Future<void> flushPendingSaves() async {
    await _saveQueue;
    if (lastPersistenceError != null) throw lastPersistenceError!;
  }

  DishNotifier({
    DishStorageRepository? storage,
    SavedDishesNotifier? savedDishesNotifier,
  })  : _storage = storage,
        _savedDishesNotifier = savedDishesNotifier,
        super(
          Dish(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ) {
    _ready = _initFromStorage();
    // Observe initialization errors without silently replacing damaged data.
    _ready.catchError((Object error, StackTrace stack) {
      lastPersistenceError = error;
      debugPrint('Failed to load dishes: $error');
    });
  }

  Future<void> _initFromStorage() async {
    final storage = _storage;
    if (storage == null) return;
    final data = await storage.loadAll();
    if (!mounted) return;
    _savedDishesNotifier?.setInitialDishes(data.savedDishes, data.activeDraft);
    if (!_editedBeforeLoad &&
        data.activeDraft != null &&
        state.ingredients.isEmpty &&
        state.title.isEmpty) {
      state = data.activeDraft!;
    }
  }

  void _persist() {
    _editedBeforeLoad = true;
    final snapshot = state;
    _saveQueue = _saveQueue.then((_) async {
      await _ready;
      if (_savedDishesNotifier != null) {
        await _savedDishesNotifier.updateDraftReference(snapshot);
      } else {
        await _storage?.saveAll(activeDraft: snapshot, savedDishes: const []);
      }
      lastPersistenceError = null;
    }).catchError((Object error, StackTrace stack) {
      lastPersistenceError = error;
      debugPrint('Failed to persist dishes: $error');
    });
  }

  void setTitle(String title) {
    state = state.copyWith(
      title: title,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void toggleShowTitle(bool show) {
    state = state.copyWith(
      showTitleInExport: show,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void toggleShowPer100gRow(bool show) {
    state = state.copyWith(
      showPer100gRowInExport: show,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void setCustomYield(double? yieldGrams) {
    if (yieldGrams != null && (!yieldGrams.isFinite || yieldGrams < 0.1))
      return;
    final shouldClear = yieldGrams == null;
    state = state.copyWith(
      customYieldGrams: shouldClear ? null : yieldGrams,
      clearCustomYield: shouldClear,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void setRetention({double? protein, double? fat, double? carbs}) {
    state = state.copyWith(
      retentionProtein: protein ?? state.retentionProtein,
      retentionFat: fat ?? state.retentionFat,
      retentionCarbs: carbs ?? state.retentionCarbs,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void setBlankMode(BlankMode mode) {
    state = state.copyWith(
      blankMode: mode,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void addIngredient(Product product, double grams, {bool isGross = false}) {
    final newIngredient = Ingredient(
      id: '${product.id}_${DateTime.now().microsecondsSinceEpoch}',
      product: product,
      weightGrams: grams,
      isGross: isGross,
    );

    state = state.copyWith(
      ingredients: [...state.ingredients, newIngredient],
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void updateIngredient(String id, double grams, {bool? isGross}) {
    final updatedList = state.ingredients.map((ing) {
      if (ing.id == id) {
        return ing.copyWith(
          weightGrams: grams,
          isGross: isGross ?? ing.isGross,
        );
      }
      return ing;
    }).toList();

    state = state.copyWith(
      ingredients: updatedList,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void removeIngredient(String id) {
    final updatedList = state.ingredients.where((ing) => ing.id != id).toList();
    state = state.copyWith(
      ingredients: updatedList,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void restoreIngredient(Ingredient ingredient, int index) {
    if (state.ingredients.any((item) => item.id == ingredient.id)) return;
    final items = List<Ingredient>.from(state.ingredients);
    items.insert(index.clamp(0, items.length), ingredient);
    state = state.copyWith(ingredients: items, updatedAt: DateTime.now());
    _persist();
  }

  void reorderIngredients(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final list = List<Ingredient>.from(state.ingredients);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    state = state.copyWith(
      ingredients: list,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void saveCurrentToLibrary() {
    final snapshot = state;
    _saveQueue = _saveQueue.then((_) async {
      await _ready;
      _savedDishesNotifier?.saveDish(snapshot);
    }).catchError((Object error, StackTrace stack) {
      lastPersistenceError = error;
      debugPrint('Failed to save current dish: $error');
    });
  }

  void loadDish(Dish dish) {
    state = dish;
    _persist();
  }

  void createNewDish() {
    state = Dish(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      blankMode: state.blankMode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void clearAll() {
    createNewDish();
  }
}
