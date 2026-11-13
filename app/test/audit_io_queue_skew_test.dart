// Аудит персистентности, пункт 6+5 (дополнительно по запросу parent):
// `SavedDishesNotifier.updateDraftReference` передаёт ЖИВОЙ `state`, а у
// `SavedDishesNotifier` свой `_operationTail`, у `DishNotifier` — свой
// `_saveQueue`. Проверяем, возможно ли, что на диске оказывается устаревший
// draft ИЛИ устаревшая библиотека (потеря последней правки) при чередовании
// saveDish()/deleteDish()/updateDraftReference()/saveCurrentToLibrary().
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('IO-6/D-IO10 probe A: interleaved saveDish/deleteDish/'
      'updateDraftReference without awaiting — FINAL draft on disk is an '
      'OLDER draft than the last one passed in', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    addTearDown(saved.dispose);

    // Чередование «без await»: как три независимых обработчика UI.
    final f = <Future<Object?>>[];
    f.add(saved.updateDraftReference(auditDish(1, title: 'draft 1')));
    f.add(saved.saveDish(auditDish(10, id: 'a', title: 'A')));
    f.add(saved.updateDraftReference(auditDish(2, title: 'draft 2')));
    f.add(saved.deleteDish('a'));
    f.add(saved.updateDraftReference(auditDish(3, title: 'draft 3')));
    f.add(saved.saveDish(auditDish(20, id: 'b', title: 'B')));
    f.add(saved.updateDraftReference(auditDish(4, title: 'draft 4')));
    await Future.wait(f);

    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    // Ожидание: последний вызов updateDraftReference(draft 4) + полная
    // библиотека (['b']). Ниже — что реально на диске.
    expect(disk.activeDraft!.title, 'draft 4',
        reason: 'stale draft on disk (${disk.activeDraft!.title})');
    expect(disk.savedDishes.map((d) => d.id).toList(), ['b'],
        reason: 'stale library on disk '
            '(${disk.savedDishes.map((d) => d.id).toList()})');
  });

  test('IO-6/D-IO10 probe B: TWO SEPARATE _tail chains (DishNotifier._saveQueue '
      '→ updateDraftReference + direct saveDish) interleave so an OLD draft '
      'overwrites a NEWER one on disk', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    final dish = DishNotifier(storage: repo, savedDishesNotifier: saved);
    addTearDown(() {
      dish.dispose();
      saved.dispose();
    });

    // Цепочка 1: автосохранение черновика (DishNotifier._saveQueue).
    // Цепочка 2: сохранение в библиотеку (SavedDishesNotifier._operationTail).
    dish.setTitle('новая правка');
    final lib = dish.saveCurrentToLibrary();
    dish.addIngredient(auditBeet, 100);
    dish.setTitle('самая новая правка');
    await lib;
    await dish.flushPendingSaves();

    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(disk.activeDraft!.title, 'самая новая правка',
        reason: 'stale draft "${disk.activeDraft!.title}" persisted');
  });

  test('IO-6/D-IO10 probe C: `state` is a live list — a save queued BEFORE a '
      'library mutation serializes the MUTATED list (read/write skew)',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final saved = SavedDishesNotifier(repo);
    addTearDown(saved.dispose);
    await saved.saveDish(auditDish(10, id: 'old', title: 'old'));

    // Вызываем updateDraftReference несколько раз без await, одновременно
    // мутируя библиотеку: каждый save в цепочке увидит состояние НА МОМЕНТ
    // ИСПОЛНЕНИЯ, а не на момент вызова.
    final order = <String>[];
    final a = saved
        .updateDraftReference(auditDish(1, title: 'd1'))
        .then((_) => order.add('d1'));
    final b = saved.saveDish(auditDish(20, id: 'new', title: 'new'))
        .then((_) => order.add('save new'));
    final c = saved
        .updateDraftReference(auditDish(2, title: 'd2'))
        .then((_) => order.add('d2'));
    await Future.wait([a, b, c]);

    // state ПОСЛЕ всех операций: ['new', 'old'].
    expect(saved.state.map((d) => d.id).toList(), ['new', 'old']);
    final disk = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    // main = последняя операция (d2) — она должна нести ОБЕ записи.
    expect(disk.savedDishes.map((d) => d.id).toList(), ['new', 'old'],
        reason: 'library record lost: ${disk.savedDishes.map((d) => d.id)}');
    expect(disk.activeDraft!.title, 'd2');
    // FUZZ-13: библиотека и черновик — разные документы. Поколение `.bak`
    // несёт ТОЛЬКО библиотеку (`activeDraft` там null: последнее сохранение
    // библиотеки произошло до первого черновика), а сам черновик живёт в
    // `draft.json` со своей резервной копией. Главное — что при перезапуске
    // восстанавливается d2 и обе записи библиотеки.
    final bak = jsonDecode(await s.bak.readAsString()) as Map<String, dynamic>;
    expect(bak['activeDraft'], isNull,
        reason: 'документ библиотеки больше не дублирует черновик');
    expect((bak['savedDishes'] as List).map((e) => (e as Map)['id']).toList(),
        ['old'],
        reason: 'резервная копия — поколение ДО добавления new');
    final draftDoc =
        jsonDecode(await File('${s.main.path}.draft.json').readAsString())
            as Map<String, dynamic>;
    expect((draftDoc['activeDraft'] as Map)['title'], 'd2',
        reason: 'последний черновик сохранён отдельным документом');
    expect(order, ['d1', 'save new', 'd2']);
  });
}
