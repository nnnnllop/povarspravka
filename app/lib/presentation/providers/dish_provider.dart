import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_validation.dart';
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

final _random = Random.secure();
String _newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // RFC 4122 version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

Dish _snapshot(Dish dish) => Dish.fromJson(dish.toJson());

class SavedDishesNotifier extends StateNotifier<List<Dish>> {
  final DishStorageRepository _storage;
  Dish? _latestDraft;
  Future<void> _operationTail = Future<void>.value();

  // Serialize read-modify-write, not merely the final disk writes.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  SavedDishesNotifier(this._storage) : super(const []);

  void setInitialDishes(List<Dish> dishes, Dish? draft) {
    _latestDraft = draft;
    state = dishes;
  }

  Future<void> updateDraftReference(Dish draft) => _serialized(() async {
        await _storage.saveAll(activeDraft: draft, savedDishes: state);
        _latestDraft = draft;
      });

  Future<void> saveDish(Dish dish) => _serialized(() async {
        dish = _snapshot(dish);
        final existingIdx = state.indexWhere((d) => d.id == dish.id);
        final updated = List<Dish>.from(state);
        if (existingIdx >= 0) {
          updated[existingIdx] = dish;
        } else {
          updated.insert(0, dish);
        }
        await _storage.saveAll(activeDraft: _latestDraft, savedDishes: updated);
        state = updated;
      });

  Future<void> deleteDish(String id) => _serialized(() async {
        final updated = state.where((d) => d.id != id).toList();
        await _storage.saveAll(activeDraft: _latestDraft, savedDishes: updated);
        state = updated;
      });

  Future<Dish> duplicateDish(Dish dish) => _serialized(() async {
        final now = DateTime.now();
        final copyTitle = dish.title.trim().isEmpty
            ? 'Блюдо (копия)'
            : '${dish.title} (копия)';
        final duplicated = dish.copyWith(
          id: _newId(),
          ingredients: dish.ingredients
              .map((i) => i.copyWith(
                  id: _newId(), product: Product.fromJson(i.product.toJson())))
              .toList(),
          title: copyTitle,
          createdAt: now,
          updatedAt: now,
        );
        final updated = [duplicated, ...state];
        await _storage.saveAll(activeDraft: _latestDraft, savedDishes: updated);
        state = updated;
        return duplicated;
      });
}

class DishNotifier extends StateNotifier<Dish> {
  final DishStorageRepository? _storage;
  final SavedDishesNotifier? _savedDishesNotifier;
  late final Future<void> _ready;
  Future<void> _saveQueue = Future<void>.value();
  bool _editedBeforeLoad = false;
  Object? lastPersistenceError;

  Future<void> flushPendingSaves() async {
    await _ready;
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
            id: _newId(),
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
    if (yieldGrams != null &&
        !CalculationValidation.inRange(yieldGrams, .1, 9999999)) return;
    final shouldClear = yieldGrams == null;
    state = state.copyWith(
      customYieldGrams: shouldClear ? null : yieldGrams,
      clearCustomYield: shouldClear,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void setRetention({double? protein, double? fat, double? carbs}) {
    for (final value in [protein, fat, carbs]) {
      if (value != null && !CalculationValidation.inRange(value, 0, 1)) return;
    }
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
    if (!CalculationValidation.inRange(grams, .1, 9999999)) return;
    CalculationValidation.product(product);
    final newIngredient = Ingredient(
      id: _newId(),
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
    if (!CalculationValidation.inRange(grams, .1, 9999999)) return;
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
    CalculationValidation.product(ingredient.product);
    CalculationValidation.range(
        ingredient.weightGrams, 0, 9999999, 'weightGrams');
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

  Future<void> saveCurrentToLibrary() {
    final snapshot = state;
    _saveQueue = _saveQueue.then((_) async {
      await _ready;
      await _savedDishesNotifier?.saveDish(snapshot);
      lastPersistenceError = null;
    }).catchError((Object error, StackTrace stack) {
      lastPersistenceError = error;
      debugPrint('Failed to save current dish: $error');
    });
    return flushPendingSaves();
  }

  void loadDish(Dish dish) {
    CalculationValidation.dish(dish);
    state = _snapshot(dish);
    _persist();
  }

  void createNewDish() {
    state = Dish(
      id: _newId(),
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
