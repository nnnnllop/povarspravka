import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/loss_group.dart';
import '../../core/calculation/models/product.dart';
import '../../data/repositories/dish_storage_repository.dart';

final dishStorageRepositoryProvider = Provider<DishStorageRepository>((ref) {
  return DishStorageRepository();
});

final savedDishesErrorProvider = StateProvider<Object?>((ref) => null);

final savedDishesProvider =
    StateNotifierProvider<SavedDishesNotifier, List<Dish>>((ref) {
  final storage = ref.watch(dishStorageRepositoryProvider);
  return SavedDishesNotifier(
    storage,
    onError: (error) =>
        ref.read(savedDishesErrorProvider.notifier).state = error,
  );
});

/// Путь каталога хранения данных для экрана «Как считается» (IO-07).
final storageDirectoryPathProvider = FutureProvider<String?>((ref) {
  return ref.read(dishStorageRepositoryProvider).resolveStorageDirectoryPath();
});

/// Уведомление «данные восстановлены из резервной копии» после загрузки
/// хранилища (`null` — восстанавливать не пришлось или повар его закрыл).
/// Главный экран показывает его баннером с кнопкой «Понятно».
final storageRecoveryNoticeProvider = StateProvider<String?>((ref) => null);

/// Уведомление совместимости при чтении файла от более новой версии формата.
final storageCompatibilityNoticeProvider = StateProvider<String?>((ref) => null);

final dishProvider = StateNotifierProvider<DishNotifier, Dish>((ref) {
  final storage = ref.watch(dishStorageRepositoryProvider);
  final savedNotifier = ref.read(savedDishesProvider.notifier);
  return DishNotifier(
    storage: storage,
    savedDishesNotifier: savedNotifier,
    onRecoveryNotice: (notice) =>
        ref.read(storageRecoveryNoticeProvider.notifier).state = notice,
    onCompatibilityNotice: (notice) =>
        ref.read(storageCompatibilityNoticeProvider.notifier).state = notice,
  );
});

/// Результат расчёта активного блюда — либо `null`, если данные невычислимы.
///
/// STATE-01: раньше провайдер бросал `ArgumentError` прямо в `build()`
/// экрана, и Flutter рисовал красную страницу — одно неисправное блюдо в
/// библиотеке делало недоступным всё приложение. Теперь ошибка данных —
/// это `null`, а экран показывает баннер [CalcErrorBanner].
///
/// RA-22: `null` — только для ошибок данных ([CalculationEngine.isDataError]).
/// Ошибка программы (`TypeError`, `StackOverflowError`, …) не выдаётся за
/// «ошибку данных блюда» и остаётся видной для диагностики.
final calculationResultProvider = Provider<CalculationResult?>((ref) {
  final dish = ref.watch(dishProvider);
  try {
    return CalculationEngine.calculate(dish);
  } catch (e) {
    if (CalculationEngine.isDataError(e)) return null;
    rethrow;
  }
});

/// Человеческое объяснение, почему блюдо не удалось посчитать (null — если
/// всё в порядке).
/// Ошибка сохранения на диск (null — сохранение успешно или ошибок нет).
final persistenceErrorProvider = Provider<Object?>((ref) {
  ref.watch(dishProvider);
  return ref.read(dishProvider.notifier).lastPersistenceError;
});

