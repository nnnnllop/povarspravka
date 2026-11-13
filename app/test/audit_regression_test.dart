import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'support/test_artifacts.dart';

Dish fixture(int n, {BlankMode mode = BlankMode.photoCross}) => Dish(
      id: 'audit',
      title: 'Аудит экспорта: $n ингредиентов',
      showTitleInExport: true,
      showPer100gRowInExport: true,
      blankMode: mode,
      retentionProtein: 0.9456,
      retentionFat: 0.8812,
      retentionCarbs: 0.9134,
      createdAt: DateTime(2026, 10, 16),
      updatedAt: DateTime(2026, 10, 16),
      ingredients: List.generate(
          n,
          (i) => Ingredient(
                id: 'i$i',
                weightGrams: i == 0 ? 0.3 : 123.4567 + i * 3.14159,
                isGross: i.isOdd,
                product: Product(
                    id: i + 1,
                    code: 'audit.$i',
                    name: 'Продукт ${i + 1}',
                    groupId: 1,
                    source: 'skurikhin',
                    protein: i == 0 ? 15.0 : 12.3456,
                    fat: 7.89123,
                    carbs: 35.6789,
                    kcal: 269.876,
                    wastePct: 19.5),
              )),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Артефакты экспорта — во временный каталог, а не в `../audit_artifacts/`
  // рабочего дерева (аудит D14).
  final artifacts = artifactDirOnce('exports');
  tearDownAll(() {
    if (artifacts.existsSync()) artifacts.deleteSync(recursive: true);
  });

  for (final mode in BlankMode.values) {
    for (final n in [0, 1, 18, 19, 30, 50, 100]) {
      test('PDF ${mode.name} $n ingredients', () async {
        final bytes = await PdfBlankGenerator.generate(fixture(n, mode: mode));
        expect(bytes.length, greaterThan(1000));
        expect(ascii.decode(bytes.take(4).toList()), '%PDF');
        await File('${artifacts.path}/pdf_${mode.name}_$n.pdf')
            .writeAsBytes(bytes);
      });
    }
    for (final n in [1, 5, 20]) {
      test('XLSX ${mode.name} $n ingredients', () async {
        final bytes = XlsxBlankGenerator.generate(fixture(n, mode: mode));
        expect(bytes.length, greaterThan(1000));
        await File('${artifacts.path}/xlsx_${mode.name}_$n.xlsx')
            .writeAsBytes(bytes);
      });
    }
  }

  late Directory dir;
  late DishStorageRepository storage;
  File getMain() => File('${dir.path}/povarspravka_user_dishes.json');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('povar_audit_');
    storage = DishStorageRepository(storageDirectory: dir);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('Storage serializes 100 concurrent saves', () async {
    final drafts = List.generate(100, (i) => fixture(1).copyWith(title: 'snapshot $i'));
    await Future.wait(List.generate(
        100,
        (i) => storage.saveAll(
              activeDraft: drafts[i],
              savedDishes: [fixture(1)],
            )));
    // Порядок соблюдён: последним записан именно 99-й черновик.
    expect((await storage.loadAll()).activeDraft!.title, 'snapshot 99');
    // FUZZ-13: черновик живёт в `draft.json` со СВОЕЙ резервной копией, а не
    // в документе библиотеки. Библиотека не менялась ни разу, поэтому её
    // документ и `.bak` не переписывались вовсе — и предпоследним
    // сохранённым черновиком остаётся 98-й.
    final draftBackup = jsonDecode(await File(
            '${getMain().path}.draft.json.bak')
        .readAsString()) as Map<String, dynamic>;
    expect((draftBackup['activeDraft'] as Map)['title'], 'snapshot 98');
    expect(await File('${getMain().path}.tmp').exists(), isFalse);
    expect(await File('${getMain().path}.draft.json.tmp').exists(), isFalse);
  });

  for (final damaged in [
    '',
    '{broken',
    '{}',
    '{"activeDraft":5,"savedDishes":[]}'
  ]) {
    test('Storage recovers invalid main: $damaged', () async {
      await storage.saveAll(
          activeDraft: fixture(1).copyWith(title: 'good'),
          savedDishes: [fixture(1)]);
      await storage.saveAll(
          activeDraft: fixture(1).copyWith(title: 'latest'), savedDishes: []);
      final before = await File('${getMain().path}.bak').readAsBytes();
      await getMain().writeAsString(damaged);
      expect((await storage.loadAll()).activeDraft!.title, 'good');
      expect(await File('${getMain().path}.bak').readAsBytes(), before);
      expect(jsonDecode(await getMain().readAsString())['activeDraft']['title'],
          'good');
    });
  }

  test('Storage recovers missing main from backup', () async {
    await storage.saveAll(activeDraft: fixture(1), savedDishes: []);
    await storage.saveAll(activeDraft: fixture(5), savedDishes: []);
    await getMain().delete();
    // FUZZ-13: черновик — отдельный документ, поэтому удаление файла
    // библиотеки его больше не задевает: восстанавливается ПОСЛЕДНИЙ
    // черновик (fixture(5) — 5 ингредиентов), а не предыдущее поколение.
    expect((await storage.loadAll()).activeDraft!.ingredients.length, 5);
  });

  test('Storage rejects unrecoverable corruption', () async {
    await getMain().writeAsString('{broken');
    await expectLater(storage.loadAll(), throwsFormatException);
    expect(await getMain().readAsString(), '{broken');
  });

  test('Storage propagates I/O error and queue remains usable', () async {
    await Directory('${getMain().path}.tmp').create();
    await expectLater(storage.saveAll(activeDraft: fixture(1), savedDishes: []),
        throwsA(isA<FileSystemException>()));
    await Directory('${getMain().path}.tmp').delete();
    await storage.saveAll(activeDraft: fixture(5), savedDishes: []);
    expect((await storage.loadAll()).activeDraft!.ingredients.length, 5);
  });

  test('DishNotifier sequentially saves rapid edits', () async {
    final notifier = DishNotifier(storage: storage);
    for (var i = 0; i < 100; i++) {
      notifier.setTitle('edit $i');
    }
    await notifier.flushPendingSaves();
    expect((await storage.loadAll()).activeDraft!.title, 'edit 99');
    notifier.dispose();
  });
}
