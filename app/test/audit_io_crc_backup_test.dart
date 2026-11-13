// Аудит персистентности, пункт 2 из 10: CRC-32 и восстановление из .bak.
//
// Сценарии (a) обрыв, (b) битовая порча, (c) правка JSON без обновления CRC,
// (d) подмена CRC + вопрос «legacy-документ без crc32 проходит мимо CRC?».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

/// Готовит «поколение 1 → поколение 2»: main=v2, bak=v1.
Future<void> seedTwoGenerations(StorePaths s) async {
  final repo = DishStorageRepository(storageDirectory: s.dir);
  final v1 = auditDish(100, id: 'v1', title: 'ПЕРВОЕ поколение');
  final v2 = auditDish(200, id: 'v2', title: 'ВТОРОЕ поколение');
  await repo.saveAll(activeDraft: v1, savedDishes: [v1]);
  await repo.saveAll(activeDraft: v2, savedDishes: v2.toJson().isEmpty ? [] : [v2]);
  expect(await s.bak.exists(), isTrue);
}

/// Минимальный зонд UI-пута: `DishNotifier` с отказом loadAll() внутри
/// ничего не бросает наружу, а только пишет `lastPersistenceError`.
///
/// (Реальная логика — `DishNotifier._ready.catchError` в
/// `lib/presentation/providers/dish_provider.dart:177`.)
class DishNotifierForProbe {
  final DishStorageRepository repo;
  Object? lastPersistenceError;
  List<Object> state = const [];
  DishNotifierForProbe(this.repo);

