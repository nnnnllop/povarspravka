// ПОВТОРНЫЙ АУДИТ — пункт 1: атомарность каждого файла схемы
// (библиотека `povarspravka_user_dishes.json` и черновик
// `povarspravka_user_dishes.json.draft.json`).
//
// Метод: конкурентный читатель открывает и читает файл вне очереди записи
// репозитория во время ≥100 сохранений и проверяет, что каждый увиденный
// снимок байт — целый документ (валидный JSON + верный CRC-32), а не раз.
//
// ВАЖНО (Windows): открытый на чтение хэндл БЛОКИРУЕТ `File.rename` над
// целью (PathAccessException errno=5), поэтому «чистую» атомарность
// измеряем в A1 (читатель аккуратно отпускает хэндл между чтениями), а
// РЕАЛЬНУЮ конкуренцию читатель↔запись — в A2 (наивный читатель / второе
// приложение) и фиксируем отказы записи как находку RA-IO-01.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'reaudit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A1 main: 150 сохранений, читатель отпускает хэндл — ни одного '
      'порванного/чужого снимка',
      // 150 реальных транзакций draft+library на диске при аккуратном
      // читателе (пауза 1 мс между чтениями): время зависит от машины
      // (в прогоне c=1 ≈ 43 с). Это тест корректности, а не скорости
      // (см. RA-16), поэтому бюджет как у A4.
      timeout: const Timeout(Duration(minutes: 3)), () async {
    final s = await newStore('at1');
    final repo = DishStorageRepository(storageDirectory: s.dir);

    Future<void> saveGen(int n) => repo.saveAll(
          activeDraft: mkDish(id: 'd$n', title: 'черновик $n', grams: 100.0 + n),
          savedDishes: [mkDish(id: 'a$n', title: 'блюдо $n', grams: 50.0 + n)],
        );

    await saveGen(0);

    final seen = <String>{};
    final bad = <String>[];
    var reads = 0;
    var empty = 0;
    var vanished = 0;
    var reading = true;

    Future<void> reader() async {
      while (reading) {
        try {
          final bytes = await s.lib.readAsBytes();
          reads++;
          if (bytes.isEmpty) {
            empty++;
            continue;
          }
          final (ok, why) = verifyLibrarySnapshot(bytes);
          if (ok) {
            seen.add('${bytes.length}:${String.fromCharCodes(bytes)}');
          } else if (bad.length < 8) {
            bad.add('read#$reads -> $why');
          }
          // Аккуратный читатель («правильное» поведение читателя):
          // даём писателю шанс на атомарный rename. `Duration.zero` такого
          // шанса не даёт: на быстром диске читатель снова открывает
          // файл раньше, чем Windows выполнит замену, и всё бюджетное
          // время повторов цель занята (так ведёт себя наивный читатель
          // из A6, а не аккуратный). Пауза 1 мс — то самое «отпускает
          // хэндл» из названия теста; проверки целостности не менялись.
          await Future<void>.delayed(const Duration(milliseconds: 1));
        } on PathNotFoundException {
          vanished++;
        } on FileSystemException {
          // занят писателем — повторим
        }
      }
    }

    final r = reader();
    var saveErrors = 0;
    for (var i = 1; i <= 150; i++) {
      try {
        await saveGen(i);
      } on FileSystemException {
        saveErrors++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await saveGen(i);
      }
    }
    reading = false;
    await r;

    // ignore: avoid_print
    print('A1: iterations=150 reads=$reads distinctValid=${seen.length} '
        'empty=$empty vanished=$vanished saveRetries=$saveErrors '
        'bad=${bad.length} ${bad.join(' | ')}');

    expect(bad, isEmpty, reason: 'порванный снимок виден читателю');
    expect(empty, 0, reason: 'пустой файл виден читателю');
    expect(vanished, 0, reason: 'файл пропадал на время смены поколения');
    expect(reads, greaterThanOrEqualTo(100));
    final loaded =
        await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.single.id, 'a150');
    expect(loaded.activeDraft!.id, 'd150');
  });

  // RA-15: прежняя версия A2 ТРЕБОВАЛА дефекта (`failed > 0`) и падала бы на
  // любом исправлении. Теперь она проверяет исправление RA-IO-01 строже:
  // читатель держит ОБА файла схемы, сохранения чередуют медленный
  // (библиотека) и быстрый (только черновик) пути, и ни одно не отказывает,
  // ни один снимок не порван, а честный «перезапуск» видит последнее
  // сохранение.
  test('A2 [RA-IO-01 закрыт] наивный читатель main и draft.json (второе '
      'приложение/бэкап, без пауз) → ни одного отказа записи, порванного '
      'снимка или потерянного сохранения', () async {
    final s = await newStore('at2');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    var library = [mkDish(id: 'a0', title: 'a0')];
    var draft = mkDish(id: 'd0', title: 'd0');
    await repo.saveAll(activeDraft: draft, savedDishes: library);
    // Второе сохранение меняет только черновик (быстрый путь) и создаёт
    // draft.json: дальше оба файла схемы существуют всё время.
    draft = mkDish(id: 'd0b', title: 'd0b');
    await repo.saveAll(activeDraft: draft, savedDishes: library);
    expect(await s.draft.exists(), isTrue);

    final bad = <String>[];
    var reading = true;
    var libReads = 0;
    var draftReads = 0;
    Future<void> reader() async {
      while (reading) {
        try {
          final bytes = await s.lib.readAsBytes();
          libReads++;
          final (ok, why) = verifyLibrarySnapshot(bytes);
          if (!ok) bad.add('main:$why');
        } on PathNotFoundException {
          bad.add('main:missing');
        } on FileSystemException {
          // занят
        }
        try {
          final bytes = await s.draft.readAsBytes();
          draftReads++;
          final (ok, why) = verifyDraftSnapshot(bytes);
          if (!ok) bad.add('draft:$why');
        } on PathNotFoundException {
          bad.add('draft:missing');
        } on FileSystemException {
          // занят
        }
      }
    }

    final r = reader();
    var failed = 0;
    final codes = <int?>{};
    for (var i = 1; i <= 60; i++) {
      // Нечётные шаги меняют библиотеку (медленный путь: main и .bak),
      // чётные — только черновик (быстрый путь: draft.json и его .bak).
      if (i.isOdd) library = [mkDish(id: 'a$i', title: 'блюдо $i')];
      draft = mkDish(id: 'd$i', title: 'черновик $i');
      try {
        await repo.saveAll(activeDraft: draft, savedDishes: library);
      } on FileSystemException catch (e) {
        failed++;
        codes.add(e.osError?.errorCode);
      }
    }
    reading = false;
    await r;

    // ignore: avoid_print
    print('A2: saves=60 failed=$failed osCodes=$codes libReads=$libReads '
        'draftReads=$draftReads tornSnapshots=${bad.length} ${bad.take(5)}');
    expect(bad, isEmpty, reason: 'порванный или пропавший снимок');
    expect(failed, 0,
        reason: 'запись отказала под конкурентным читателем: osCodes=$codes');
    expect(libReads, greaterThan(0));
    expect(draftReads, greaterThan(0));

    // Честный «перезапуск»: процесс не помнит ничего о каталоге.
    DishStorageRepository.resetForTesting();
    final loaded =
        await DishStorageRepository(storageDirectory: s.dir).loadAll();
    expect(loaded.savedDishes.single.id, library.single.id);
    expect(loaded.activeDraft!.id, draft.id);
  });

  test('A3 нет накопления .tmp/.bak.tmp: после 150 смешанных сохранений не '
      'остаётся временных файлов', () async {
    final s = await newStore('at3');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    for (var i = 0; i < 75; i++) {
      await repo.saveAll(
          activeDraft: mkDish(id: 'd$i', title: 'd$i'),
          savedDishes: [mkDish(id: 'l$i', title: 'l$i')]);
      await repo.saveAll(
          activeDraft: mkDish(id: 'd$i-b', title: 'd$i-b'),
          savedDishes: [mkDish(id: 'l$i', title: 'l$i')]);
    }
    final names = s.namesSync();
    // ignore: avoid_print
    print('A3: files=$names');
    expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    expect(names, containsAll([kLib, kDraft]));
  });

  // Нагрузочный тест: 120 полных сохранений с fsync при аккуратном читателе
  // (пауза 1 мс между чтениями, см. цикл читателя ниже). Его длительность —
  // свойство диска и конкуренции с читателем, а не проверяемое свойство: в
  // базовом прогоне он не укладывался в стандартные 30 с. Бюджет задан явно;
  // проверка целостности не менялась.
  test('A4 120 правок крупной библиотеки (40 блюд x 6 ингредиентов) — '
      'читатель не видит порванного main',
      timeout: const Timeout(Duration(minutes: 3)), () async {
    final s = await newStore('at4');
    final big = [
      for (var i = 0; i < 40; i++)
        mkDish(id: 'b$i', title: 'Блюдо №$i', substitutes: 5)
    ];
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(activeDraft: big.first, savedDishes: big);

    final bad = <String>[];
    var reading = true;
    var reads = 0;
    Future<void> reader() async {
      while (reading) {
        try {
          final bytes = await s.lib.readAsBytes();
          reads++;
          final (ok, why) = verifyLibrarySnapshot(bytes);
          if (!ok) bad.add(why);
          // Как в A1: аккуратный читатель отпускает хэндл на 1 мс.
          await Future<void>.delayed(const Duration(milliseconds: 1));
        } on PathNotFoundException {
          bad.add('missing');
        } on FileSystemException {
          // busy-on-rename
        }
      }
    }

    final r = reader();
    var retries = 0;
    for (var i = 0; i < 120; i++) {
      final mut = [
        for (var j = 0; j < big.length; j++)
          big[j].copyWith(title: 'Блюдо №$j (правка $i)')
      ];
      while (true) {
        try {
          await repo.saveAll(activeDraft: mut.first, savedDishes: mut);
          break;
        } on FileSystemException {
          retries++;
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }
    }
    reading = false;
    await r;
    // ignore: avoid_print
    print('A4: iterations=120 reads=$reads saveRetries=$retries '
        'bad=${bad.length} ${bad.take(5)}');
    expect(bad, isEmpty);
  });

  test('A5 ОС-семантика: read-хэндл на цели блокирует rename, после закрытия — '
      'первая попытка', () async {
    final s = await newStore('at5');
    await s.lib.writeAsString('A' * 100000, flush: true);
    final whileOpen = <String>[];
    var afterCloseFirstTry = 0;
    for (var i = 0; i < 10; i++) {
      final raf = await s.lib.open();
      final t = s.f('x$i.tmp');
      await t.writeAsString('B' * 100000, flush: true);
      try {
        await t.rename(s.lib.path);
        whileOpen.add('ok');
      } on FileSystemException catch (e) {
        whileOpen.add('fail(${e.osError?.errorCode})');
      }
      await raf.close();
      try {
        await t.rename(s.lib.path);
        afterCloseFirstTry++;
      } on FileSystemException {
        // не сработало с первого раза
      }
    }
    // ignore: avoid_print
    print('A5: renameWhileHandleOpen=$whileOpen '
        'afterCloseFirstTry=$afterCloseFirstTry/10');
    expect(whileOpen.every((e) => e.startsWith('fail')), isTrue,
        reason: 'ожидание: открытый read-хэндл блокирует rename на Windows');
    expect(afterCloseFirstTry, 10);
  });

  // RA-IO-01: кратковременную блокировку репозиторий пережидает повторами
  // `rename`; здесь хэндл держится ДОЛЬШЕ бюджета повторов, и тест
  // проверяет безопасный отказ: ошибка видна вызывающему, main цел.
  test('A6 [RA-IO-01] хэндл на main держится дольше бюджета повторов → '
      'saveAll падает PathAccessException(5); старый main цел, .tmp '
      'остаётся', () async {
    final s = await newStore('at6');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    await repo.saveAll(
        activeDraft: mkDish(id: 'g1', title: 'поколение 1'),
        savedDishes: [mkDish(id: 'g1', title: 'поколение 1')]);
    final raf = await s.lib.open();
    final before = await s.lib.readAsBytes();
    Object? err;
    try {
      await repo.saveAll(
          activeDraft: mkDish(id: 'g2', title: 'поколение 2'),
          savedDishes: [mkDish(id: 'g2', title: 'поколение 2')]);
    } on Object catch (e) {
      err = e;
    }
    await raf.close();
    // ignore: avoid_print
    print('A6: error=${errLabel(err)} mainUnchanged='
        '${bytesEqual(before, await s.lib.readAsBytes())} '
        'files=${s.namesSync()}');
    expect(err, isA<FileSystemException>());
    expect(bytesEqual(before, await s.lib.readAsBytes()), isTrue);
    expect(await s.libTmp.exists(), isTrue,
        reason: 'после отказа .tmp остаётся на диске');
  });

  test('A7 [RA-IO-01] хэндл на draft.json держится дольше бюджета повторов '
      '→ сохранение черновика падает, новый ввод на диск не попал', () async {
    final s = await newStore('at7');
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final lib = [mkDish(id: 'lib', title: 'lib')];
    // Первое сохранение — медленный путь (отпечатка библиотеки ещё нет):
    // оно пишет только документ библиотеки вместе с черновиком. DRAFT
    // создаёт второе — быстрый путь (изменился только черновик). Прежняя
    // подготовка считала, что DRAFT создаёт уже первое сохранение, и падала
    // на предусловии, не дойдя до проверяемого свойства.
    await repo.saveAll(
        activeDraft: mkDish(id: 'd0', title: 'd0'), savedDishes: lib);
    await repo.saveAll(
        activeDraft: mkDish(id: 'd1', title: 'd1'), savedDishes: lib);
    expect(await s.draft.exists(), isTrue);

    final raf = await s.draft.open();
    Object? err;
    try {
      await repo.saveAll(
          activeDraft: mkDish(id: 'd2', title: 'd2'), savedDishes: lib);
    } on Object catch (e) {
      err = e;
    }
    await raf.close();
    final onDisk = await s.draft.readAsString();
    // ignore: avoid_print
    print('A7: error=${errLabel(err)} onDiskHasD1=${onDisk.contains('"d1"')} '
        'onDiskHasD2=${onDisk.contains('"d2"')} files=${s.namesSync()}');
    expect(err, isA<FileSystemException>());
    expect(onDisk.contains('"d2"'), isFalse);
  });
}
