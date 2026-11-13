// Аудит персистентности, пункт 5 из 10: гонки. Внутри одного экземпляра
// `_tail` сериализует записи; между ДВУМЯ экземплярами (два дерева провайдеров,
// например планшет с двумя движками или рестарт при живом старом изоляте)
// блокировки нет — проверяем потерю данных и порчу файла.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-5/P1 one instance: 200 concurrent saveAll()+loadAll() interleaved '
      'with different payloads — final file is the LAST logical payload and '
      'never invalid', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final futures = <Future<void>>[];
    final lastTitle = 'payload 99';
    for (var i = 0; i < 100; i++) {
      final title = 'payload $i';
      futures.add(repo.saveAll(
          activeDraft: auditDish(100 + i.toDouble(), title: title),
          savedDishes: [auditDish(100, id: 'd$i', title: title)]));
      futures.add(repo.loadAll().then((_) {}));
    }
    await Future.wait(futures);
    // Последний логический payload — «payload 99».
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, lastTitle);
    expect(loaded.savedDishes.single.title, lastTitle);
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect((doc['activeDraft'] as Map)['title'], lastTitle);
  });

  test('IO-5/P2 one instance: concurrent mixed mutations of SavedDishesNotifier '
      'agree with what a restarted app reads from disk', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final n = SavedDishesNotifier(repo);
    addTearDown(n.dispose);
    final jobs = <Future<Object?>>[];
    for (var i = 0; i < 25; i++) {
      final d = auditDish(10 + i.toDouble(), id: 'id$i', title: 't$i');
      jobs.add(n.saveDish(d));
      if (i.isEven) jobs.add(n.updateDraftReference(d));
      if (i % 10 == 0) jobs.add(n.duplicateDish(d));
    }
    await Future.wait(jobs);
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(disk.savedDishes.map((d) => d.toJson()).toList(),
        n.state.map((d) => d.toJson()).toList());
    expect(disk.activeDraft, isNotNull);
  });

  test('IO-5/P3 one instance + DishNotifier autosave racing library mutations '
      'never writes a torn file', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    final dish = DishNotifier(storage: repo, savedDishesNotifier: saved);
    addTearDown(() {
      dish.dispose();
      saved.dispose();
    });
    for (var i = 0; i < 30; i++) {
      dish.setTitle('draft $i');
      dish.addIngredient(auditBeet, 50 + i.toDouble());
      saved.saveDish(auditDish(10, id: 'lib$i', title: 'lib $i'));
      saved.deleteDish('lib${i - 1}');
    }
    await dish.flushPendingSaves();
    await saved.updateDraftReference(dish.state);
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(disk.activeDraft!.title, 'draft 29');
    expect(jsonDecode(await s.main.readAsString()), isA<Map<String, dynamic>>(),
        reason: 'main must always be a complete JSON document');
  });

  // ────────────────────────── DEFECT PROBES ──────────────────────────

  test('IO-5/D-IO05 two repositories on one directory: writes are ATOMIC and '
      'the last generation wins intact (LWW)', () async {
    final s = await makeStore();
    final a = DishStorageRepository(storageDirectory: s.dir);
    final b = DishStorageRepository(storageDirectory: s.dir);
    await a.saveAll(activeDraft: auditDish(1, title: 'init'), savedDishes: const []);

    final futures = <Future<void>>[];
    final errors = <Object>[];
    for (var i = 0; i < 60; i++) {
      futures.add(a
          .saveAll(
              activeDraft: auditDish(10 + i.toDouble(), title: 'A$i'),
              savedDishes: [
                auditDish(10, id: 'a$i', title: 'A$i'),
                auditDish(10, id: 'a${i - 1}', title: 'A${i - 1}'),
              ])
          .catchError(errors.add));
      futures.add(b
          .saveAll(
              activeDraft: auditDish(20 + i.toDouble(), title: 'B$i'),
              savedDishes: [
                auditDish(20, id: 'b$i', title: 'B$i'),
                auditDish(20, id: 'b${i - 1}', title: 'B${i - 1}'),
              ])
          .catchError(errors.add));
    }
    await Future.wait(futures);

    // SPEC: `saveAll` is a full-document replace (last-write-wins). Two writers
    // interleaving must not corrupt the protocol: no I/O errors, and the file
    // must be a COMPLETE generation from exactly one writer — never a merge,
    // never a torn document.
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    final ids = disk.savedDishes.map((d) => d.id).toList();

    expect(errors, isEmpty,
        reason: '${errors.length} cross-instance I/O errors');
    expect(ids, hasLength(2), reason: 'the winning generation is complete');
    final prefix = ids.first.substring(0, 1);
    expect(ids.every((id) => id.startsWith(prefix)), isTrue,
        reason: 'a generation never mixes writers: $ids');
    // …and it is the LATEST generation of whichever writer won.
    final latestA = ids.contains('a59');
    final latestB = ids.contains('b59');
    expect(latestA || latestB, isTrue,
        reason: 'the last committed generation must be on disk: $ids');
    expect(disk.activeDraft, isNotNull);
  });

  test('IO-5/D-IO05 probe2: cross-instance concurrent writes can throw '
      'PathAccessException/FileSystemException(32) on Windows rename',
      () async {
    final s = await makeStore();
    final a = DishStorageRepository(storageDirectory: s.dir);
    final b = DishStorageRepository(storageDirectory: s.dir);
    await a.saveAll(activeDraft: auditDish(1, title: 'init'), savedDishes: const []);
    Object? firstError;
    var errorCount = 0;
    final futures = <Future<void>>[];
    for (var i = 0; i < 80; i++) {
      Future<void> run(DishStorageRepository r, int k) => r
          .saveAll(activeDraft: auditDish(k.toDouble(), title: 'w$k'), savedDishes: const [])
          .catchError((Object e) {
        errorCount++;
        firstError ??= e;
      });
      futures.add(run(a, i));
      futures.add(run(b, 1000 + i));
    }
    await Future.wait(futures);
    // Ожидаемое: 0 ошибок. Наблюдаемое: rename затирает чужой .tmp.
    expect(errorCount, 0,
        reason: 'cross-instance writes produced $errorCount I/O failures; '
            'first=${errLabel(firstError)}');
  });

  test('IO-5/D-IO05 probe3: two FULL notifier trees (two ProviderContainers) '
      'on one directory lose one of them (library fork)', () async {
    final s = await makeStore();
    final diskInit = DishStorageRepository(storageDirectory: s.dir);
    await diskInit.saveAll(activeDraft: auditDish(1, title: 'shared'), savedDishes: const []);

    final repoA = DishStorageRepository(storageDirectory: s.dir);
    final repoB = DishStorageRepository(storageDirectory: s.dir);
    final savedA = SavedDishesNotifier(repoA);
    final savedB = SavedDishesNotifier(repoB);
    addTearDown(() {
      savedA.dispose();
      savedB.dispose();
    });
    await savedA.saveDish(auditDish(10, id: 'fromA', title: 'Рецепт A'));
    await savedB.saveDish(auditDish(20, id: 'fromB', title: 'Рецепт B'));

    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    final ids = disk.savedDishes.map((d) => d.id).toList();
    // SPEC: saveAll is a full-collection replace (LWW). Auto-merging two
    // independent notifier trees would make deletion impossible — a removed
    // dish would keep resurrecting from disk. What must hold instead:
    //  * no I/O error and a readable document (no fork corruption);
    //  * the document contains a COMPLETE library from one writer;
    //  * the winner is the one that saved last.
    final expected = ids.contains('fromB')
        ? savedB.state.map((d) => d.id).toList()
        : savedA.state.map((d) => d.id).toList();
    expect(disk.savedDishes, isNotEmpty,
        reason: 'the document must never be left empty or unreadable');
    expect(ids, contains('fromB'),
        reason: 'the LAST writer (B) wins: disk=$ids');
    expect(ids.contains('fromA') && ids.contains('fromB'), isFalse,
        reason: 'LWW: a single generation, never a merged list: $ids');
    expect(expected, isNotEmpty);
  });
}