final calculationErrorProvider = Provider<String?>((ref) {
  final dish = ref.watch(dishProvider);
  try {
    CalculationEngine.calculate(dish);
    return null;
  } on ArgumentError catch (e) {
    return e.message.toString();
  } catch (e) {
    // RA-22: прочие ошибки данных — общее сообщение; ошибка программы — дальше.
    if (CalculationEngine.isDataError(e)) return 'Ошибка данных блюда';
    rethrow;
  }
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
  final void Function(Object? error)? _onError;
  Dish? _latestDraft;
  Future<void> _operationTail = Future<void>.value();
  Object? lastError;
  Future<void> Function()? _lastFailedOperation;

  // Serialize read-modify-write, not merely the final disk writes.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<T> _tracked<T>(
    Future<T> Function() operation, {
    bool trackRetry = false,
  }) async {
    Future<T> attempt() async {
      try {
        final value = await _serialized(operation);
        lastError = null;
        if (trackRetry) _lastFailedOperation = null;
        if (mounted) _onError?.call(null);
        return value;
      } catch (error) {
        lastError = error;
        if (trackRetry) {
          _lastFailedOperation = () async {
            await attempt();
          };
        }
        if (mounted) _onError?.call(error);
        rethrow;
      }
    }

    return attempt();
  }

  void clearError() {
    lastError = null;
    _lastFailedOperation = null;
    if (mounted) _onError?.call(null);
  }

  Future<bool> retryLastOperation() async {
    final op = _lastFailedOperation;
    if (op == null) return lastError == null;
    try {
      await op();
      return true;
    } catch (_) {
      return false;
    }
  }

  SavedDishesNotifier(
    this._storage, {
    void Function(Object? error)? onError,
  })  : _onError = onError,
        super(const []);

  void setInitialDishes(List<Dish> dishes, Dish? draft) {
    _latestDraft = draft;
    state = dishes;
  }

  Future<void> updateDraftReference(Dish draft) => _tracked(() async {
        await _storage.saveAll(activeDraft: draft, savedDishes: state);
        _latestDraft = draft;
      });

  /// Сохранить блюдо в библиотеку.
  ///
  /// Семантика — **last-write-wins**: `saveAll` полностью заменяет коллекцию.
  /// Автоматическое слияние с диском здесь недопустимо: удалённое блюдо
  /// «воскресало» бы из файла при каждом следующем сохранении, то есть
  /// удаление стало бы невозможным.
  Future<void> saveDish(Dish dish) => _tracked(() async {
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
      }, trackRetry: true);

  Future<void> deleteDish(String id) => _tracked(() async {
        final updated = state.where((d) => d.id != id).toList();
        await _storage.saveAll(activeDraft: _latestDraft, savedDishes: updated);
        state = updated;
      }, trackRetry: true);

  Future<Dish> duplicateDish(Dish dish) => _tracked(() async {
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
      }, trackRetry: true);
}

class DishNotifier extends StateNotifier<Dish> {
  final DishStorageRepository? _storage;
  final SavedDishesNotifier? _savedDishesNotifier;
  late final Future<void> _ready;
  Future<void> _saveQueue = Future<void>.value();
  bool _editedBeforeLoad = false;
  Object? lastPersistenceError;

  /// Снимок последнего сохранённого / загруженного состояния — база для
  /// [isDirty]. Обновляется при `saveCurrentToLibrary`, `loadDish`,
  /// `createNewDish` и при восстановлении черновика с диска.
  Dish? _lastCleanSnapshot;

  /// Есть ли несохранённые правки относительно последнего сохранения.
  ///
  /// Сравнение идёт по сериализации без `updatedAt` (это метка времени
  /// каждого автодействия, она меняется и при отмене правки обратно) и без
  /// `id` (после «Открыть как копию» это уже другое блюдо, но раскладка та
  /// же).
  bool get isDirty {
    if (_savedDishesNotifier != null && lastPersistenceError != null) {
      return true;
    }
    final clean = _lastCleanSnapshot;
    if (clean == null) {
      return state.ingredients.isNotEmpty || state.title.isNotEmpty;
    }
    return _contentSignature(clean) != _contentSignature(state);
  }

  String _contentSignature(Dish dish) => jsonEncode(<String, Object?>{
        'title': dish.title,
        'ingredients': dish.ingredients.map((i) => i.toJson()).toList(),
        'customYieldGrams': dish.customYieldGrams,
        'process': dish.process.name,
        'retention': [
          dish.retentionProtein,
          dish.retentionFat,
          dish.retentionCarbs,
        ],
        'blankMode': dish.blankMode.name,
        'showTitle': dish.showTitleInExport,
        'showPer100g': dish.showPer100gRowInExport,
      });

  /// Отметить текущее состояние как сохранённое (сбрасывает [isDirty]).
  void markClean() => _lastCleanSnapshot = _snapshot(state);

  Future<void> flushPendingSaves() async {
    await _ready;
    await _saveQueue;
    if (lastPersistenceError != null) throw lastPersistenceError!;
  }

  /// Уведомление о восстановлении из резервной копии при загрузке
  /// (см. [DishStorageRepository.recoveryNotice]); `null` — всё прочитано чисто.
  String? storageRecoveryNotice;
  String? storageCompatibilityNotice;
  final void Function(String notice)? _onRecoveryNotice;
  final void Function(String notice)? _onCompatibilityNotice;
  bool _initCompleted = false;
  bool _pendingLibraryRetry = false;

