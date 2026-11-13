import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'culinary_logic_test.dart' show fixture;
import 'support/chaos_io.dart';
import 'support/test_artifacts.dart';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Best-effort удаление временного каталога.
///
/// На Windows файл может ещё удерживаться другим процессом (антивирус,
/// параллельный шард `flutter test`), и `delete(recursive: true)` бросает
/// `PathAccessException`. Падение уборки не должно валить пройденный тест —
/// каталог лежит в `%TEMP%` и будет вычищен системой.
Future<void> removeTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (!dir.existsSync()) return;
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const points = [
    'temp.beforeWrite',
    'temp.afterWrite',
    'main.beforeRead',
    'backup.beforeWrite',
    'backup.afterWrite',
    'backup.beforeRename',
    'backup.afterRename',
    'main.beforeRename'
  ];
  for (final code in [28, 5]) {
    for (final point in points) {
      test(
          'DEEP I/O fault $code at $point preserves committed snapshot and queue',
          () async {
        final dir = await Directory.systemTemp.createTemp('povar_fault_');
        addTearDown(() => removeTempDir(dir));
        final repo = DishStorageRepository(storageDirectory: dir);
        final old = fixture(100).copyWith(title: 'old');
        final current = old.copyWith(title: 'committed');
        await repo.saveAll(activeDraft: old, savedDishes: [old]);
        await repo.saveAll(activeDraft: current, savedDishes: [current]);
        var hit = false;
        final chaos = ChaosIO((p, file) async {
          if (!hit && p == point) {
            hit = true;
            throw FileSystemException(
                'Injected I/O failure', file.path, OSError('test only', code));
          }
        });
        await IOOverrides.runWithIOOverrides(() async {
          await expectLater(
              repo.saveAll(
                  activeDraft: current.copyWith(title: 'failed'),
                  savedDishes: [old]),
              throwsA(isA<FileSystemException>()));
        }, chaos);
        expect(hit, isTrue);
        final recovered =
            await DishStorageRepository(storageDirectory: dir).loadAll();
        expect(recovered.activeDraft!.title, 'committed');
        expect(recovered.savedDishes.single.title, 'committed');
        final next = current.copyWith(title: 'next');
        await repo.saveAll(activeDraft: next, savedDishes: [next]);
        final restarted =
            await DishStorageRepository(storageDirectory: dir).loadAll();
        expect(restarted.activeDraft!.title, 'next');
        expect(restarted.savedDishes.single.title, 'next');
      });
    }
  }
  for (final suffix in ['.tmp', '.bak.tmp']) {
    for (final size in [0, 1, 127]) {
      test('DEEP partial write $suffix $size bytes cannot erase main library',
          () async {
        final dir = await Directory.systemTemp.createTemp('povar_partial_');
        addTearDown(() => removeTempDir(dir));
        final repo = DishStorageRepository(storageDirectory: dir);
        final d = fixture(100).copyWith(title: 'complete');
        await repo.saveAll(activeDraft: d, savedDishes: [d]);
        var hit = false;
        final chaos = ChaosIO((point, file) async {
          final expected =
              suffix == '.tmp' ? 'temp.beforeWrite' : 'backup.beforeWrite';
          if (!hit && point == expected) {
            hit = true;
            await file.writeAsBytes(List.filled(size, 0x7b), flush: true);
            throw FileSystemException('Injected partial write', file.path,
                const OSError('disk full', 28));
          }
        });
        await IOOverrides.runWithIOOverrides(() async {
          await expectLater(
              repo.saveAll(
                  activeDraft: d.copyWith(title: 'incomplete'),
                  savedDishes: []),
              throwsA(isA<FileSystemException>()));
        }, chaos);
        expect(hit, isTrue);
        final recovered =
            await DishStorageRepository(storageDirectory: dir).loadAll();
        expect(recovered.savedDishes.single.toJson(), d.toJson());
        expect(recovered.activeDraft!.toJson(), d.toJson());
      });
    }
  }
  test('DEEP 512 seeded single-bit corruptions restore exact backup',
      timeout: const Timeout(Duration(minutes: 3)), () async {
    final dir = await Directory.systemTemp.createTemp('povar_bits_');
    addTearDown(() => removeTempDir(dir));
    final repo = DishStorageRepository(storageDirectory: dir);
    final old = fixture(100).copyWith(title: 'backup');
    // Обе генерации пишут БИБЛИОТЕКУ (меняем и состав), чтобы у основного
    // документа была резервная копия предыдущего поколения: тест про
    // восстановление библиотеки из `.bak`, а не про черновик.
    await repo.saveAll(activeDraft: old, savedDishes: [old]);
    await repo.saveAll(
        activeDraft: old.copyWith(title: 'current'),
        savedDishes: [old.copyWith(title: 'current')]);
    final main = File('${dir.path}/povarspravka_user_dishes.json');
    final backup = File('${main.path}.bak');
    final raw = await main.readAsBytes();
    final bak = await backup.readAsBytes();
    final rng = Random(20261018);
    final failures = <String>[];
    final sw = Stopwatch()..start();
    for (var i = 0; i < 512; i++) {
      final mutated = List<int>.from(raw);
      final index = rng.nextInt(raw.length);
      mutated[index] ^= 1 << rng.nextInt(8);
      await main.writeAsBytes(mutated);
      final restored =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      // Собираем все нарушения и падаем один раз в конце: 512 отдельных
      // `expect` с `reason` печатали огромный отчёт и упирались в таймаут.
      // Проверяем БИБЛИОТЕКУ: при любой однобитной порче основного файла
      // она восстанавливается из `.bak` до последнего целого поколения.
      if (restored.savedDishes.isEmpty ||
          restored.savedDishes.single.toJson().toString() !=
              old.toJson().toString()) {
        failures.add('mutation $i byte $index');
      }
      if (!_sameBytes(await backup.readAsBytes(), bak)) {
        failures.add('mutation $i rewrote the backup');
      }
    }
    sw.stop();
    // Тест проверяет КОРРЕКТНОСТЬ 512 восстановлений, а не скорость. Раньше
    // он требовал < 25 с, но это свойство машины, а не кода: при четырёх
    // параллельных файлах и холодном антивирусе один прогон занимает 20–30 с.
    // Проверяем рабочее время как СТРАЖУ на порядок величины — чтобы настоящая
    // деградация (например, перечитывание библиотеки на каждое сохранение,
    // как было до FUZZ-13) не осталась незамеченной.
    expect(sw.elapsed, lessThan(const Duration(minutes: 2)),
        reason: '512 восстановлений заняли ${sw.elapsed.inMilliseconds} мс');
    expect(failures, isEmpty, reason: failures.take(5).join(', '));
    // Отчёт пишется во временный каталог: раньше он попадал в
    // `../audit_artifacts/` рабочего дерева (аудит D14).
    artifactFile('io_fault', 'io_fault_result.json').writeAsStringSync(
        jsonEncode({
          'injectedErrors': 16,
          'partialWrites': 6,
          'singleBitCorruptions': 512,
          'failures': failures.length,
          'elapsedMs': sw.elapsedMilliseconds,
          'scope':
              'test-only I/O boundary injection; not physical disk exhaustion'
        }));
  });
}
