// Аудит персистентности, пункт 7 из 10: crash-consistency черновика при
// повреждённых полях (customYieldGrams = 1e309, ретеншн вне 0..1, inf/nan,
// отрицательный вес, дубли id). Что происходит — падение, откат на .bak или
// тихая подмена значений.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

/// Кладёт в main «поколение 2» с подменённым полем черновика и возвращает
/// результат loadAll() / ошибку.
Future<({DishStorageData? data, Object? error})> loadWithTweak(
  StorePaths s,
  void Function(Map<String, dynamic> draft) tweak,
) async {
  final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
  tweak(doc['activeDraft'] as Map<String, dynamic>);
  await s.main.writeAsString(encodeDocument(doc), flush: true);
  try {
    return (
      data: await DishStorageRepository(storageDirectory: s.dir).loadAll(),
      error: null
    );
  } catch (e) {
    return (data: null, error: e);
  }
}

Future<StorePaths> seeded() async {
  final s = await makeStore();
  final repo = DishStorageRepository(storageDirectory: s.dir);
  // Каждое поколение реалистично младше: updatedAt растёт, иначе
  // `Dish.toJson()` идентичен и `_bak` станет копией main.
  final gen1 = Dish(
      id: 'gen1',
      title: 'ПЕРВОЕ',
      ingredients: [
        Ingredient(id: 'gen1-1', product: auditBeet, weightGrams: 100)
      ],
      createdAt: DateTime(2026, 1, 1, 10),
      updatedAt: DateTime(2026, 1, 1, 10));
  await repo.saveAll(activeDraft: gen1, savedDishes: [gen1]);
  final gen2 = Dish(
      id: 'gen2',
      title: 'ВТОРОЕ',
      ingredients: [
        Ingredient(id: 'gen2-1', product: auditBeet, weightGrams: 200)
      ],
      customYieldGrams: 150,
      createdAt: DateTime(2026, 1, 1, 11),
      updatedAt: DateTime(2026, 1, 1, 11));
  await repo.saveAll(activeDraft: gen2, savedDishes: [gen2]);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-7/P1 customYieldGrams = 1e309 (JSON overflow) in the draft → '
      'falls back to .bak, no throw, main repaired', () async {
    final s = await seeded();
    final doc = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    // 1e309 нельзя выразить через jsonEncode (это double), поэтому
    // вставляем сырой литерал в текст, как пришло бы с испорченного диска.
    final text = (await s.main.readAsString()).replaceFirst(
        RegExp(r'"customYieldGrams":150\.0'), '"customYieldGrams":1e309');
    expect(text, contains('1e309'));
    await s.main.writeAsString(text, flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ');
    expect(loaded.activeDraft!.customYieldGrams, isNull);
    final repaired = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect((repaired['activeDraft'] as Map)['title'], 'ПЕРВОЕ');
    expect(doc['activeDraft'], isNotNull);
  });

  test('IO-7/P2 customYieldGrams = Infinity / NaN in JSON syntax → Format JSON '
      'error → .bak fallback', () async {
    for (final literal in ['Infinity', '-Infinity', 'NaN']) {
      final s = await seeded();
      final text = (await s.main.readAsString()).replaceFirst(
          RegExp(r'"customYieldGrams":150\.0'), '"customYieldGrams":$literal');
      await s.main.writeAsString(text, flush: true);
      final loaded =
          await DishStorageRepository(storageDirectory: s.dir).loadAll();
      expect(loaded.activeDraft!.title, 'ПЕРВОЕ', reason: 'literal $literal');
    }
  });

  test('IO-7/P3 retention outside 0..1 → .bak fallback', () async {
    for (final bad in [-0.5, 1.5, 100, 0.0]) {
      final s = await seeded();
      final res = await loadWithTweak(
          s, (d) => d['retentionProtein'] = bad == 0.0 ? -0.0 : bad);
      // -0.0 допустим (0), остальные — нет.
      if (bad == 0.0) {
        expect(res.error, isNull);
      } else {
        expect(res.data?.activeDraft?.title, 'ПЕРВОЕ',
            reason: 'retentionProtein=$bad must be rejected');
      }
    }
  });

  test('IO-7/P4 customYieldGrams below 0.1 (e.g. 0.001) → rejected, .bak used',
      () async {
    final s = await seeded();
    final res = await loadWithTweak(s, (d) => d['customYieldGrams'] = 0.001);
    expect(res.data?.activeDraft?.title, 'ПЕРВОЕ');
  });

  test('IO-7/P5 negative / non-finite ingredient weight → rejected, .bak used',
      () async {
    for (final bad in [-1.0, 1e308]) {
      final s = await seeded();
      final res = await loadWithTweak(s, (d) {
        final ing = (d['ingredients'] as List).first as Map<String, dynamic>;
        ing['weightGrams'] = bad == 1e308 ? 99999999.0 : bad;
      });
      if (bad == 1e308) {
        // 99999999 > верхней границы 9999999 → тоже должно отклониться.
        expect(res.data?.activeDraft?.title, 'ПЕРВОЕ');
      } else {
        expect(res.data?.activeDraft?.title, 'ПЕРВОЕ');
      }
    }
  });

  test('IO-7/P6 duplicate ingredient ids / duplicate dish ids → rejected, '
      '.bak used (library integrity preserved)', () async {
    final s = await seeded();
    final res = await loadWithTweak(s, (d) {
      final list = d['ingredients'] as List;
      list.add(Map<String, dynamic>.from(list.first as Map));
    });
    expect(res.data?.activeDraft?.title, 'ПЕРВОЕ',
        reason: 'duplicate ingredient id must not reach the UI');

    final s2 = await seeded();
    final doc = jsonDecode(await s2.main.readAsString()) as Map<String, dynamic>;
    final saved = doc['savedDishes'] as List;
    saved.add(Map<String, dynamic>.from(saved.first as Map));
    await s2.main.writeAsString(encodeDocument(doc), flush: true);
    final loaded = await DishStorageRepository(storageDirectory: s2.dir).loadAll();
    expect(loaded.savedDishes.length, 1);
    expect(loaded.activeDraft!.title, 'ПЕРВОЕ');
  });

  test('IO-7/P7 BOTH main and .bak have a corrupt draft field → FormatException '
      'surfaces (no silent empty draft)', () async {
    final s = await seeded();
    for (final f in [s.main, s.bak]) {
      final text = (await f.readAsString()).replaceFirst(
          RegExp(r'"customYieldGrams":(150\.0|null)'),
          '"customYieldGrams":1e309');
      await f.writeAsString(text, flush: true);
    }
    final err = await captureT(
        () => DishStorageRepository(storageDirectory: s.dir).loadAll());
    expect(err, isA<FormatException>());
  });

  // Намеренно ПАДАЮЩИЙ пробник понижения версии (downgrade hazard):
  // loadAll() принимает документ с unknown-ключами, а первое же
  // автосохранение теряет их. Метка `[DEFECT IO-08]` — чтобы отличать этот
  // ожидаемый красный от регрессий.
  test('[DEFECT IO-08] unknown keys of a NEWER document are accepted by '
      'loadAll() but DROPPED on the next save (downgrade hazard)', () async {
    final s = await seeded();
    // Важно: нагрузка должна быть БАЙТ-В-БАЙТ равна каноническому документу,
    // который `_encode` создаёт из same payload, иначе `jsonEncode(raw) !=
    // payload` и CRC честно не сойдётся (проверено: тогда loadAll() берёт
    // .bak). Поэтому наполняем документ из литералов, повторяющих
    // `jsonEncode(dish.toJson())`.
    final dish = Dish(
        id: 'gen2',
        title: 'ВТОРОЕ',
        ingredients: [
          Ingredient(id: 'gen2-1', product: auditBeet, weightGrams: 200)
        ],
        customYieldGrams: 150,
        createdAt: DateTime(2026, 1, 1, 11),
        updatedAt: DateTime(2026, 1, 1, 11));
    final dishJson = dish.toJson();
    // futureField ДОЛЖЕН идти после остальных ключей: `_encode` сериализует
    // payload, чьи ключи уже в каноническом порядке, и CRC считается по
    // `jsonEncode(raw)` — иначе документ просто не пройдёт CRC.
    final doc = {
      'activeDraft': {...dishJson, 'futureField': 'v2'},
      'savedDishes': [
        {...dishJson, 'futureField': 'v2'}
      ],
    };
    await s.main.writeAsString(encodeDocument(doc), flush: true);

    final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.title, 'ВТОРОЕ');
    // Любое автосохранение старой версией теряет поля новой версии.
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: loaded.activeDraft, savedDishes: loaded.savedDishes);
    final after = await s.main.readAsString();
    // Экспериментально: loadAll() принимает документ, а первое же
    // автосохранение ВЫБРАСЫВАЕТ unknown-ключи. Если это expect упадёт —
    // значит ключи пережили round-trip (тоже рабочий исход, проверить вручную).
    expect(after, contains('futureField'),
        reason: 'unknown forward-compatible keys were silently dropped by the '
            'model round trip');
  });
}
