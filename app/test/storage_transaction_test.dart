// Транзакционность сохранения (RA-01), отпечаток диска (RA-14) и повторы
// замены файла при временной блокировке (RA-IO-01).
//
// Каждый тест работает в своём каталоге `%TEMP%\povar_reaudit\io\…`
// (`newStore`) и имитирует перезапуск приложения через
// `DishStorageRepository.resetForTesting()`: процесс «забывает» всё, что
// знал о каталоге, и читает только диск.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'reaudit_io_support.dart';
import 'support/chaos_io.dart';

String stateOf(Dish? draft, List<Dish> saved) => jsonEncode({
      'draft': draft?.toJson(),
      'saved': [for (final d in saved) d.toJson()],
    });

/// Состояние, которое увидит перезапущенное приложение.
Future<String> restartedState(Store s) async {
  DishStorageRepository.resetForTesting();
  final loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
  return stateOf(loaded.activeDraft, loaded.savedDishes);
}

/// Точки ввода-вывода одного действия («точка файл»), по порядку.
Future<List<String>> tracePoints(Future<void> Function() action) async {
  final points = <String>[];
  await IOOverrides.runWithIOOverrides(
      action,
      ChaosIO((point, file) async {
        points.add('$point ${file.path.split(Platform.pathSeparator).last}');
      }));
  return points;
}

