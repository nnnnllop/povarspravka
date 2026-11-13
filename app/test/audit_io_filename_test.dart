// Аудит персистентности, пункт 10 из 10: имя файла, зарезервированные имена и
// создание родительского каталога, которого ещё нет.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-10/P1 fixed storage file name has no reserved-name / illegal-char '
      'collision on Windows (CON/PRN/AUX/NUL, <>:"/\\|?*)', () {
    const name = kMainName;
    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'LPT1', 'LPT2',
    };
    final stem = name.split('.').first.toUpperCase();
    expect(reserved.contains(stem), isFalse);
    expect(RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(name), isFalse);
    // Расширение не заканчивается точкой/пробелом (Windows отбрасывает их).
    expect(name.endsWith('.') || name.endsWith(' '), isFalse);
    expect(name.length, lessThan(255));
  });

  test('IO-10/P2 parent directory that does not exist yet is created '
      'recursively on first save', () async {
    final s = await makeStore();
    final deep = Directory('${s.dir.path}${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b${Platform.pathSeparator}c');
    expect(await deep.exists(), isFalse);
    final repo = DishStorageRepository(storageDirectory: deep);
    await repo.saveAll(activeDraft: auditDish(100), savedDishes: const []);
    expect(await File('${deep.path}${Platform.pathSeparator}$kMainName').exists(),
        isTrue);
    final loaded = await DishStorageRepository(storageDirectory: deep).loadAll();
    expect(loaded.activeDraft!.ingredients.single.weightGrams, 100);
  });

  test('IO-10/P3 directory path with Cyrillic, spaces, emoji, trailing spaces '
      'and a very long name works end-to-end', () async {
    final s = await makeStore();
    final weird = 'Поварская справка 🍲 ' '  ${'ё' * 40}';
    final dir = Directory('${s.dir.path}${Platform.pathSeparator}$weird');
    final repo = DishStorageRepository(storageDirectory: dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'Тест'), savedDishes: const []);
    final loaded = await DishStorageRepository(storageDirectory: dir).loadAll();
    expect(loaded.activeDraft!.title, 'Тест');
    final names = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last);
    expect(names, contains(kMainName));
  });

  test('IO-10/P4 a directory name using a Windows device name is rejected by '
      'the OS, and saveAll surfaces it (no silent memory fallback here)',
      () async {
    final s = await makeStore();
    final dir = Directory('${s.dir.path}${Platform.pathSeparator}CON');
    final repo = DishStorageRepository(storageDirectory: dir);
    final err = await capture(
        () => repo.saveAll(activeDraft: auditDish(100), savedDishes: const []));
    // Ожидаемое: либо FileSystemException, либо успех (Windows 10+ с
    // longPathAware позволяет «CON» как имя каталога только в некоторых
    // контекстах). Главное — НЕ тихий успех без файла.
    if (err == null) {
      final f = File('${dir.path}${Platform.pathSeparator}$kMainName');
      expect(await f.exists(), isTrue,
          reason: 'reported success without writing anything');
    } else {
      expect(err, isA<FileSystemException>());
    }
  });

  test('IO-10/P5 two repositories with different directories never collide '
      'even with identical payloads', () async {
    final a = await makeStore();
    final b = await makeStore();
    final ra = DishStorageRepository(storageDirectory: a.dir);
    final rb = DishStorageRepository(storageDirectory: b.dir);
    await Future.wait([
      ra.saveAll(activeDraft: auditDish(100, title: 'A'), savedDishes: const []),
      rb.saveAll(activeDraft: auditDish(200, title: 'B'), savedDishes: const []),
    ]);
    expect((await ra.loadAll()).activeDraft!.title, 'A');
    expect((await rb.loadAll()).activeDraft!.title, 'B');
  });

  test('IO-10/P6 a storage directory that is a FILE (not a directory) fails '
      'loudly, not silently', () async {
    final s = await makeStore();
    final fake = File('${s.dir.path}${Platform.pathSeparator}not_a_dir');
    await fake.writeAsString('x');
    final repo = DishStorageRepository(storageDirectory: Directory(fake.path));
    final err = await capture(
        () => repo.saveAll(activeDraft: auditDish(100), savedDishes: const []));
    expect(err, isNotNull);
    expect(err, isA<FileSystemException>());
  });
}
