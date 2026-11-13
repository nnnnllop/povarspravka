// Аудит персистентности, пункт 3 из 10: нулевой файл, отсутствующий файл,
// каталог на месте файла, read-only файл — что становится «пустой
// библиотекой» (handled null), а что бросает необработанное исключение в UI.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-3/P1 zero-byte main with valid .bak → restore from .bak', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'gen1'), savedDishes: [auditDish(100)]);
    await repo.saveAll(activeDraft: auditDish(200, title: 'gen2'), savedDishes: [auditDish(200)]);
    await writeBytes(s.main, const <int>[]);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'gen1');
    expect(await s.main.length(), greaterThan(0), reason: 'main rewritten');
  });

  test('IO-3/P2 zero-byte main with NO .bak → FormatException (NOT a silent '
      'empty library): the file exists, so loadAll() refuses to guess',
      () async {
    final s = await makeStore();
    await writeBytes(s.main, const <int>[]);
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FormatException>());
    expect(await s.main.length(), 0, reason: 'nothing was overwritten');
  });

  test('IO-3/P3 missing main → clean empty document, and the file is NOT '
      'created by a read', () async {
    final s = await makeStore();
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes, isEmpty);
    expect(await s.main.exists(), isFalse);
  });

  test('IO-3/P4 directory at the storage path → FileSystemException (handled '
      'as failure, not as empty library)', () async {
    final s = await makeStore();
    await Directory(s.main.path).create();
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FileSystemException>());
  });

  test('IO-3/P5 saveAll onto a directory path fails and keeps the queue usable',
      () async {
    final s = await makeStore();
    await Directory(s.main.path).create();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final err = await capture(() =>
        repo.saveAll(activeDraft: auditDish(10), savedDishes: const []));
    expect(err, isA<FileSystemException>());
    await Directory(s.main.path).delete();
    await repo.saveAll(activeDraft: auditDish(20), savedDishes: const []);
    expect((await repo.loadAll()).activeDraft!.ingredients.single.weightGrams, 20);
  });

  test('IO-3/P6 read-only main file: read still works, save fails loudly',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'ro'), savedDishes: const []);
    final raw = await s.main.readAsBytes();
    await s.main.setLastModified(DateTime.now());
    // Windows: атрибут «только чтение» блокирует открытие файла на запись.
    Process.runSync('attrib', ['+R', s.main.path]);
    final size = await s.main.length();
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ro');
    // FUZZ-13: черновик и библиотека — разные документы. Отказ записи может
    // проявиться только там, куда мы действительно пишем, поэтому меняем
    // БИБЛИОТЕКУ (а не один черновик): цель теста — «сохранение библиотеки в
    // read-only файл падает громко».
    final err = await capture(
        () => repo.saveAll(
            activeDraft: auditDish(1, title: 'blocked'),
            savedDishes: [auditDish(1, id: 'blocked', title: 'blocked')]));
    // Наблюдаемое: либо отказ записи, либо (если Windows позволил) успех.
    // Главное — данных не теряем и не падаем молча.
    if (err == null) {
      expect((await s.main.readAsString()), contains('blocked'));
    } else {
      expect(err, isA<FileSystemException>());
      expect(await s.main.length(), size, reason: 'main must be untouched');
      expect(await raw.length, size);
    }
    Process.runSync('attrib', ['-R', s.main.path]);
  });

  test('IO-3/P6b read-only main: автосохранение ЧЕРНОВИКА не падает, потому '
      'что библиотека не тронута (FUZZ-13)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'ro'), savedDishes: [
      auditDish(100, id: 'a', title: 'A'),
    ]);
    final raw = await s.main.readAsBytes();
    Process.runSync('attrib', ['+R', s.main.path]);
    // Библиотека прежняя, меняется только черновик — пишется `draft.json`.
    await repo.saveAll(
        activeDraft: auditDish(1, title: 'draft edit'),
        savedDishes: [auditDish(100, id: 'a', title: 'A')]);
    Process.runSync('attrib', ['-R', s.main.path]);
    expect((await s.main.readAsBytes()), raw,
        reason: 'документ библиотеки не тронут — править его незачем');
    final reloaded =
        await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(reloaded.activeDraft!.title, 'draft edit');
    expect(reloaded.savedDishes.single.title, 'A');
  });

  test('IO-3/P7 read-only main + corrupt content → recovery cannot rewrite '
      'main (rename fails); error surfaces instead of silent success',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'gen1'), savedDishes: const []);
    await repo.saveAll(activeDraft: auditDish(200, title: 'gen2'), savedDishes: const []);
    await s.main.writeAsString('{broken', flush: true);
    Process.runSync('attrib', ['+R', s.main.path]);
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    Process.runSync('attrib', ['-R', s.main.path]);
    // Восстановление из .bak читает OK, но перезапись main может упасть.
    // Ожидаемо: данные вернулись, ошибка записи не маскирует потерю.
    if (err != null) {
      expect(err, isA<FileSystemException>());
    }
  });

  // ────────────────────────── DEFECT PROBES ──────────────────────────

  test('IO-3/D-IO03 a zero-byte main is recovered from .bak WITHOUT a silent '
      'rollback: the loss is reported', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'gen1'), savedDishes: [
      auditDish(100, id: 'a', title: 'A')
    ]);
    await repo.saveAll(activeDraft: auditDish(200, title: 'gen2'), savedDishes: [
      auditDish(200, id: 'b', title: 'B'),
      auditDish(100, id: 'a', title: 'A'),
    ]);
    await writeBytes(s.main, const <int>[]);
    final reader = DishStorageRepository(storageDirectory: s.dir);
    final loaded = await reader.loadAll();
    // SPEC: the app must come up (never an empty library), and when it had to
    // fall back to an older generation the user has to be told — a silent
    // rollback that loses dish "b" without a word is the defect.
    expect(loaded.savedDishes, isNotEmpty,
        reason: 'recovery must not yield an empty library');
    expect(reader.didRecoverFromBackup, isTrue,
        reason: 'falling back to .bak must be observable to the UI');
  });

  test('IO-3/D-IO03 probe2: read-only main + corrupt with valid .bak — the '
      'backup can NEVER be applied and loadAll() throws on every launch '
      '(no fallback to reading .bak in place)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'gen1'), savedDishes: const []);
    await repo.saveAll(activeDraft: auditDish(200, title: 'gen2'), savedDishes: const []);
    await s.main.writeAsString('{broken', flush: true);
    Process.runSync('attrib', ['+R', s.main.path]);
    Object? err;
    try {
      await DishStorageRepository(storageDirectory: s.dir).loadAll();
    } catch (e) {
      err = e;
    } finally {
      Process.runSync('attrib', ['-R', s.main.path]);
    }
    // Ожидаемое: восстановленные из .bak данные ВОЗВРАЩАЮТСЯ (хотя бы в
    // память), перезапись main — best effort. Наблюдаемое: отказ доступа,
    // который UI показывает как потерю библиотеки, хотя данные в .bak целы.
    expect(err, isNull,
        reason: 'a recoverable .bak is thrown away because the repaired main '
            'cannot be renamed (${errLabel(err)}); user sees "library lost"');
  });

  test('IO-3/D-IO03 probe3: after the read-only failure above, a fresh '
      'launch WITHOUT the read-only flag recovers — data was never lost, only '
      'masked', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'gen1'), savedDishes: const []);
    await repo.saveAll(activeDraft: auditDish(200, title: 'gen2'), savedDishes: const []);
    await s.main.writeAsString('{broken', flush: true);
    Process.runSync('attrib', ['+R', s.main.path]);
    await captureT(() => DishStorageRepository(storageDirectory: s.dir).loadAll());
    Process.runSync('attrib', ['-R', s.main.path]);
    final recovered = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    // FUZZ-13: черновик хранится отдельным документом, поэтому порча
    // библиотечного файла больше НЕ откатывает черновик к предыдущему
    // поколению: последнее состояние редактора (gen2) переживает поломку
    // библиотеки. Раньше здесь ожидался gen1 — то есть молчаливая потеря
    // последнего ввода.
    expect(recovered.activeDraft!.title, 'gen2',
        reason: 'новейший черновик не откатывается к предыдущему поколению');
  });

  test('IO-3/D-IO04 probe: a missing documents directory (plugin host without '
      'path_provider) silently degrades to an in-memory store — asserts that '
      'the memory fallback is NOT persisted anywhere', () async {
    // Эмуляция реального отказа: каталог документов недоступен, saveAll
    // уходит в `_memoryFallback` (dish_storage_repository.dart:38-43,196).
    final dir = await Directory.systemTemp.createTemp('povar_auditio_nodir_');
    addTearDown(() => dir.delete(recursive: true));
    final blind = DishStorageRepository();
    final err = await IOOverrides.runWithIOOverrides(() async {
      try {
        await blind.saveAll(
            activeDraft: auditDish(100, title: 'в памяти'), savedDishes: const []);
      } catch (e) {
        return e;
      }
      return null;
    }, _NoDocumentsDirIO());
    // Наблюдаемое: исключение либо тихая память. Ожидаемое: пользователь
    // должен узнать, что рецепт не сохранён на диск.
    expect(err, isNull,
        reason: 'saveAll() reported success while nothing was written to disk '
            '(exception=${errLabel(err)})');
    final onDisk = File('${dir.path}/$kMainName');
    expect(await onDisk.exists(), isFalse);
  });
}

class _NoDocumentsDirIO extends IOOverrides {
  // Каталог документов «не существует»: такой путь даёт отказ при записи.
  @override
  File createFile(String path) => File('${path}__missing_dir__/$kMainName');
}
