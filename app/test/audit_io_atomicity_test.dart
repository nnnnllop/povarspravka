// Аудит персистентности, пункт 1 из 10: атомарность записи, крах процесса
// между шагами протокола `.tmp → .bak.tmp → .bak → rename(main)` и утечка
// осиротевших файлов на диск.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-1/P1 native File.rename over an existing file keeps the old bytes '
      'readable until the atomic replace', () async {
    final s = await makeStore();
    await s.main.writeAsString('OLD', flush: true);
    await s.tmp.writeAsString('NEW', flush: true);
    // Windows: MoveFileEx(REPLACE_EXISTING) — замена существующего файла
    // разрешена и не требует предварительного delete().
    await s.tmp.rename(s.main.path);
    expect(await s.main.readAsString(), 'NEW',
        reason: 'rename over existing destination must succeed');
    expect(await s.tmp.exists(), isFalse);
  });

  test('IO-1/P2 crash BEFORE rename (leftover .tmp) must keep the previous '
      'library recoverable and must not leak disk forever', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100), savedDishes: [
      auditDish(100, id: 'keep', title: 'kept')
    ]);
    // Имитация SIGKILL после записи `.tmp`, но до rename: содержимое `.tmp`
    // полностью валидно, однако process died раньше.
    final next = auditDish(200, id: 'lost', title: 'never committed');
    final encoded = encodeDocument(
        {'activeDraft': next.toJson(), 'savedDishes': <Object>[]});
    await s.tmp.writeAsString(encoded, flush: true);

    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.first.id, 'keep',
        reason: 'crash before rename must not change the committed library');
    expect(loaded.activeDraft!.ingredients.single.weightGrams, 100);

    // Осиротевший `.tmp` теперь перезапишется следующим save — не течёт.
    await repo.saveAll(activeDraft: auditDish(300), savedDishes: const []);
    expect(await s.tmp.exists(), isFalse,
        reason: 'the next successful save must consume the orphan .tmp');
    expect(await s.strays(), isEmpty);
  });

  test('IO-1/P3 crash AFTER .bak rename and BEFORE main rename: loadAll() '
      'serves committed main, .bak holds the same previous generation',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final v1 = auditDish(100, id: 'v1', title: 'v1');
    final v2 = auditDish(200, id: 'v2', title: 'v2');
    final v3 = auditDish(300, id: 'v3', title: 'v3');
    await repo.saveAll(activeDraft: v1, savedDishes: [v1]);
    await repo.saveAll(activeDraft: v2, savedDishes: [v2]);
    // Состояние: main=v2, bak=v1. Начинается третий save: .tmp=v3 уже
    // записан, .bak уже заменён копией v2, процесс умирает до rename.
    await s.tmp.writeAsString(
        encodeDocument({'activeDraft': v3.toJson(), 'savedDishes': <Object>[]}),
        flush: true);
    await s.main.readAsBytes().then((b) => s.bakTmp.writeAsBytes(b, flush: true));
    await s.bakTmp.rename(s.bak.path);

    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'v2',
        reason: 'committed generation must survive a crash after .bak rename');
    expect(loaded.savedDishes.single.title, 'v2');
    // Осиротевший .bak.tmp исчез (rename), но .tmp остался до следующего save.
    expect(await s.bakTmp.exists(), isFalse);
    final names = await s.listNames();
    expect(names, contains('$kMainName.tmp'));
  });

  test('IO-1/P4 orphan `.bak.tmp` left by a crash mid-backup-write is '
      'overwritten by the next save and never accumulates', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100), savedDishes: [auditDish(100)]);
    await s.bakTmp.writeAsString('{"partial":', flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.ingredients.single.weightGrams, 100);
    await repo.saveAll(activeDraft: auditDish(200), savedDishes: const []);
    expect(await s.bakTmp.exists(), isFalse,
        reason: 'orphan .bak.tmp must be replaced, not accumulated');
  });

  test('IO-1/P5 fifty save cycles leave exactly main+.bak and zero stray files',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    for (var i = 0; i < 50; i++) {
      await repo.saveAll(
          activeDraft: auditDish(100 + i.toDouble(), title: 'cycle $i'),
          savedDishes: [auditDish(100, id: 'lib$i', title: 'lib $i')]);
    }
    final names = await s.listNames();
    expect(names, [kMainName, '$kMainName.bak'],
        reason: 'no .tmp/.bak.tmp must survive a clean save cycle');
    expect(await s.strays(), isEmpty);
    // main несёт cycle 49, .bak — предыдущее поколение cycle 48.
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'cycle 49');
    final bakDoc = await s.bak.readAsString();
    expect(bakDoc, contains('cycle 48'));
    // И ни одного «исторического» файла на диске: 50 сохранений = 2 файла.
    expect(names.length, 2);
  });

  test('IO-1/P6 fifty save cycles with a reader racing each write never '
      'observes a missing or invalid main file', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    var bad = 0;
    for (var i = 0; i < 50; i++) {
      final fut = repo.saveAll(
          activeDraft: auditDish(100 + i.toDouble(), title: 'race $i'),
          savedDishes: const []);
      // Читатель «вне очереди» — как второй процесс/изолят.
      try {
        final txt = await s.main.readAsString();
        if (txt.isEmpty) bad++;
      } on PathNotFoundException {
        // Единственная легальная «пропажа» — самый первый save.
        if (i > 0) bad++;
      } catch (_) {
        bad++;
      }
      await fut;
    }
    expect(bad, 0, reason: 'rename() must never expose an empty/missing file');
  });

  test('IO-1/P7 saveAll propagates a rename failure and leaves the previous '
      'main document intact (no torn write)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'good'), savedDishes: [
      auditDish(100, id: 'g', title: 'good')
    ]);
    // Директория на месте `.tmp` воспроизводит отказ записи temp-файла.
    await s.tmp.delete().catchError((_) => s.tmp);
    await Directory(s.tmp.path).create();
    final err = await capture(
        () => repo.saveAll(activeDraft: auditDish(5, title: 'bad'), savedDishes: const []));
    expect(err, isA<FileSystemException>());
    await Directory(s.tmp.path).delete();
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'good');
  });
}
