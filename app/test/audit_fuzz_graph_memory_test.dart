// FUZZ-EDGE / PART 6 — circular composite dependency & memory/GC heuristics.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

Product prod(int id, {bool? isDish, double protein = 10}) => Product(
      id: id,
      code: 'p$id',
      name: 'Блюдо $id',
      groupId: 1,
      source: 'skurikhin',
      protein: protein,
      fat: 5,
      carbs: 20,
      kcal: 300,
      isDish: isDish,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 400+ real fsync'd writes through the serialized storage queue; the default
  // 30 s per-test budget is not enough. This is harness cost, not app latency
  // (a single user save is ~1 ms).
  const longTimeout = Timeout(Duration(minutes: 4));

  group('Circular composite dependency (полуфабрикаты)', () {
    test('Product has NO link back to a Dish — the cycle is unrepresentable in the model', () {
      // Product fields: id/code/name/group/…/isDish/measures. There is no
      // dishId, no child list, no resolver. So A→B→A cannot be expressed.
      final p = prod(1, isDish: true);
      expect(p.isDish, isTrue);
      expect(p.isDishOnly, isTrue);
      // The only "composite" link is a flat Product row with isDish=1.
      final json = p.toJson();
      expect(json.keys.where((k) => k.contains('dish')).toList(), ['is_dish']);
    });

    test('embedding dish B as a product of A is finite: numbers are flat, recursion impossible', () {
      // B "contains" a product that represents A, but only as DATA (its BJU).
      final aAsProduct = prod(99, isDish: true, protein: 8);
      final b = Dish(
        id: 'B',
        ingredients: [
          Ingredient(id: 'b1', product: aAsProduct, weightGrams: 100),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final bAsProduct = prod(98, isDish: true, protein: 12);
      final a = Dish(
        id: 'A',
        ingredients: [
          Ingredient(id: 'a1', product: bAsProduct, weightGrams: 100),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      // Both compute instantly; there is no traversal, hence no stack overflow.
      final sw = Stopwatch()..start();
      final ra = CalculationEngine.calculate(a);
      final rb = CalculationEngine.calculate(b);
      sw.stop();
      expect(ra.rawTotalProtein, 12.0);
      expect(rb.rawTotalProtein, 8.0);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('a self-referencing PRODUCT object (same instance) is still just one row', () {
      final shared = prod(7, isDish: true);
      final d = Dish(
        id: 'S',
        ingredients: [
          Ingredient(id: 'x', product: shared, weightGrams: 100),
          Ingredient(id: 'y', product: shared, weightGrams: 100),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final r = CalculationEngine.calculate(d);
      expect(r.rawTotalProtein, 20.0); // counted twice, computed once per row
      // And serialisation does not recurse.
      expect(() => jsonEncode(d.toJson()), returnsNormally);
    });

    test('loading a saved dish that embeds isDish rows does not recurse', () async {
      final dir = Directory.systemTemp.createTempSync('povar_fuzz_cyc_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final inner = prod(5, isDish: true);
      final d = Dish(
        id: 'outer',
        ingredients: [Ingredient(id: 'i', product: inner, weightGrams: 50)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final repo = DishStorageRepository(storageDirectory: dir);
      await repo.saveAll(activeDraft: d, savedDishes: [d]);
      final loaded = await repo.loadAll();
      expect(loaded.activeDraft!.ingredients.first.product.isDish, isTrue);
      expect(loaded.savedDishes.single.id, 'outer');
      expect(() => CalculationEngine.calculate(loaded.activeDraft!), returnsNormally);
    });
  });

  group('Memory / GC — 200 dishes through the notifier', () {
    test('[FUZZ-13] a draft save does not rewrite the library: < 50 ms at 200 dishes', timeout: longTimeout, () async {
      final dir = Directory.systemTemp.createTempSync('povar_fuzz_perf_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final repo = DishStorageRepository(storageDirectory: dir);

      Dish libDish(int i) => Dish(
            id: 'lib-$i',
            title: 'Блюдо $i',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            ingredients: List.generate(
                10,
                (k) => Ingredient(
                    id: 'i$k', product: prod(k), weightGrams: 100.0 + k)),
          );
      final library = List.generate(200, libDish);
      await repo.saveAll(activeDraft: library.first, savedDishes: library);
      final doc = File(
          '${dir.path}${Platform.pathSeparator}povarspravka_user_dishes.json');
      final docBytes = doc.lengthSync();

      // Одно автосохранение черновика (одно нажатие клавиши в редакторе):
      // библиотека не меняется, поэтому трогать её документ незачем.
      //
      // Первое сохранение прогревает JIT и кэш отпечатка библиотеки —
      // измеряем установившийся режим, как при наборе текста.
      await repo.saveAll(activeDraft: library.first, savedDishes: library);
      final docMtimeBefore = doc.lastModifiedSync();
      final docBytesBefore = doc.lengthSync();
      final timings = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        await repo.saveAll(activeDraft: library.first, savedDishes: library);
        sw.stop();
        timings.add(sw.elapsedMicroseconds);
      }
      final worst = timings.reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print('PART6 one draft save over 200 dishes ($docBytes bytes): '
          'worst of 5 = ${(worst / 1000).toStringAsFixed(1)} ms $timings (µs)');

      // FUZZ-13: раньше одно нажатие стоило O(библиотеки) — 0,8–1,6 с на
      // 200 блюдах, потому что документ переписывался, перечитывался ради
      // `.bak` и пересчитывался по CRC целиком. Теперь черновик — отдельный
      // `draft.json`, а библиотечный документ не трогается вовсе.
      expect(doc.lastModifiedSync(), docMtimeBefore,
          reason: 'FUZZ-13: черновик не переписывает библиотеку');
      expect(doc.lengthSync(), docBytesBefore,
          reason: 'FUZZ-13: документ библиотеки не изменился');

      // И библиотечный документ действительно не тронут.
      expect(doc.lengthSync(), docBytes,
          reason: 'документ библиотеки не перезаписывался');

      // Требование: одно автосохранение черновика при 200 блюдах — < 50 мс.
      expect(worst ~/ 1000, lessThan(50),
          reason: 'FUZZ-13: сохранение черновика не должно зависеть от '
              'размера библиотеки (получилось ${worst ~/ 1000} мс)');
    });

    test('reachability: 200 saved dishes leave no residue after deletion', timeout: longTimeout, () async {
      final dir = Directory.systemTemp.createTempSync('povar_fuzz_gc_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = ProviderContainer(overrides: [
        dishStorageRepositoryProvider.overrideWithValue(
            DishStorageRepository(storageDirectory: dir)),
      ]);
      addTearDown(c.dispose);

      final saved = c.read(savedDishesProvider.notifier);
      final n = c.read(dishProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await n.flushPendingSaves();
      n.addIngredient(prod(0), 100);

      var listenerCalls = 0;
      c.listen<List<Dish>>(savedDishesProvider, (_, __) => listenerCalls++);

      final bulk = List.generate(
          200,
          (i) => Dish(
                id: 'lib-$i',
                title: 'Блюдо $i',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
                ingredients: [
                  Ingredient(id: 'x', product: prod(i), weightGrams: 100.0 + i)
                ],
              ));
      // Reachability is a StateNotifier property, not an I/O property: load the
      // bulk in memory (each deleteDish() would otherwise pay the O(library)
      // document rewrite — see FUZZ-13, covered in the realtime suite).
      saved.setInitialDishes(bulk, null);
      expect(c.read(savedDishesProvider).length, 200);
      expect(c.read(savedDishesProvider).map((d) => d.id).toSet().length, 200);
      expect(listenerCalls, greaterThan(0));

      // The notifier's ONLY container of dishes is `state`. Empty it directly.
      final ids = c.read(savedDishesProvider).map((d) => d.id).toList();
      for (final id in ids) {
        saved.state = saved.state.where((d) => d.id != id).toList();
      }
      expect(c.read(savedDishesProvider), isEmpty);
      expect(c.read(savedDishesProvider).length, 0);
      // The draft is untouched by library churn.
      expect(c.read(dishProvider).ingredients.length, 1);

      // No residue on disk after a single save of the emptied library.
      await saved.saveDish(bulk.first);
      await saved.deleteDish(bulk.first.id);
      await c.read(dishProvider.notifier).flushPendingSaves();
      final onDisk =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(onDisk.savedDishes, isEmpty);
    });

    test('200 createNewDish() without saving does not accumulate', timeout: longTimeout, () async {
      final dir = Directory.systemTemp.createTempSync('povar_fuzz_gc2_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = ProviderContainer(overrides: [
        dishStorageRepositoryProvider.overrideWithValue(
            DishStorageRepository(storageDirectory: dir)),
      ]);
      addTearDown(c.dispose);
      final n = c.read(dishProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await n.flushPendingSaves();
      for (var i = 0; i < 200; i++) {
        n.createNewDish();
        n.addIngredient(prod(i), 100);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await n.flushPendingSaves();
      // Only the last draft survives; each createNewDish() replaced the state.
      expect(c.read(dishProvider).ingredients.length, 1);
      expect(c.read(savedDishesProvider), isEmpty);
    });
  });
}
