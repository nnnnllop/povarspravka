import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'culinary_logic_test.dart' show fixture;
import 'support/chaos_io.dart';

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
        addTearDown(() => dir.delete(recursive: true));
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
        addTearDown(() => dir.delete(recursive: true));
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
  test('DEEP 512 seeded single-bit corruptions restore exact backup', () async {
    final dir = await Directory.systemTemp.createTemp('povar_bits_');
    addTearDown(() => dir.delete(recursive: true));
    final repo = DishStorageRepository(storageDirectory: dir);
    final old = fixture(100).copyWith(title: 'backup');
    await repo.saveAll(activeDraft: old, savedDishes: [old]);
    await repo
        .saveAll(activeDraft: old.copyWith(title: 'current'), savedDishes: []);
    final main = File('${dir.path}/povarspravka_user_dishes.json');
    final backup = File('${main.path}.bak');
    final raw = await main.readAsBytes();
    final bak = await backup.readAsBytes();
    final rng = Random(20261018);
    for (var i = 0; i < 512; i++) {
      final mutated = List<int>.from(raw);
      final index = rng.nextInt(raw.length);
      mutated[index] ^= 1 << rng.nextInt(8);
      await main.writeAsBytes(mutated);
      final restored =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(restored.activeDraft!.toJson(), old.toJson(),
          reason: 'mutation $i byte $index');
      expect(restored.savedDishes.single.toJson(), old.toJson());
      expect(await backup.readAsBytes(), bak);
    }
    final out = Directory('../audit_artifacts/mega')
      ..createSync(recursive: true);
    File('${out.path}/io_fault_result.json').writeAsStringSync(jsonEncode({
      'injectedErrors': 16,
      'partialWrites': 6,
      'singleBitCorruptions': 512,
      'failures': 0,
      'scope': 'test-only I/O boundary injection; not physical disk exhaustion'
    }));
  });
}
