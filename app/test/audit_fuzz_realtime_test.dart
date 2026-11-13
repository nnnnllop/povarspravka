// FUZZ-EDGE / PART 3 — real-time add / delete / undo / reorder / update through
// the Riverpod providers, backed by a temp-dir DishStorageRepository.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

Product prod(int id, {double protein = 10, double kcal = 300}) => Product(
      id: id,
      code: 'p$id',
      name: 'Продукт $id',
      groupId: 1,
      source: 'skurikhin',
      protein: protein,
      fat: 5,
      carbs: 20,
      kcal: kcal,
    );

Directory tmpDir() {
  final d = Directory.systemTemp.createTempSync('povar_fuzz_rt_');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

ProviderContainer containerFor(Directory dir) {
  final c = ProviderContainer(overrides: [
    dishStorageRepositoryProvider
        .overrideWithValue(DishStorageRepository(storageDirectory: dir)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> settle(ProviderContainer c) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await c.read(dishProvider.notifier).flushPendingSaves();
}

/// From-scratch calculation of an arbitrary ingredient list.
/// [process] — способ блюда; по умолчанию как у нового блюда (cold), а не
/// legacy-умолчание конструктора [Dish] (старые документы без ключа).
dynamic scratch(List<Ingredient> ings,
        {double? yieldGrams, HeatProcess process = HeatProcess.cold}) =>
    CalculationEngine.calculate(Dish(
      id: 'scratch',
      ingredients: ings,
      customYieldGrams: yieldGrams,
      process: process,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));

void expectSameNumbers(dynamic live, dynamic ref, String label) {
  expect(live.yieldGrams, ref.yieldGrams, reason: '$label yield');
  expect(live.rawTotalWeight, ref.rawTotalWeight, reason: '$label weight');
  expect(live.rawTotalProtein, ref.rawTotalProtein, reason: '$label protein');
  expect(live.rawTotalFat, ref.rawTotalFat, reason: '$label fat');
  expect(live.rawTotalCarbs, ref.rawTotalCarbs, reason: '$label carbs');
  expect(live.cookedProtein, ref.cookedProtein, reason: '$label cProtein');
  expect(live.cookedFat, ref.cookedFat, reason: '$label cFat');
  expect(live.cookedCarbs, ref.cookedCarbs, reason: '$label cCarbs');
  expect(live.cookedKcal, ref.cookedKcal, reason: '$label cKcal');
  expect(live.per100gProtein, ref.per100gProtein, reason: '$label p100 P');
  expect(live.per100gKcal, ref.per100gKcal, reason: '$label p100 kcal');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Новое блюдо (cold), табличные потери (boil) и старый расчёт (legacy):
  // живой итог всегда равен расчёту «с нуля» тем же способом.
  for (final process in [HeatProcess.cold, HeatProcess.boil, HeatProcess.legacy]) {
  test('add 3 -> delete middle -> restoreIngredient -> reorder -> update weight == from-scratch'
      ' [${process.name}]',
      () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.setHeatProcess(process);
    expect(c.read(dishProvider).process, process);

    n.addIngredient(prod(1, protein: 10), 100);
    n.addIngredient(prod(2, protein: 20), 250);
    n.addIngredient(prod(3, protein: 30), 33.3);
    await settle(c);

    expect(c.read(dishProvider).ingredients.length, 3);
    final live0 = c.read(calculationResultProvider);
    expectSameNumbers(live0,
        scratch(c.read(dishProvider).ingredients, process: process), 'after add');

    final middle = c.read(dishProvider).ingredients[1];
    n.removeIngredient(middle.id);
    await settle(c);
    expect(c.read(dishProvider).ingredients.map((i) => i.id),
        isNot(contains(middle.id)));
    expectSameNumbers(c.read(calculationResultProvider),
        scratch(c.read(dishProvider).ingredients, process: process),
        'after delete');

    n.restoreIngredient(middle, 1);
    await settle(c);
    final restored = c.read(dishProvider).ingredients;
    expect(restored.length, 3);
    expect(restored[1].id, middle.id);
    expectSameNumbers(c.read(calculationResultProvider),
        scratch(restored, process: process), 'after restore');
    expectSameNumbers(c.read(calculationResultProvider), live0,
        'restore is a true undo');

    n.reorderIngredients(0, 3); // ReorderableListView convention
    await settle(c);
    final reordered = c.read(dishProvider).ingredients;
    expect(reordered.map((i) => i.product.id).toList(), [2, 3, 1]);
    expectSameNumbers(c.read(calculationResultProvider),
        scratch(reordered, process: process), 'after reorder');

    n.updateIngredient(reordered.last.id, 512.7);
    await settle(c);
    final updated = c.read(dishProvider).ingredients;
    expect(updated.last.weightGrams, 512.7);
    expectSameNumbers(c.read(calculationResultProvider),
        scratch(updated, process: process), 'after update');
  });
  }

  test('double restoreIngredient of the same id is idempotent', () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    n.addIngredient(prod(2), 100);
    await settle(c);
    final row = c.read(dishProvider).ingredients.first;
    n.removeIngredient(row.id);
    await settle(c);
    n.restoreIngredient(row, 0);
    n.restoreIngredient(row, 0);
    await settle(c);
    expect(
        c.read(dishProvider).ingredients.where((i) => i.id == row.id).length, 1);
  });

  test('restoreIngredient clamps an out-of-range / negative index', () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    await settle(c);
    final row = c.read(dishProvider).ingredients.first;
    n.removeIngredient(row.id);
    await settle(c);
    expect(() => n.restoreIngredient(row, 999), returnsNormally);
    await settle(c);
    expect(c.read(dishProvider).ingredients.length, 1);
    expect(() => n.restoreIngredient(row.copyWith(id: 'other'), -50),
        returnsNormally);
  });

  test('[FUZZ-09] reorderIngredients with out-of-range oldIndex is a safe no-op',
      () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    await settle(c);
    // SPEC: an out-of-range index is a programming/UI error, not a reason to
    // crash a tap handler. The call is ignored and state survives untouched.
    expect(() => n.reorderIngredients(5, 0), returnsNormally);
    expect(() => n.reorderIngredients(-1, 0), returnsNormally);
    expect(() => n.reorderIngredients(0, 99), returnsNormally);
    expect(c.read(dishProvider).ingredients.length, 1);
  });

  test('updateIngredient with grams 0 / negative is ignored (silent no-op)', () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    await settle(c);
    final id = c.read(dishProvider).ingredients.first.id;
    n.updateIngredient(id, 0);
    n.updateIngredient(id, -5);
    await settle(c);
    expect(c.read(dishProvider).ingredients.first.weightGrams, 100.0);
  });

  test('addIngredient with a NaN-protein product is rejected before mutating',
      () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    await settle(c);
    // SPEC (FUZZ-01): rejection is silent — user paths never throw.
    expect(() => n.addIngredient(prod(2, protein: double.nan), 100),
        returnsNormally);
    expect(c.read(dishProvider).ingredients.length, 1);
  });

  test('[FUZZ-01/ui] addIngredient REJECTS a product with kcal=Infinity',
      () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1, kcal: double.infinity), 100);
    // SPEC: the notifier validates the product, so the poison never enters.
    expect(c.read(dishProvider).ingredients, isEmpty);
    // …and nothing is ever persisted.
    await n.flushPendingSaves();
  });

  test('rapid burst: 40 adds + 20 deletes -> live state and DISK agree', () async {
    final dir = tmpDir();
    final c = containerFor(dir);
    final n = c.read(dishProvider.notifier);
    await settle(c);
    for (var i = 0; i < 40; i++) {
      n.addIngredient(prod(i, protein: 5 + i % 7), 100.0 + i);
    }
    final ids = c.read(dishProvider).ingredients.map((i) => i.id).toList();
    for (var i = 0; i < ids.length; i += 2) {
      n.removeIngredient(ids[i]);
    }
    await settle(c);
    final live = c.read(dishProvider);
    expect(live.ingredients.length, 20);
    expectSameNumbers(c.read(calculationResultProvider), scratch(live.ingredients),
        'after burst');

    final reloaded = await DishStorageRepository(storageDirectory: dir).loadAll();
    final draft = reloaded.activeDraft!;
    expect(draft.ingredients.length, 20);
    expectSameNumbers(
        CalculationEngine.calculate(draft), c.read(calculationResultProvider),
        'disk vs live after burst');
  });

  test('12 adds + every-other delete survive a fresh repository reload', () async {
    final dir = tmpDir();
    final c = containerFor(dir);
    final n = c.read(dishProvider.notifier);
    await settle(c);
    for (var i = 0; i < 12; i++) {
      n.addIngredient(prod(i, protein: 5.0 + i), 100.0 + i * 0.3);
    }
    await settle(c);
    final ids = c.read(dishProvider).ingredients.map((i) => i.id).toList();
    for (var i = 0; i < ids.length; i += 2) {
      n.removeIngredient(ids[i]);
    }
    await settle(c);
    final liveNumbers = c.read(calculationResultProvider);

    final loaded = await DishStorageRepository(storageDirectory: dir).loadAll();
    final draft = loaded.activeDraft!;
    expect(draft.ingredients.length, 6);
    expectSameNumbers(CalculationEngine.calculate(draft), liveNumbers, 'disk vs live');
  });

  test('custom yield survives the mutation sequence and keeps stale state out', () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 1000);
    n.addIngredient(prod(2), 1000);
    n.setCustomYield(1500.0);
    await settle(c);
    expect(c.read(calculationResultProvider)!.yieldGrams, 1500.0);
    n.removeIngredient(c.read(dishProvider).ingredients.first.id);
    await settle(c);
    expect(c.read(calculationResultProvider)!.yieldGrams, 1500.0);
    expectSameNumbers(c.read(calculationResultProvider),
        scratch(c.read(dishProvider).ingredients, yieldGrams: 1500), 'yield kept');
  });

  test('[RISK FUZZ-10] setCustomYield silently IGNORES invalid values instead of clearing', () async {
    final c = containerFor(tmpDir());
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 1000);
    n.setCustomYield(500.0);
    await settle(c);
    n.setCustomYield(double.nan);
    n.setCustomYield(0.05);
    n.setCustomYield(-5.0);
    await settle(c);
    // Silent no-op: the PREVIOUS valid yield stays, nothing tells the user.
    expect(c.read(dishProvider).customYieldGrams, 500.0);
  });

  test('[FUZZ-01/storage] a product with NaN kcal never reaches the document',
      () async {
    final dir = tmpDir();
    final c = containerFor(dir);
    final n = c.read(dishProvider.notifier);
    await settle(c);
    n.addIngredient(prod(1), 100);
    await settle(c);

    final poisoned = prod(2).copyWith(kcal: double.nan);
    // SPEC: the poisoned product is rejected at the door, so persistence is
    // never exposed to a non-JSON-encodable number.
    expect(() => n.addIngredient(poisoned, 100), returnsNormally);
    expect(() => n.addIngredient(poisoned, 100), returnsNormally);

    await n.flushPendingSaves();
    expect(n.lastPersistenceError, isNull);

    // On disk: only the single healthy ingredient.
    final onDisk = await DishStorageRepository(storageDirectory: dir).loadAll();
    expect(onDisk.activeDraft?.ingredients.length, 1);
    expect(onDisk.activeDraft!.ingredients.single.product.kcal.isFinite, isTrue);
  });

  test('SavedDishesNotifier: save/delete/duplicate keeps the library consistent', () async {
    final dir = tmpDir();
    final c = containerFor(dir);
    final saved = c.read(savedDishesProvider.notifier);
    final n = c.read(dishProvider.notifier);
    await settle(c);

    n.addIngredient(prod(1), 100);
    await n.saveCurrentToLibrary();
    n.setTitle('Первое');
    await n.saveCurrentToLibrary();
    n.createNewDish();
    n.addIngredient(prod(2), 200);
    await n.saveCurrentToLibrary();
    await settle(c);
    expect(c.read(savedDishesProvider).length, 2);

    final first = c.read(savedDishesProvider).last;
    final dup = await saved.duplicateDish(first);
    expect(c.read(savedDishesProvider).length, 3);
    expect(dup.id, isNot(first.id));
    expect(dup.ingredients.first.id, isNot(first.ingredients.first.id));

    await saved.deleteDish(dup.id);
    await settle(c);
    expect(c.read(savedDishesProvider).length, 2);
    final reloaded = await DishStorageRepository(storageDirectory: dir).loadAll();
    expect(reloaded.savedDishes.length, 2);
  });
}
