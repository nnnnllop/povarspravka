// ПОВТОРНЫЙ АУДИТ — пункт 10: масштаб и производительность схемы
// «два документа» на 1000 блюд × 100 ингредиентов.
//
// Измеряем: размер файлов, время сохранения библиотеки, время сохранения
// черновика (быстрый путь FUZZ-13), время загрузки, пиковый RSS.
// Запуск: flutter test test/reaudit_io_perf_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'reaudit_io_support.dart';

List<Dish> buildLibrary(int dishes, int ings, {int salt = 0}) {
  final list = <Dish>[];
  for (var d = 0; d < dishes; d++) {
    final ing = <Ingredient>[];
    for (var i = 0; i < ings; i++) {
      ing.add(Ingredient(
        id: 'd$d-i$i',
        weightGrams: 10.0 + ((i + salt) % 50),
        isGross: i.isOdd,
        product: Product(
          id: 1000 + i,
          code: '${1000 + i}',
          name: 'Продукт $i',
          groupId: 1 + (i % 12),
          source: i.isEven ? 'skurikhin' : 'bls',
          wastePct: (i % 7) * 1.5,
          protein: 1.0 + (i % 10),
          fat: 0.5 + (i % 7),
          carbs: 2.0 + (i % 20),
          kcal: 50.0 + (i % 90),
          water: 60.0,
        ),
      ));
    }
    list.add(Dish(
      id: 'd$d',
      title: 'Блюдо номер $d (соль $salt)',
      ingredients: ing,
      customYieldGrams: 100.0 + d,
      retentionProtein: 0.94,
      retentionFat: 0.88,
      retentionCarbs: 0.91,
      createdAt: DateTime.utc(2026, 1, 1, 0, 0, d % 60),
      updatedAt: DateTime.utc(2026, 1, 1, 0, 0, d % 60),
    ));
  }
  return list;
}

String kb(int n) => '${(n / 1024).toStringAsFixed(1)} KiB';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PERF 1000 блюд × 100 ингредиентов', () async {
    final sw = Stopwatch();
    final rss0 = ProcessInfo.currentRss;

    sw.start();
    final lib = buildLibrary(1000, 100);
    sw.stop();
    final buildMs = sw.elapsedMilliseconds;
    final rssBuilt = ProcessInfo.currentRss;

    final s = await newStore('perf');
    final repo = DishStorageRepository(storageDirectory: s.dir);

    // Итерация 1: библиотека + черновик (медленный путь).
    sw
      ..reset()
      ..start();
    await repo.saveAll(activeDraft: lib.first, savedDishes: lib);
    sw.stop();
    final slowSaveMs = sw.elapsedMilliseconds;
    final libSize = await s.lib.length();
    final bakSize = await s.libBak.length();
    // Медленный путь пишет черновик в документ библиотеки; draft.json
    // появляется только на быстром пути (RA-01), поэтому здесь его может не
    // быть. Раньше вызов `length()` на отсутствующем файле ронял замер.
    final draftSize1 = await s.draft.exists() ? await s.draft.length() : 0;

    // Быстрый путь: меняется только черновик (библиотека — те же объекты).
    final fast = <int>[];
    for (var i = 0; i < 20; i++) {
      sw
        ..reset()
        ..start();
      await repo.saveAll(
          activeDraft: lib.first.copyWith(title: 'Правка $i'),
          savedDishes: lib);
      sw.stop();
      fast.add(sw.elapsedMicroseconds);
    }
    final rssFast = ProcessInfo.currentRss;

    // Загрузка в НОВЫЙ репозиторий.
    final reader = DishStorageRepository(storageDirectory: s.dir);
    sw
      ..reset()
      ..start();
    final loaded = await reader.loadAll();
    sw.stop();
    final loadMs = sw.elapsedMilliseconds;
    final rssLoad = ProcessInfo.currentRss;

    // Полный цикл в новый каталог (как «сохранить как», худший случай).
    final s2 = await newStore('perf2');
    final repo2 = DishStorageRepository(storageDirectory: s2.dir);
    sw
      ..reset()
      ..start();
    await repo2.saveAll(
        activeDraft: loaded.savedDishes.first, savedDishes: loaded.savedDishes);
    sw.stop();
    final saveLoadedMs = sw.elapsedMilliseconds;

    fast.sort();
    final rep = StringBuffer()
      ..writeln('PERF count=${loaded.savedDishes.length} '
          'ingsPerDish=${loaded.savedDishes.first.ingredients.length}')
      ..writeln('  lib bytes=$libSize (${kb(libSize)})  bak=$bakSize '
          '(${kb(bakSize)})  draft(after fast path)='
          '${await s.draft.length()} (${kb(await s.draft.length())})'
          '  draft(initial)=$draftSize1 (${kb(draftSize1)})')
      ..writeln('  build model: ${buildMs} ms')
      ..writeln('  save lib+draft (slow path): ${slowSaveMs} ms')
      ..writeln('  save draft only (fast path) n=20: '
          'min=${(fast.first / 1000).toStringAsFixed(2)} ms '
          'median=${(fast[fast.length ~/ 2] / 1000).toStringAsFixed(2)} ms '
          'p95=${(fast[(fast.length * 95) ~/ 100] / 1000).toStringAsFixed(2)} ms '
          'max=${(fast.last / 1000).toStringAsFixed(2)} ms')
      ..writeln('  load from disk (new instance): $loadMs ms')
      ..writeln('  re-save loaded library: $saveLoadedMs ms')
      ..writeln('  RSS start=${kb(rss0)} built=${kb(rssBuilt)} '
          'afterFast=${kb(rssFast)} afterLoad=${kb(rssLoad)} '
          'delta=${kb(rssLoad - rss0)}');
    File('${kScratchRoot.path}${Platform.pathSeparator}perf.txt')
        .writeAsStringSync(rep.toString());
    // ignore: avoid_print
    print(rep.toString());

    expect(loaded.savedDishes.length, 1000);
    expect(loaded.savedDishes.first.ingredients.length, 100);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