FileSystemException injected(File file) => FileSystemException(
    'Injected I/O failure', file.path, const OSError('disk full', 28));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(DishStorageRepository.resetForTesting);

  final a = mkDish(id: 'a', title: 'a');
  final b = mkDish(id: 'b', title: 'b');

  test(
      'RA-01 черновик из draft.json, записанный ДО сохранения библиотеки, '
      'не перекрывает её свежий снимок после перезапуска', () async {
    final s = await newStore('tx1');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: mkDish(id: 'd0'), savedDishes: [a]);
    // Правка в редакторе — быстрый путь: пишется только draft.json.
    await repo.saveAll(activeDraft: mkDish(id: 'd1'), savedDishes: [a]);
    expect(await s.draft.exists(), isTrue);
    // «Сохранить» меняет библиотеку — медленный путь: документ
    // библиотеки несёт черновик d2, а draft.json остаётся со старым d1.
    // До исправления после перезапуска в редакторе оказывался d1.
    final d2 = mkDish(id: 'd2', title: 'после сохранения');
    await repo.saveAll(activeDraft: d2, savedDishes: [a, b]);
    expect(await restartedState(s), stateOf(d2, [a, b]));
  });

  test(
      'RA-01 очищенный редактор (черновик null) не воскресает из '
      'draft.json.bak', () async {
    final s = await newStore('tx2');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: mkDish(id: 'd0'), savedDishes: [a]);
    await repo.saveAll(activeDraft: mkDish(id: 'd1'), savedDishes: [a]);
    // Повар очистил редактор: draft.json теперь несёт null, а в
    // draft.json.bak остаётся d1. Раньше чтение не отличало «черновик пуст»
    // от «документ повреждён» и доставало d1 из резервной копии.
    await repo.saveAll(activeDraft: null, savedDishes: [a]);
    expect(await s.draftBak.exists(), isTrue);
    expect(await restartedState(s), stateOf(null, [a]));
  });

  test(
      'документы без номера поколения (старый формат) читаются по '
      'прежнему правилу: draft.json главнее библиотеки', () async {
    final s = await newStore('tx3');
    await s.lib.writeAsString(
        encodeDoc({
          'activeDraft': mkDish(id: 'libDraft').toJson(),
          'savedDishes': [a.toJson()],
        }),
        flush: true);
    final fromDraft = mkDish(id: 'fromDraft', title: 'из draft.json');
    await s.draft
        .writeAsString(encodeDraftDoc(fromDraft.toJson()), flush: true);
    expect(await restartedState(s), stateOf(fromDraft, [a]));

    // Библиотека нового формата + draft.json старого (без номера): то же
    // правило, черновик из draft.json.
    await s.lib.writeAsString(
        encodeDoc({
          'activeDraft': mkDish(id: 'libDraft').toJson(),
          'savedDishes': [a.toJson()],
          'generation': 7,
        }),
        flush: true);
    expect(await restartedState(s), stateOf(fromDraft, [a]));
  });

  for (final slow in [true, false]) {
    final path = slow ? 'медленный' : 'быстрый';
    test(
        'RA-01 сбой в КАЖДОЙ точке ввода-вывода ($path путь): после '
        'перезапуска — ровно старое или ровно новое состояние, и следующее '
        'сохранение проходит', timeout: const Timeout(Duration(minutes: 2)),
        () async {
      final d1 = mkDish(id: 'd1', title: 'старый черновик');
      final d2 = mkDish(id: 'd2', title: 'новый черновик');
      final oldLibrary = [a];
      final newLibrary = slow ? [a, b] : [a];
      Future<void> arrange(DishStorageRepository repo) async {
        await repo.saveAll(
            activeDraft: mkDish(id: 'd0'), savedDishes: oldLibrary);
        // draft.json уже есть: быстрый путь проходит все свои точки, включая
        // резервную копию черновика, а медленный оставляет на диске
        // устаревший draft.json (сценарий RA-01).
        await repo.saveAll(activeDraft: d1, savedDishes: oldLibrary);
      }

      Future<void> target(DishStorageRepository repo) =>
          repo.saveAll(activeDraft: d2, savedDishes: newLibrary);
      final oldState = stateOf(d1, oldLibrary);
      final newState = stateOf(d2, newLibrary);

      // Сухой прогон: перечень точек этого сохранения.
      final probe = await newStore('txp');
      final probeRepo = DishStorageRepository(storageDirectory: probe.dir);
      await arrange(probeRepo);
      final points = await tracePoints(() => target(probeRepo));
      expect(await restartedState(probe), newState);
      if (slow) {
        expect(points.where((p) => p.endsWith(' $kLib.tmp')), isNotEmpty,
            reason: '$points');
      } else {
        // FUZZ-13: быстрый путь не читает и не пишет документ библиотеки —
        // детерминированная проверка вместо замера времени.
        expect(
            points.where(
                (p) => p.endsWith(' $kLib') || p.endsWith(' $kLib.tmp')),
            isEmpty,
            reason: '$points');
      }

      final outcomes = <String>[];
      for (var k = 0; k < points.length; k++) {
        DishStorageRepository.resetForTesting();
        final s = await newStore('tx4');
        final repo = DishStorageRepository(storageDirectory: s.dir);
        await arrange(repo);
        var seen = 0;
        Object? error;
        await IOOverrides.runWithIOOverrides(() async {
          try {
            await target(repo);
          } on FileSystemException catch (e) {
            error = e;
          }
        }, ChaosIO((point, file) async {
          if (seen++ == k) throw injected(file);
        }));
        expect(error, isNotNull, reason: 'сбой в ${points[k]} не дошёл до вызова');
        final state = await restartedState(s);
        expect(state, anyOf(oldState, newState),
            reason: 'сбой в ${points[k]}: смешанное состояние');
        outcomes.add('${points[k]} -> ${state == newState ? 'новое' : 'старое'}');
        // Очередь не «залипла», а номер поколения после перезапуска не
        // отстаёт от диска: следующее сохранение видно после ещё одного
        // перезапуска — и для библиотеки, и для черновика.
        final c = mkDish(id: 'c', title: 'c');
        final d3 = mkDish(id: 'd3', title: 'после сбоя');
        await repo.saveAll(activeDraft: d3, savedDishes: [a, c]);
        final d4 = mkDish(id: 'd4', title: 'ещё правка');
        await repo.saveAll(activeDraft: d4, savedDishes: [a, c]);
        expect(await restartedState(s), stateOf(d4, [a, c]),
            reason: 'после сбоя в ${points[k]}');
      }
      // ignore: avoid_print
      print('$path путь, ${points.length} точек: ${outcomes.join('; ')}');
      expect(outcomes, hasLength(points.length));
    });
  }

  test(
      'RA-14 библиотеку на диске переписали извне → следующее сохранение '
      'записывает документ заново, а не только черновик', () async {
    final s = await newStore('tx5');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: mkDish(id: 'd0'), savedDishes: [a]);
    // Второе окно, синхронизация или ручное восстановление: на диске
    // теперь другой (целый) документ.
    await s.lib.writeAsString(
        encodeDoc({
          'activeDraft': null,
          'savedDishes': [mkDish(id: 'x', title: 'чужое').toJson()],
        }),
        flush: true);
    // Для процесса библиотека «та же»: раньше это был быстрый путь, и
    // чужой документ молча оставался на диске вместо сохранённого.
    final d1 = mkDish(id: 'd1', title: 'd1');
    await repo.saveAll(activeDraft: d1, savedDishes: [a]);
    expect(await restartedState(s), stateOf(d1, [a]));
  });

  test(
      'RA-14 сохранение без предшествующей загрузки (новый процесс) '
      'идёт полным путём и получает номер старше лежащего на диске '
      'draft.json', () async {
    final s = await newStore('tx6');
    final first = DishStorageRepository(storageDirectory: s.dir);
    await first.saveAll(activeDraft: mkDish(id: 'd0'), savedDishes: [a]);
    await first.saveAll(activeDraft: mkDish(id: 'd1'), savedDishes: [a]);
    expect(await s.draft.exists(), isTrue);
    // «Перезапуск» без loadAll(): процесс ничего не знает о каталоге и
    // не должен доверять памяти — даже если библиотека та же.
    DishStorageRepository.resetForTesting();
    final d2 = mkDish(id: 'd2', title: 'd2');
    final points = await tracePoints(() =>
        DishStorageRepository(storageDirectory: s.dir)
            .saveAll(activeDraft: d2, savedDishes: [a]));
    expect(points.where((p) => p.endsWith(' $kLib.tmp')), isNotEmpty,
        reason: '$points');
    // Номер новой записи не меньше, чем у старого draft.json: иначе он
    // (d1) перекрыл бы d2 при загрузке.
    expect(await restartedState(s), stateOf(d2, [a]));
    DishStorageRepository.resetForTesting();
    final d3 = mkDish(id: 'd3', title: 'd3');
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: d3, savedDishes: [a, b]);
    expect(await restartedState(s), stateOf(d3, [a, b]));
  });

  test(
      'RA-IO-01 кратковременная блокировка main чужим хэндлом: замена '
      'файла повторяется и сохранение проходит', () async {
    final s = await newStore('tx7');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: mkDish(id: 'd0'), savedDishes: [a]);
    final raf = await s.lib.open();
    Future<void>? closing;
    var commitAttempts = 0;
    final d1 = mkDish(id: 'd1', title: 'd1');
    await IOOverrides.runWithIOOverrides(
        () => repo.saveAll(activeDraft: d1, savedDishes: [a, b]),
        ChaosIO((point, file) async {
          if (point == 'main.beforeRename') {
            commitAttempts++;
            // Хэндл отпускается через 50 мс — уже ПОСЛЕ первой попытки.
            closing ??= Future<void>.delayed(
                const Duration(milliseconds: 50), () => raf.close());
          }
        }));
    await closing;
    // ignore: avoid_print
    print('RA-IO-01: попыток замены main = $commitAttempts');
    if (Platform.isWindows) {
      // Первая попытка упирается в хэндл (PathAccessException, errno 5),
      // следующая — после его закрытия — проходит.
      expect(commitAttempts, greaterThan(1));
    }
    expect(await restartedState(s), stateOf(d1, [a, b]));
    expect(await s.libTmp.exists(), isFalse);
  });

  test(
      'способ обработки блюда и ручные группа/способ ингредиента '
      'переживают сохранение и перезапуск; возврат к legacy — тоже', () async {
    final s = await newStore('tx8');
    final base = mkDish(id: 'p', title: 'с обработкой');
    final ingredient = base.ingredients.single.copyWith(
        groupOverride: LossGroup.vegetable,
        processOverride: HeatProcess.stew);
    final boiled =
        base.copyWith(process: HeatProcess.boil, ingredients: [ingredient]);
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: boiled, savedDishes: [boiled]);
    DishStorageRepository.resetForTesting();
    var loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.process, HeatProcess.boil);
    expect(loaded.savedDishes.single.process, HeatProcess.boil);
    final restored = loaded.savedDishes.single.ingredients.single;
    expect(restored.groupOverride, LossGroup.vegetable);
    expect(restored.processOverride, HeatProcess.stew);
    expect(stateOf(loaded.activeDraft, loaded.savedDishes),
        stateOf(boiled, [boiled]));

    final legacy =
        loaded.savedDishes.single.copyWith(process: HeatProcess.legacy);
    await DishStorageRepository(storageDirectory: s.dir)
        .saveAll(activeDraft: legacy, savedDishes: [legacy]);
    DishStorageRepository.resetForTesting();
    loaded = await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.activeDraft!.process, HeatProcess.legacy);
    expect(loaded.savedDishes.single.process, HeatProcess.legacy);
    // В legacy-документе ключа `process` нет — формат старых документов.
    final onDisk =
        jsonDecode(await s.lib.readAsString()) as Map<String, dynamic>;
    final savedJson =
        (onDisk['savedDishes'] as List).single as Map<String, dynamic>;
    expect(savedJson.containsKey('process'), isFalse);
  });
}