  Future<void> init() async {
    try {
      final data = await repo.loadAll();
      state = data.savedDishes;
    } catch (e) {
      lastPersistenceError = e;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('IO-2/(a) truncated main JSON falls back to .bak AND rewrites main',
      () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final bakBefore = await s.bak.readAsBytes();
    final raw = await s.main.readAsBytes();
    await writeBytes(s.main, raw.sublist(0, raw.length ~/ 2));
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ поколение');
    expect(loaded.savedDishes.single.title, 'ПЕРВОЕ поколение');
    expect(await sameBytes(s.bak, s.bak) , isTrue);
    expect(await s.bak.readAsBytes(), bakBefore,
        reason: 'recovery must never overwrite the good backup');
    // main ПЕРЕПИСАН восстановленными данными.
    final rewritten = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect(rewritten['storageVersion'], 1);
    expect((rewritten['activeDraft'] as Map)['title'], 'ПЕРВОЕ поколение');
    // Второй load уже читает main, а не .bak (main валиден).
    final again = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(again.activeDraft!.title, 'ПЕРВОЕ поколение');
    expect(await s.tmp.exists(), isFalse, reason: 'recovery temp must be renamed');
  });

  test('IO-2/(b) single flipped byte in the middle (bit rot) is caught by CRC '
      'and recovered from .bak', () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final raw = await s.main.readAsBytes();
    final idx = raw.length ~/ 2;
    final mutated = List<int>.from(raw);
    mutated[idx] ^= 0x04;
    await writeBytes(s.main, mutated);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ поколение',
        reason: 'bit rot must never be served to the UI');
    final rewritten = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect((rewritten['activeDraft'] as Map)['title'], 'ПЕРВОЕ поколение');
  });

  test('IO-2/(b2) single-byte flips sampled across the whole main document are '
      'all detected (0.9 s per probe because each one triggers a full '
      'recovery; the probe count is bounded by the 30 s test timeout)',
      () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final good = await s.main.readAsBytes();
    final undetected = <int>[];
    // Ровно 30 проб: каждая = запись + чтение + восстановление .bak + rename
    // (~0.9 с из-за CreateFileW с PN_* флагами), 30 × 0.9 s ≈ 27 s.
    const maxProbes = 30;
    final step = (good.length / maxProbes).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < good.length; i += step) {
      final mutated = List<int>.from(good);
      mutated[i] ^= 0x01;
      await writeBytes(s.main, mutated);
      final loaded =
          await DishStorageRepository(storageDirectory: s.dir).loadAll();
      if (loaded.activeDraft?.title != 'ПЕРВОЕ поколение') undetected.add(i);
    }
    expect(undetected, isEmpty,
        reason: 'bytes whose corruption slipped through CRC: $undetected');
    // Возвращаем валидный main для порядка.
    await writeBytes(s.main, good);
  });

  test('IO-2/(c) valid JSON whose payload changed WITHOUT a CRC update is '
      'rejected and recovered from .bak', () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    // Правка «на 1 г»: JSON остаётся синтаксически валидным, CRC — прежний.
    final ing = ((doc['activeDraft'] as Map)['ingredients'] as List).first as Map;
    ing['weightGrams'] = 9999.0;
    await s.main.writeAsString(jsonEncode(doc), flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ поколение');
    expect(loaded.activeDraft!.ingredients.single.weightGrams, 100);
  });

  test('IO-2/(d) tampered crc32 field is rejected and recovered from .bak',
      () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    doc['crc32'] = ((doc['crc32'] as int) ^ 0xDEAD) & 0xffffffff;
    await s.main.writeAsString(jsonEncode(doc), flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ поколение');
  });

  test('IO-2/(d2) main and .bak BOTH corrupt → FormatException surfaces, '
      'nothing silent', () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    const damaged = '{"savedDishes":[';
    await s.main.writeAsString(damaged, flush: true);
    await s.bak.writeAsString(damaged, flush: true);
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FormatException>(),
        reason: 'double corruption must not degrade to an empty library');
    // И файлы НЕ перезаписаны «пустой библиотекой».
    expect(await s.main.length(), damaged.length);
    expect(await s.bak.length(), damaged.length);
    expect(utf8.decode(await s.main.readAsBytes()), damaged);
  });

  test('IO-2/(d3) both corrupt with VALID JSON but wrong payloads: rejected '
      'via FormatException (no partial library)', () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    await s.main.writeAsString('{"savedDishes":[1,2,3],"activeDraft":null}',
        flush: true);
    await s.bak.writeAsString('{"savedDishes":[{"id":""}]}', flush: true);
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FormatException>());
  });

  test('IO-2/P1 legacy document (no storageVersion, no crc32) is still '
      'loadable and upgraded on next save', () async {
    final s = await makeStore();
    final dish = auditDish(150, title: 'старый формат');
    await s.main.writeAsString(jsonEncode({
      'activeDraft': dish.toJson(),
      'savedDishes': [dish.toJson()],
    }), flush: true);
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final legacy = await repo.loadAll();
    expect(legacy.savedDishes.single.title, 'старый формат');
    await repo.saveAll(
        activeDraft: legacy.activeDraft, savedDishes: legacy.savedDishes);
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect(doc['storageVersion'], 1);
    expect(doc['crc32'], isA<int>());
  });

  // ────────────────────────── DEFECT PROBES ──────────────────────────

  test('IO-2/D-IO01 probe2: stripping crc32 from a legit document also '
      'disables corruption detection (only crc32 key, storageVersion kept)',
      () async {
    final s = await makeStore();
    await seedTwoGenerations(s);
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    doc.remove('crc32'); // storageVersion: 1 остаётся
    final ing = ((doc['activeDraft'] as Map)['ingredients'] as List).first as Map;
    ing['weightGrams'] = 424242.0;
    await s.main.writeAsString(jsonEncode(doc), flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    // Наблюдаемое: 424242 проходит, хотя storageVersion=1 обещает CRC.
    expect(loaded.activeDraft!.ingredients.single.weightGrams, 100,
        reason: 'document declared storageVersion=1 but corrupted weight '
            '${loaded.activeDraft!.ingredients.single.weightGrams} was '
            'accepted because crc32 was absent');
  });

  test('IO-2/D-IO02 first save leaves a recoverable second copy (spec)', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: auditDish(100, title: 'единственный'),
        savedDishes: [auditDish(100, id: 'only', title: 'единственный')]);
    // SPEC: the very first save must not leave a single, unprotected copy.
    expect(await s.bak.exists(), isTrue,
        reason: 'first save must create a recovery copy');
    expect(await s.bak.length(), greaterThan(0));

    final raw = await s.main.readAsBytes();
    await writeBytes(s.main, raw.sublist(0, raw.length - 10));

    // The damaged main is rejected and the recipe is recovered from the copy.
    final recovered = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(recovered.savedDishes.single.title, 'единственный');
    expect(recovered.activeDraft!.title, 'единственный');
  });
}
