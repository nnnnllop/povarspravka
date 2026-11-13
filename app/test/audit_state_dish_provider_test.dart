// STATE-04 (isDirty), STATE-09 (lost ingredient on double-tap),
// STATE-10 (undo/redo) — pure `DishNotifier` logic.
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_state_support.dart';

Product prod(String name, {double p = 1.5, double f = .1, double c = 8.8}) =>
    Product(
        id: name.hashCode,
        code: name,
        name: name,
        groupId: 1,
        source: 'skurikhin',
        protein: p,
        fat: f,
        carbs: c,
        kcal: 42);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-04 isDirty tracks the CONTENT signature', () {
    late DishNotifier n;
    setUp(() {
      n = DishNotifier(storage: CountingStorage());
    });
    tearDown(() => n.dispose());

    test('(a) change then revert -> isDirty false', () {
      n.markClean();
      expect(n.isDirty, isFalse);
      n.setTitle('Борщ');
      expect(n.isDirty, isTrue);
      n.setTitle('');
      expect(n.isDirty, isFalse,
          reason: 'updatedAt is excluded from _contentSignature');
    });

    test('(b) reorder ingredients -> isDirty TRUE', () {
      n.addIngredient(prod('Картофель'), 100);
      n.addIngredient(prod('Морковь'), 50);
      n.markClean();
      expect(n.isDirty, isFalse);
      n.reorderIngredients(0, 2);
      expect(n.state.ingredients.map((i) => i.product.name),
          ['Морковь', 'Картофель']);
      expect(n.isDirty, isTrue,
          reason: 'list order is part of the blank / export');
    });

    test('(c) customYieldGrams null -> set -> null', () {
      n.addIngredient(prod('Картофель'), 200);
      n.markClean();
      n.setCustomYield(180);
      expect(n.isDirty, isTrue);
      n.setCustomYield(null);
      expect(n.state.customYieldGrams, isNull);
      expect(n.isDirty, isFalse);
    });

    test('(d) draft loaded from disk -> isDirty false', () async {
      final diskDraft = Dish(
        id: 'disk',
        title: 'Черновик с диска',
        ingredients: [
          Ingredient(id: 'i1', product: prod('Свекла'), weightGrams: 300)
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      final storage = GatedStorage(
          initial: DishStorageData(activeDraft: diskDraft, savedDishes: const []));
      final local = DishNotifier(storage: storage);
      addTearDown(local.dispose);
      await local.flushPendingSaves();
      expect(local.state.title, 'Черновик с диска');
      expect(local.isDirty, isFalse, reason: '_lastCleanSnapshot set on load');
    });

    test('(e) createNewDish -> isDirty false', () {
      n.addIngredient(prod('Картофель'), 100);
      n.setTitle('Старое');
      expect(n.isDirty, isTrue);
      n.createNewDish();
      expect(n.state.ingredients, isEmpty);
      expect(n.state.title, '');
      expect(n.isDirty, isFalse);
    });

    test('(f) updateIngredient with the SAME grams does not dirty the draft',
        () {
      n.addIngredient(prod('Картофель'), 100);
      n.markClean();
      final id = n.state.ingredients.single.id;
      final before = n.state.updatedAt;
      n.updateIngredient(id, 100);
      expect(n.state.updatedAt.isAfter(before) || n.state.updatedAt != before,
          isTrue,
          reason: 'updatedAt DOES change — it is only excluded from the sig');
      expect(n.isDirty, isFalse);
    });

    test('(f2) retyping the same title does not dirty the draft', () {
      n.setTitle('Борщ');
      n.markClean();
      n.setTitle('Борщ');
      expect(n.isDirty, isFalse);
    });

    test('(g) changing retention / blank mode / export toggles dirties', () {
      n.addIngredient(prod('Картофель'), 100);
      n.markClean();
      n.setRetention(protein: .5);
      expect(n.isDirty, isTrue);
      n.setRetention(protein: .94);
      expect(n.isDirty, isFalse);
      n.toggleShowTitle(true);
      expect(n.isDirty, isTrue);
      n.toggleShowTitle(false);
      expect(n.isDirty, isFalse);
      n.toggleShowPer100gRow(true);
      expect(n.isDirty, isTrue);
      n.toggleShowPer100gRow(false);
      expect(n.isDirty, isFalse);
    });

    test('(h) isDirty ignores the dish id (loadDishAsCopy keeps layout)', () {
      n.addIngredient(prod('Картофель'), 100);
      n.markClean();
      final copy = n.state.copyWith(id: 'another-id');
      n.loadDishAsCopy(copy);
      expect(n.state.id, isNot('another-id'));
      expect(n.isDirty, isFalse);
    });

    test('a failing draft autosave IS reported by flushPendingSaves(), but '
        'isDirty has already been cleared', () async {
      final failing = DishNotifier(storage: _ThrowingStorage());
      addTearDown(() {
        try {
          failing.dispose();
        } catch (_) {}
      });
      failing.addIngredient(prod('Картофель'), 100);
      Object? flushThrew;
      var flushReturnedNormally = false;
      try {
        await failing.flushPendingSaves();
        flushReturnedNormally = true;
      } catch (e) {
        flushThrew = e;
      }
      // ignore: avoid_print
      print('STATE-04/STATE-07: lastPersistenceError='
          '${failing.lastPersistenceError}; flush threw='
          '${flushThrew ?? '(nothing)'}; normal=$flushReturnedNormally; '
          'isDirty=${failing.isDirty}');
      expect(failing.lastPersistenceError, isNotNull,
          reason: 'the error IS recorded on the notifier');
      expect(flushThrew, isA<Exception>(),
          reason: 'dish_provider.dart:160 does rethrow — but only for the few '
              'callers that await it');
      expect(flushReturnedNormally, isFalse);
      expect(failing.isDirty, isFalse,
          reason: 'OBSERVED DEFECT STATE-04b: nothing was written, yet '
              'isDirty is false, so the «несохранённые изменения» indicator is '
              'already gone while the data on disk is stale');
      // `_persist()` ends with `.catchError` (line 209) and NO UI reads
      // `lastPersistenceError`; nothing in `lib/` calls `flushPendingSaves()`
      // on the autosave path, so the user is never told the draft stopped
      // being saved.
    });

    test('DEFECT: saveCurrentToLibrary() also swallows the write failure of '
        'the underlying draft storage', () async {
      final failing = DishNotifier(storage: _ThrowingStorage());
      addTearDown(() {
        try {
          failing.dispose();
        } catch (_) {}
      });
      failing.addIngredient(prod('Картофель'), 100);
      Object? thrown;
      try {
        await failing.saveCurrentToLibrary();
      } catch (e) {
        thrown = e;
      }
      // ignore: avoid_print
      print('STATE-04c: saveCurrentToLibrary threw='
          '${thrown ?? '(nothing)'}; isDirty=${failing.isDirty}; '
          'lastPersistenceError=${failing.lastPersistenceError}');
      expect(thrown, isNull,
          reason: 'OBSERVED: `_saveQueue = ... .catchError(...)` before '
              '`flushPendingSaves()` means the caller of an EXPLICIT save also '
              'gets a normal Future and `isDirty` flips to false');
      expect(failing.isDirty, isFalse);
    });
  });

  group('STATE-09 double-tap "Добавить в блюдо"', () {
    test('two synchronous addIngredient calls keep BOTH ingredients with '
        'distinct ids', () {
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      n.addIngredient(prod('Картофель'), 250, isGross: true);
      n.addIngredient(prod('Картофель'), 250, isGross: true);
      final ids = n.state.ingredients.map((i) => i.id).toList();
      // ignore: avoid_print
      print('STATE-09: ids=$ids total=${n.state.totalRawNetGrams} g');
      expect(ids.length, 2);
      expect(ids.toSet().length, 2, reason: 'ids must differ');
      expect(n.state.ingredients.map((i) => i.weightGrams), [250, 250]);
    });

    test('the state replaced by _persist() snapshots both ingredients '
        '(no lost update in the draft queue)', () async {
      final storage = CountingStorage();
      final n = DishNotifier(storage: storage);
      addTearDown(n.dispose);
      // Two taps in the same frame, exactly like two onTap callbacks.
      for (var i = 0; i < 2; i++) {
        n.addIngredient(prod('Морковь'), 100);
      }
      await n.flushPendingSaves();
      expect(storage.lastDraft!.ingredients.length, 2);
    });

    test('50 rapid adds all survive in state and in the persisted draft', () async {
      final storage = CountingStorage();
      final n = DishNotifier(storage: storage);
      addTearDown(n.dispose);
      for (var i = 0; i < 50; i++) {
        n.addIngredient(prod('Продукт $i'), 10.0 + i);
      }
      await n.flushPendingSaves();
      expect(n.state.ingredients.length, 50);
      expect(storage.lastDraft!.ingredients.length, 50);
      expect(storage.lastDraft!.ingredients.map((i) => i.id).toSet().length, 50);
    });
  });

  group('STATE-10 undo / redo', () {
    test('there is NO undo/redo history stack in the codebase', () {
      // Verified by grepping lib/ for Undo/Redo/history/_history — the only
      // hit is a comment in dish_provider.dart:129. The provider exposes no
      // `undo()`/`redo()`/`canUndo` API at all.
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      n.addIngredient(prod('Картофель'), 100);
      n.setTitle('A');
      n.setTitle('B');
      // Nothing to go back to:
      expect(n.state.title, 'B');
      // The only "undo" is restoreIngredient (SnackBar «Отменить»).
    });

    test('restoreIngredient puts the item back at the SAME index', () {
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      for (final name in ['A', 'B', 'C']) {
        n.addIngredient(prod(name), 100);
      }
      final removed = n.state.ingredients[1];
      n.removeIngredient(removed.id);
      n.restoreIngredient(removed, 1);
      expect(n.state.ingredients.map((i) => i.product.name), ['A', 'B', 'C']);
      expect(n.state.ingredients[1].id, removed.id);
    });

    test('rapid delete + restore does not duplicate ids (restore is idempotent)',
        () {
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      for (final name in ['A', 'B', 'C']) {
        n.addIngredient(prod(name), 100);
      }
      final removed = n.state.ingredients[1];
      n.removeIngredient(removed.id);
      n.restoreIngredient(removed, 1);
      n.restoreIngredient(removed, 1); // second tap on «Отменить»
      n.restoreIngredient(removed, 0);
      final ids = n.state.ingredients.map((i) => i.id).toList();
      expect(ids.length, 3);
      expect(ids.toSet().length, 3, reason: 'no duplicate ingredient ids');
      expect(n.state.ingredients.map((i) => i.product.name), ['A', 'B', 'C']);
    });

    test('restore at an out-of-range index clamps instead of throwing', () {
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      n.addIngredient(prod('A'), 100);
      final removed = n.state.ingredients.single;
      n.removeIngredient(removed.id);
      n.restoreIngredient(removed, 99);
      expect(n.state.ingredients.single.id, removed.id);
      n.removeIngredient(removed.id);
      n.restoreIngredient(removed, -5);
      expect(n.state.ingredients.single.id, removed.id);
    });

    test('DEFECT: restore after the dish was replaced puts the ingredient '
        'into a DIFFERENT dish (no dishId guard in the notifier)', () {
      final n = DishNotifier(storage: CountingStorage());
      addTearDown(n.dispose);
      n.addIngredient(prod('Картофель'), 100);
      final firstDishId = n.state.id;
      final removed = n.state.ingredients.single;
      n.removeIngredient(removed.id); // SnackBar «Отменить» is showing
      n.createNewDish(); // user pressed «Новый расчёт»
      expect(n.state.id, isNot(firstDishId));
      n.restoreIngredient(removed, 0); // SnackBar action still tappable
      // ignore: avoid_print
      print('STATE-10: deleted from dish $firstDishId, restored into '
          '${n.state.id}: ${n.state.ingredients.length} ingredient(s)');
      expect(n.state.ingredients.single.product.name, 'Картофель',
          reason: 'restoreIngredient has no dish-id guard of its own');
      // The SCREEN guards this (recipe_editor_screen.dart:326), so the user
      // path is safe — but the notifier API is not, and any other caller
      // would corrupt the new draft.
    });
  });
}

class _ThrowingStorage extends CountingStorage {
  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    throw Exception('disk full');
  }
}