  DishNotifier({
    DishStorageRepository? storage,
    SavedDishesNotifier? savedDishesNotifier,
    void Function(String notice)? onRecoveryNotice,
    void Function(String notice)? onCompatibilityNotice,
  })  : _storage = storage,
        _savedDishesNotifier = savedDishesNotifier,
        _onRecoveryNotice = onRecoveryNotice,
        _onCompatibilityNotice = onCompatibilityNotice,
        // Новое блюдо — без тепловой обработки (задача 2026-11-03), как и
        // [createNewDish]. Черновик с диска заменяет это состояние со своим
        // способом (старый документ остаётся legacy).
        super(
          Dish.withProcess(
            id: _newId(),
            process: HeatProcess.cold,
          ),
        ) {
    _ready = _runInit();
  }

  Future<void> _runInit() async {
    try {
      await _initFromStorage();
      _initCompleted = true;
    } catch (error) {
      // Observe initialization errors without silently replacing damaged data.
      lastPersistenceError = error;
      debugPrint('Failed to load dishes: $error');
      if (mounted) state = state.copyWith();
    }
  }

  Future<void> _initFromStorage() async {
    final storage = _storage;
    if (storage == null) return;
    final data = await storage.loadAll();
    final notice = storage.recoveryNotice;
    final compatNotice = storage.consumeCompatibilityNotice();
    if (!mounted) return;
    if (notice != null) {
      storageRecoveryNotice = notice;
      _onRecoveryNotice?.call(notice);
    }
    if (compatNotice != null) {
      storageCompatibilityNotice = compatNotice;
      _onCompatibilityNotice?.call(compatNotice);
    }
    _savedDishesNotifier?.setInitialDishes(data.savedDishes, data.activeDraft);
    if (!_editedBeforeLoad &&
        data.activeDraft != null &&
        state.ingredients.isEmpty &&
        state.title.isEmpty) {
      state = data.activeDraft!;
    }
    if (!_editedBeforeLoad) {
      _lastCleanSnapshot = _snapshot(state);
    } else if (_savedDishesNotifier == null) {
      _lastCleanSnapshot = _snapshot(state);
    } else {
      if (data.activeDraft != null) {
        _lastCleanSnapshot = _snapshot(data.activeDraft!);
      }
    }
  }

