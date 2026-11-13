// ПОВТОРНЫЙ АУДИТ — диагностические пробники (не находки): измеряем, какие
// именно операции Dart I/O на Windows конфликтуют с `File.rename`.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'reaudit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P0 где именно создаётся draft.json', () async {
    final s = await newStore('pr0');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final lib = [mkDish(id: 'lib', title: 'lib')];
    await repo.saveAll(activeDraft: mkDish(id: 'd1', title: 'd1'), savedDishes: lib);
    // ignore: avoid_print
    print('P0 after 1st save files=${s.namesSync()}');
    await repo.saveAll(activeDraft: mkDish(id: 'd1', title: 'd1'), savedDishes: lib);
    print('P0 after 2nd identical save files=${s.namesSync()}');
    await repo.saveAll(activeDraft: mkDish(id: 'd2', title: 'd2'), savedDishes: lib);
    print('P0 after 3rd (draft changed) files=${s.namesSync()}');
    final fresh = DishStorageRepository(storageDirectory: s.dir);
    await fresh.saveAll(activeDraft: mkDish(id: 'd3', title: 'd3'), savedDishes: lib);
    print('P0 after 4th (NEW instance, draft changed) files=${s.namesSync()}');
    final reloaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    print('P0 loaded draft=${reloaded.activeDraft?.id}');
  });

  test('P1 конфликт операций чтения с rename (Windows)', () async {
    final rand = Random(7);
    final r = StringBuffer();
    for (final op in ['readAsBytes', 'readAsString', 'openRead', 'length', 'exists']) {
      var conflicts = 0;
      final s = await newStore('pr1_$op');
      await s.lib.writeAsBytes(List.filled(200000, 0x61), flush: true);
      var reading = true;
      Future<void> reader() async {
        while (reading) {
          try {
            switch (op) {
              case 'readAsBytes':
                await s.lib.readAsBytes();
              case 'readAsString':
                await s.lib.readAsString();
              case 'openRead':
                await s.lib.openRead().fold<int>(0, (a, b) => a + b.length);
              case 'length':
                await s.lib.length();
              case 'exists':
                await s.lib.exists();
            }
          } catch (_) {}
        }
      }

      final f = reader();
      for (var i = 0; i < 60; i++) {
        final t = s.f('w$i.tmp');
        await t.writeAsBytes(List.filled(200000, 0x62), flush: true);
        try {
          await t.rename(s.lib.path);
        } on FileSystemException {
          conflicts++;
        }
      }
      reading = false;
      await f;
      r.writeln('P1 $op: renameConflicts=$conflicts / 60');
    }
    // ignore: avoid_print
    print(r.toString());
    expect(rand, isNotNull);
  });

  // Зонд ОС, а не утверждение о коде: 20 проб × до 200 попыток с паузой
  // 5 мс — это 20 с одних только пауз, а на Windows пауза округляется до
  // кванта системного таймера. Стандартных 30 с ему не хватало (таймаут
  // в базовом прогоне), поэтому бюджет задан явно; проверка не менялась.
  test('P2 конфликт только от открытого хэндла: сколько повторных попыток нужно',
      timeout: const Timeout(Duration(minutes: 3)), () async {
    final s = await newStore('pr2');
    await s.lib.writeAsString('A' * 1000, flush: true);
    var needed = <int>[];
    for (var trial = 0; trial < 20; trial++) {
      final raf = await s.lib.open();
      final t = s.f('x$trial.tmp');
      await t.writeAsString('B' * 1000, flush: true);
      // Держим хэндл открытым, но не читаем.
      var attempts = 0;
      var ok = false;
      while (attempts < 200 && !ok) {
        attempts++;
        try {
          await t.rename(s.lib.path);
          ok = true;
        } on FileSystemException {
          await Future<void>.delayed(Duration(milliseconds: 5));
        }
      }
      await raf.close();
      if (!ok) await t.rename(s.lib.path);
      needed.add(attempts);
    }
    // ignore: avoid_print
    print('P2 attempts-to-rename while handle held: $needed');
    expect(needed.length, 20);
  });

  test('P3 запись .tmp и rename под reader-loop без перечитывания main',
      () async {
    // Сравнение: конфликт даёт ЛИБО чтение main, ЛИБО rename. Проверяем,
    // что .tmp самого rename-целя тоже не конфликтует.
    final s = await newStore('pr3');
    await s.lib.writeAsString('{"a":1}', flush: true);
    final bad = <String>[];
    var reading = true;
    Future<void> reader() async {
      while (reading) {
        try {
          await s.lib.readAsString();
        } catch (_) {}
      }
    }

    final f = reader();
    for (var i = 0; i < 60; i++) {
      final t = s.f('w$i.tmp');
      await t.writeAsString(jsonEncode({'a': i}), flush: true);
      try {
        await t.rename(s.lib.path);
      } on FileSystemException catch (e) {
        bad.add('${e.osError?.errorCode}@$i');
      }
    }
    reading = false;
    await f;
    // ignore: avoid_print
    print('P3 renameConflicts=${bad.length}/60 ${bad.take(6)}');
    expect(bad.length, lessThanOrEqualTo(60));
  });
}
