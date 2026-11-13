// Аудит персистентности, пункт 6 из 10: мутация «живого» состояния во время
// записи. Проверяем, что `saveAll` снимает снимок СИНХРОННО в момент вызова
// (`toJson()` до постановки в очередь), и что ни один метод провайдеров не
// передаёт в запись живую коллекцию, которую потом мутируют.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-6/P1 saveAll() snapshots its arguments synchronously: mutating the '
      'passed List<Dish> AFTER the call does not change the written document',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final dish = auditDish(100, title: 'снимок');
    final live = <dynamic>[dish];
    final first =
        repo.saveAll(activeDraft: dish, savedDishes: live.cast());
    // Мутируем «живую» коллекцию сразу после вызова, до завершения записи.
    live.add(auditDish(200, id: 'intruder', title: 'втиснутое'));
    live.removeAt(0);
    await first;
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.map((d) => d.title).toList(), ['снимок']);
  });

  test('IO-6/P2 DishNotifier._persist captures `state` by reference but Dish '
      'is immutable — later edits do not leak into an already-queued draft',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final notifier = DishNotifier(storage: repo);
    addTearDown(notifier.dispose);
    notifier.setTitle('первый');
    notifier.addIngredient(auditBeet, 10);
    notifier.setTitle('второй');
    notifier.addIngredient(auditBeet, 20);
    await notifier.flushPendingSaves();
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'второй');
    expect(loaded.activeDraft!.ingredients.length, 2);
    expect(loaded.activeDraft!.ingredients.map((i) => i.weightGrams),
        [10.0, 20.0]);
    // Дедупликации/дубликатов нет: ровно два ингредиента.
    final ids = loaded.activeDraft!.ingredients.map((i) => i.id).toSet();
    expect(ids.length, 2);
  });

  test('IO-6/P3 adding an ingredient WHILE saveCurrentToLibrary() is in flight: '
      'the saved library record keeps the CALL-TIME content', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    final dish = DishNotifier(storage: repo, savedDishesNotifier: saved);
    addTearDown(() {
      dish.dispose();
      saved.dispose();
    });
    dish.setTitle('борщ');
    dish.addIngredient(auditBeet, 100);
    // Кнопка «Сохранить в библиотеку».
    final save = dish.saveCurrentToLibrary();
    // Пока запись в полёте — пользователь добавляет ещё один ингредиент.
    dish.addIngredient(auditBeet, 50);
    dish.setTitle('борщ (правка)');
    await save;
    await dish.flushPendingSaves();
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.length, 1);
    // В библиотеке — состояние НА МОМЕНТ вызова: один ингредиент 100 г.
    expect(loaded.savedDishes.single.ingredients.length, 1,
        reason: 'live list leaked into the saved record');
    expect(loaded.savedDishes.single.ingredients.single.weightGrams, 100);
    expect(loaded.savedDishes.single.title, 'борщ');
    // Черновик при этом содержит правку.
    expect(loaded.activeDraft!.ingredients.length, 2);
    expect(loaded.activeDraft!.title, 'борщ (правка)');
    // Память провайдера == диск.
    expect(jsonEncode(loaded.savedDishes.single.toJson()),
        jsonEncode(saved.state.single.toJson()));
  });

  test('IO-6/P4 deleteDish + duplicateDish racing with draft autosave keep the '
      'library consistent (no resurrected or lost records)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    final dish = DishNotifier(storage: repo, savedDishesNotifier: saved);
    addTearDown(() {
      dish.dispose();
      saved.dispose();
    });
    final a = auditDish(100, id: 'a', title: 'A');
    final b = auditDish(200, id: 'b', title: 'B');
    final d = saved.duplicateDish(a);
    await Future.wait([
      saved.saveDish(a),
      saved.saveDish(b),
      d,
      dish.saveCurrentToLibrary(),
    ]);
    final dup = await d;
    await saved.deleteDish(b.id);
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(disk.savedDishes.map((x) => x.id).toList(),
        saved.state.map((x) => x.id).toList());
    expect(disk.savedDishes.map((x) => x.id), isNot(contains(b.id)));
    expect(disk.savedDishes.map((x) => x.id), contains(dup.id));
    // Копия — глубоко независимый продукт (не общий объект).
    final copyIng =
        disk.savedDishes.firstWhere((x) => x.id == dup.id).ingredients;
    expect(identical(copyIng.single.product, auditBeet), isFalse);
  });

  test('IO-6/P5 a queued saveAll() of a live list is unaffected by a later '
      'rebuild of that list (no post-hoc mutation of the snapshot)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final a = auditDish(100, id: 'a', title: 'keep');
    final live = [a];
    final first = repo.saveAll(activeDraft: null, savedDishes: live);
    live
      ..removeAt(0)
      ..add(auditDish(200, id: 'late', title: 'late'));
    final second = repo.saveAll(activeDraft: null, savedDishes: live);
    await Future.wait([first, second]);
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    // Второй вызов видит ПОСЛЕДНЮЮ версию списка, первый — исходную.
    expect(disk.savedDishes.map((d) => d.id).toList(), ['late']);
    final bak = jsonDecode(await s.bak.readAsString()) as Map<String, dynamic>;
    expect((bak['savedDishes'] as List).single['id'], 'a');
  });
}