  void _persist() {
    _editedBeforeLoad = true;
    final snapshot = state;
    _saveQueue = _saveQueue.then((_) async {
      await _ready;
      if (_storage != null && !_initCompleted) {
        throw lastPersistenceError ??
            StateError('Storage initialization failed');
      }
      if (_savedDishesNotifier != null) {
        await _savedDishesNotifier.updateDraftReference(snapshot);
      } else {
        await _storage?.saveAll(activeDraft: snapshot, savedDishes: const []);
      }
      final hadError = lastPersistenceError != null;
      lastPersistenceError = null;
      if (_editedBeforeLoad && _savedDishesNotifier != null) {
        _lastCleanSnapshot = _snapshot(snapshot);
      }
      if (hadError && mounted) {
        state = state.copyWith();
      }
    }).catchError((Object error, StackTrace stack) {
      lastPersistenceError = error;
      debugPrint('Failed to persist dishes: $error');
      if (mounted) {
        state = state.copyWith();
      }
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

  /// Устанавливает ручной выход готового блюда.
  ///
  /// Минимальный выход — [CalculationValidation.minCustomYieldGrams]
  /// (MATH-05: 0,1 г давал десятки миллионов ккал/100 г). Отвергнутое
  /// значение не меняет состояние; экран показывает ошибку через
  /// [yieldRejectedReason], а не молчит (FUZZ-10).
  void setCustomYield(double? yieldGrams) {
    if (yieldGrams != null &&
        !CalculationValidation.inRange(yieldGrams,
            CalculationValidation.minCustomYieldGrams,
            CalculationValidation.maxCustomYieldGrams)) {
      return;
    }
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
      if (value != null &&
          !CalculationValidation.inRange(value,
              CalculationValidation.minRetention,
              CalculationValidation.maxRetention)) {
        return;
      }
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

  /// Выбрать способ тепловой обработки блюда.
  ///
  /// Способ задаёт ТОЛЬКО потери Б/Ж/У по таблице (`LossTable`) для группы
  /// каждого ингредиента; вес готового блюда он не меняет. Тройка
  /// сохранности действует только в [HeatProcess.legacy]: при выборе legacy
  /// она получает прежние значения 0,94 / 0,88 / 0,91, при выборе другого
  /// способа не трогается (и не участвует в расчёте).
  void setHeatProcess(HeatProcess process) {
    state = process.isLegacy
        ? state.copyWith(
            process: HeatProcess.legacy,
            retentionProtein: kLegacyRetentionProtein,
            retentionFat: kLegacyRetentionFat,
            retentionCarbs: kLegacyRetentionCarbs,
            updatedAt: DateTime.now(),
          )
        : state.copyWith(
            process: process,
            updatedAt: DateTime.now(),
          );
    _persist();
  }

  /// Группа таблицы потерь для ингредиента [id], выбранная поваром.
  ///
  /// `null` — вернуть группу классификатора. Нет такого ингредиента —
  /// состояние не меняется.
  void setIngredientGroup(String id, LossGroup? group) {
    if (!state.ingredients.any((ing) => ing.id == id)) return;
    state = state.copyWith(
      ingredients: [
        for (final ing in state.ingredients)
          ing.id == id
              ? ing.copyWith(
                  groupOverride: group, clearGroupOverride: group == null)
              : ing,
      ],
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  /// Способ обработки именно ингредиента [id] (например, лук обжарен
  /// для супа). `null` — способ блюда. [HeatProcess.legacy] отклоняется:
  /// старый расчёт — свойство всего блюда.
  void setIngredientProcess(String id, HeatProcess? process) {
    if (process != null && process.isLegacy) return;
    if (!state.ingredients.any((ing) => ing.id == id)) return;
    state = state.copyWith(
      ingredients: [
        for (final ing in state.ingredients)
          ing.id == id
              ? ing.copyWith(
                  processOverride: process,
                  clearProcessOverride: process == null)
              : ing,
      ],
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  void addIngredient(Product product, double grams, {bool isGross = false}) {
    if (!CalculationValidation.inRange(grams, .1, 9999999)) return;
    // FUZZ-01: продукт с NaN/∞ в нутриентах не должен попадать в блюдо.
    // Отказ тихий (как и для массы) — это пользовательский путь, бросать
    // исключение из обработчика нажатия нельзя.
    if (!CalculationValidation.isValidProduct(product)) return;
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

  void updateIngredient(String id, double grams, {bool? isGross, Product? product}) {
    if (!CalculationValidation.inRange(grams, .1, 9999999)) return;
    final updatedList = state.ingredients.map((ing) {
      if (ing.id == id) {
        // Другой продукт — ручная группа прежнего к нему не относится
        // (иначе «молоко» молча считалось бы как «мясо»).
        final productChanged = product != null &&
            (product.id != ing.product.id || product.name != ing.product.name);
        return ing.copyWith(
          weightGrams: grams,
          isGross: isGross ?? ing.isGross,
          product: product ?? ing.product,
          clearGroupOverride: productChanged,
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

  /// Восстанавливает ранее удалённый ингредиент.
  ///
  /// STATE-10b: восстановление привязано к блюду. Если указан [dishId] и он
  /// не совпадает с текущим блюдом, ингредиент НЕ вставляется в чужой
  /// рецепт (иначе Undo в блюде A дописывал строку в блюдо B).
  void restoreIngredient(Ingredient ingredient, int index, {String? dishId}) {
    if (dishId != null && dishId != state.id) return;
    CalculationValidation.product(ingredient.product);
    CalculationValidation.range(
        ingredient.weightGrams, 0, 9999999, 'weightGrams');
    if (state.ingredients.any((item) => item.id == ingredient.id)) return;
    final items = List<Ingredient>.from(state.ingredients);
    items.insert(index.clamp(0, items.length), ingredient);
    state = state.copyWith(ingredients: items, updatedAt: DateTime.now());
    _persist();
  }

  /// Переставляет ингредиенты.
  ///
  /// FUZZ-09: раньше `removeAt(oldIndex)` на индексе вне диапазона ронял
  /// экран необработанным `RangeError`. Теперь некорректный запрос просто
  /// не меняет состояние — экран живёт, данные целы.
  void reorderIngredients(int oldIndex, int newIndex) {
    final length = state.ingredients.length;
    if (oldIndex < 0 || oldIndex >= length) return;
    // Flutter отдаёт newIndex в диапазоне 0..length (слот после удаления).
    if (newIndex < 0 || newIndex > length) return;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= length) return;
    final list = List<Ingredient>.from(state.ingredients);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    state = state.copyWith(
      ingredients: list,
      updatedAt: DateTime.now(),
    );
    _persist();
  }

  /// Сохранить текущее блюдо в библиотеку и пометить состояние чистым.
  Future<void> saveCurrentToLibrary() {
    final snapshot = state;
    if (_savedDishesNotifier != null) {
      _pendingLibraryRetry = true;
    }
    _saveQueue = _saveQueue.then((_) async {
      await _ready;
      if (_savedDishesNotifier != null) {
        if (_storage != null && !_initCompleted) {
          throw lastPersistenceError ??
              StateError('Storage initialization failed');
        }
        await _savedDishesNotifier.saveDish(snapshot);
        _pendingLibraryRetry = false;
      }
      _lastCleanSnapshot = _snapshot(snapshot);
      final hadError = lastPersistenceError != null;
      lastPersistenceError = null;
      if (_editedBeforeLoad && _savedDishesNotifier != null) {
        _lastCleanSnapshot = _snapshot(snapshot);
      }
      if (hadError && mounted) {
        state = state.copyWith();
      }
    }).catchError((Object error, StackTrace stack) {
      if (_savedDishesNotifier != null) {
        _pendingLibraryRetry = true;
      }
      lastPersistenceError = error;
      debugPrint('Failed to save current dish: $error');
      if (mounted) {
        state = state.copyWith();
      }
    });
    return flushPendingSaves();
  }

  /// Повторить неудавшуюся операцию чтения/записи на диск.
  Future<bool> retryPersistence() async {
    final snapshot = state;
    if (_storage != null && !_initCompleted) {
      try {
        await _initFromStorage();
        _initCompleted = true;
        if (!mounted) return false;
        if (!_editedBeforeLoad && !_pendingLibraryRetry) {
          lastPersistenceError = null;
          state = state.copyWith();
          return true;
        }
      } catch (error) {
        lastPersistenceError = error;
        debugPrint('Failed to retry loading dishes: $error');
        if (mounted) state = state.copyWith();
        return false;
      }
    }
    if (_pendingLibraryRetry && _savedDishesNotifier != null) {
      try {
        await _savedDishesNotifier.updateDraftReference(snapshot);
      } catch (error) {
        lastPersistenceError = error;
        debugPrint('Failed to retry draft persistence: $error');
        if (mounted) state = state.copyWith();
        return false;
      }
      try {
        await saveCurrentToLibrary();
        return lastPersistenceError == null;
      } catch (_) {
        return false;
      }
    }
    if (_editedBeforeLoad || lastPersistenceError != null) {
      _persist();
      try {
        await flushPendingSaves();
        return lastPersistenceError == null;
      } catch (_) {
        return false;
      }
    }
    return lastPersistenceError == null;
  }

  /// Безусловная замена состояния (поведение сохранено — его проверяют
  /// тесты). Экран редактора перед вызовом обязан спросить пользователя.
  ///
  /// STATE-01: открытие блюда — это ПОЛЬЗОВАТЕЛЬСКОЕ действие. Раньше
  /// `CalculationValidation.dish` бросал здесь, и одно повреждённое блюдо в
  /// библиотеке роняло домашний экран целиком. Теперь блюдо загружается как
  /// есть: расчёт вернёт `null`, а экран покажет `CalcErrorBanner`, из
  /// которого видно, что именно исправить.
  void loadDish(Dish dish) {
    _pendingLibraryRetry = false;
    state = _snapshot(dish);
    markClean();
    _persist();
  }

  /// Открыть рецептуру **как копию в черновик**: получает новый `id`, поэтому
  /// текущий черновик не перезаписывается и остаётся в истории черновиков.
  ///
  /// Вызывается только после явного выбора пользователя («Открыть как
  /// копию в черновик») — это и есть защита от тихого уничтожения работы
  /// (аудит P0-3).
  void loadDishAsCopy(Dish dish) {
    _pendingLibraryRetry = false;
    final now = DateTime.now();
    state = dish.copyWith(
      id: _newId(),
      ingredients: dish.ingredients
          .map((i) => i.copyWith(
                id: _newId(),
                product: Product.fromJson(i.product.toJson()),
              ))
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    markClean();
    _persist();
  }

  void createNewDish() {
    _pendingLibraryRetry = false;
    // Новое блюдо — `cold` (задача 2026-11-03): пока повар не выбрал
    // способ, потерь нет, а вес готового блюда не угадывается. Прежняя
    // глобальная тройка 0,94 / 0,88 / 0,91 на салат или морс занижала их
    // калорийность на 7–12 %.
    //
    // Повар переключает способ в диалоге «Параметры расчета и бланка»;
    // `legacy` остаётся доступным и воспроизводит поведение старых рецептур.
    state = Dish.withProcess(
      id: _newId(),
      process: HeatProcess.cold,
      blankMode: state.blankMode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    markClean();
    _persist();
  }

  void clearAll() {
    createNewDish();
  }
}
