import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';

import 'audit_io_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(DishStorageRepository.resetForTesting);

  test('IO-07 resolveStorageDirectoryPath & storageFileName contract', () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    expect(await repo.resolveStorageDirectoryPath(), s.dir.path);
    expect(repo.storageFileName, kMainName);

    final memRepo = DishStorageRepository();
    expect(await memRepo.resolveStorageDirectoryPath(), isNull);
    expect(memRepo.storageFileName, kMainName);
  });

  test('writes schemaVersion: 2 while preserving storageVersion: 1 & legacy process omission',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final legacyDish = auditDish(120, id: 'legacy-1', title: 'Борщ');

    await repo.saveAll(activeDraft: legacyDish, savedDishes: [legacyDish]);

    final mainJson =
        jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect(mainJson['storageVersion'], 1);
    expect(mainJson['schemaVersion'], DishStorageRepository.currentSchemaVersion);
    expect(mainJson['crc32'], isA<int>());
    final savedEntry =
        (mainJson['savedDishes'] as List).single as Map<String, dynamic>;
    expect(savedEntry.containsKey('process'), isFalse);

    // Fast-path draft save also stamps schemaVersion: 2.
    await repo.saveAll(
      activeDraft: legacyDish.copyWith(title: 'Борщ 2'),
      savedDishes: [legacyDish],
    );
    final draftFile = File('${s.main.path}.draft.json');
    final draftJson =
        jsonDecode(await draftFile.readAsString()) as Map<String, dynamic>;
    expect(draftJson['storageVersion'], 1);
    expect(
        draftJson['schemaVersion'], DishStorageRepository.currentSchemaVersion);
    expect(draftJson['crc32'], isA<int>());
  });

  test('legacy documents without schemaVersion load cleanly with null compatibilityNotice',
      () async {
    final s = await makeStore();
    final dish = auditDish(100, id: 'old1', title: 'Старый');
    await s.main.writeAsString(
      encodeDocument({
        'activeDraft': dish.toJson(),
        'savedDishes': [dish.toJson()],
      }),
      flush: true,
    );

    final repo = DishStorageRepository(storageDirectory: s.dir);
    final loaded = await repo.loadAll();
    expect(loaded.savedDishes.single.title, 'Старый');
    expect(repo.recoveryNotice, isNull);
    expect(repo.consumeCompatibilityNotice(), isNull);

    await repo.saveAll(
      activeDraft: loaded.activeDraft,
      savedDishes: [dish.copyWith(title: 'Обновлённый')],
    );
    final rewritten =
        jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect(rewritten['schemaVersion'], DishStorageRepository.currentSchemaVersion);
  });

  test('forward-compat: schemaVersion > 2 preserves nested keys & unknown enums across restarts and writes .vN.bak',
      () async {
    final s = await makeStore();
    final productWithMeasure = const Product(
      id: 42,
      code: '42',
      name: 'Молоко',
      groupId: 5,
      source: 'skurikhin',
      protein: 3.0,
      fat: 3.2,
      carbs: 4.7,
      kcal: 60.0,
      measures: [
        ProductMeasure(id: 7, productId: 42, name: 'стакан', grams: 200.0),
      ],
    );
    final dish = Dish(
      id: 'v3-dish',
      title: 'Каша v3',
      ingredients: [
        Ingredient(id: 'ing-1', product: productWithMeasure, weightGrams: 100),
      ],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final dishMap = dish.toJson();
    dishMap['process'] = 'sousVide';
    dishMap['blankMode'] = 'compactPdf';
    dishMap['futureDishNote'] = 'special';
    final ingList = dishMap['ingredients'] as List;
    final ingMap = Map<String, dynamic>.from(ingList.single as Map);
    ingMap['group'] = 'futureDairy';
    ingMap['process'] = 'sousVide';
    ingMap['futureIngTag'] = 99;
    final prodMap = Map<String, dynamic>.from(ingMap['product'] as Map);
    prodMap['futureOrigin'] = 'farm';
    final measureList = prodMap['measures'] as List;
    final mMap = Map<String, dynamic>.from(measureList.single as Map);
    mMap['futureDensity'] = 1.03;
    prodMap['measures'] = [mMap];
    ingMap['product'] = prodMap;
    dishMap['ingredients'] = [ingMap];

    final v3RawBytes = encodeDocument({
      'schemaVersion': 3,
      'futureWorkspaceTheme': 'nord',
      'activeDraft': null,
      'savedDishes': [dishMap],
      'generation': 5,
    });
    await s.main.writeAsString(v3RawBytes, flush: true);

    final draftV4 = Map<String, dynamic>.from(dishMap)..['title'] = 'Черновик v4';
    final draftFile = File('${s.main.path}.draft.json');
    final v4DraftBytes = encodeDocument({
      'schemaVersion': 4,
      'activeDraft': draftV4,
      'generation': 6,
    });
    await draftFile.writeAsString(v4DraftBytes, flush: true);

    final repo = DishStorageRepository(storageDirectory: s.dir);
    final loaded = await repo.loadAll();

    // Separate notice from recoveryNotice (clean load keeps recoveryNotice == null).
    expect(repo.recoveryNotice, isNull);
    final notice = repo.consumeCompatibilityNotice();
    expect(notice, isNotNull);
    expect(notice, contains('v4'));
    expect(repo.consumeCompatibilityNotice(), isNull);

    final loadedSaved = loaded.savedDishes.single;
    expect(loadedSaved.process, HeatProcess.legacy);
    expect(loadedSaved.blankMode, BlankMode.photoCross);
    expect(loadedSaved.ingredients.single.groupOverride, isNull);
    expect(loadedSaved.ingredients.single.processOverride, isNull);
    expect(loaded.activeDraft?.title, 'Черновик v4');

    // 1) Fast-path draft edit creates draft .v4.bak and keeps main intact.
    await repo.saveAll(
      activeDraft: loaded.activeDraft!.copyWith(title: 'Черновик v2 правка'),
      savedDishes: loaded.savedDishes,
    );
    final draftV4Bak = File('${draftFile.path}.v4.bak');
    expect(await draftV4Bak.exists(), isTrue);
    expect(await draftV4Bak.readAsString(), v4DraftBytes);

    // 2) Slow-path library edit creates main .v3.bak before downgrading schemaVersion to 2,
    //    while keeping all unknown keys & unknown enum values intact.
    final modifiedSaved = loadedSaved.copyWith(
      title: 'Каша v2 правка',
      ingredients: [
        loadedSaved.ingredients.single.copyWith(weightGrams: 150),
      ],
    );
    await repo.saveAll(
      activeDraft: loaded.activeDraft!.copyWith(title: 'Черновик v2 правка'),
      savedDishes: [modifiedSaved],
    );

    final mainV3Bak = File('${s.main.path}.v3.bak');
    expect(await mainV3Bak.exists(), isTrue);
    expect(await mainV3Bak.readAsString(), v3RawBytes);

    // 3) Restart (resetForTesting) -> loadAll -> second unrelated edit -> saveAll:
    //    preserved unknown fields and future enums MUST STILL survive cycle #2.
    DishStorageRepository.resetForTesting();
    final repo2 = DishStorageRepository(storageDirectory: s.dir);
    final reloaded = await repo2.loadAll();
    expect(repo2.consumeCompatibilityNotice(), isNull);
    await repo2.saveAll(
      activeDraft: null,
      savedDishes: [reloaded.savedDishes.single.copyWith(title: 'Цикл 2')],
    );

    final afterSecond =
        jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    expect(afterSecond['schemaVersion'], DishStorageRepository.currentSchemaVersion);
    expect(afterSecond['futureWorkspaceTheme'], 'nord');
    final saved2 =
        (afterSecond['savedDishes'] as List).single as Map<String, dynamic>;
    expect(saved2['title'], 'Цикл 2');
    expect(saved2['futureDishNote'], 'special');
    expect(saved2['process'], 'sousVide');
    expect(saved2['blankMode'], 'compactPdf');
    final ing2 = (saved2['ingredients'] as List).single as Map<String, dynamic>;
    expect(ing2['futureIngTag'], 99);
    expect(ing2['group'], 'futureDairy');
    expect(ing2['process'], 'sousVide');
    final prod2 = ing2['product'] as Map<String, dynamic>;
    expect(prod2['futureOrigin'], 'farm');
    final measure2 = (prod2['measures'] as List).single as Map<String, dynamic>;
    expect(measure2['futureDensity'], 1.03);

    // 4) Explicit v2 enum edit overrides preserved future enum, and replacing
    //    ingredient product does NOT leak old product extra fields onto the new product.
    final explicitEdit = reloaded.savedDishes.single.copyWith(
      process: HeatProcess.boil,
      blankMode: BlankMode.detailed,
      ingredients: [
        reloaded.savedDishes.single.ingredients.single.copyWith(
          product: auditBeet, // product.id = 1 != 42
          groupOverride: LossGroup.meat,
        ),
      ],
    );
    await repo2.saveAll(activeDraft: null, savedDishes: [explicitEdit]);

    final afterExplicit =
        jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    final savedExplicit =
        (afterExplicit['savedDishes'] as List).single as Map<String, dynamic>;
    expect(savedExplicit['process'], 'boil');
    expect(savedExplicit['blankMode'], 'detailed');
    final ingExplicit =
        (savedExplicit['ingredients'] as List).single as Map<String, dynamic>;
    expect(ingExplicit['group'], 'meat');
    final prodExplicit = ingExplicit['product'] as Map<String, dynamic>;
    expect(prodExplicit.containsKey('futureOrigin'), isFalse);
  });

  test('corrupt timestamp or invalid schemaVersion falls back to .bak or throws FormatException',
      () async {
    final s = await makeStore();
    final repo = DishStorageRepository(storageDirectory: s.dir);
    final good = auditDish(100, id: 'good', title: 'Хорошее');
    await repo.saveAll(activeDraft: null, savedDishes: [good]);
    final second = auditDish(200, id: 'good2', title: 'Второе');
    await repo.saveAll(activeDraft: null, savedDishes: [second]);

    // Case 1: valid CRC on disk, but corrupted createdAt timestamp -> falls back to .bak.
    final badCreated = second.toJson()..['createdAt'] = 'not-a-date';
    await s.main.writeAsString(
      encodeDocument({
        'activeDraft': null,
        'savedDishes': [badCreated],
        'schemaVersion': 2,
      }),
      flush: true,
    );
    DishStorageRepository.resetForTesting();
    final recoveredRepo = DishStorageRepository(storageDirectory: s.dir);
    final recovered = await recoveredRepo.loadAll();
    expect(recoveredRepo.didRecoverFromBackup, isTrue);
    expect(recovered.savedDishes.single.id, 'good');

    // Case 2: invalid schemaVersion (0) with no backup -> throws FormatException.
    await File('${s.main.path}.bak').delete();
    await s.main.writeAsString(
      encodeDocument({
        'activeDraft': null,
        'savedDishes': [good.toJson()],
        'schemaVersion': 0,
      }),
      flush: true,
    );
    DishStorageRepository.resetForTesting();
    expect(
      () => DishStorageRepository(storageDirectory: s.dir).loadAll(),
      throwsA(isA<FormatException>()),
    );

    // Case 3: in-memory minimal Dish.fromJson without dates remains supported.
    expect(Dish.fromJson({'id': 'z'}).process, HeatProcess.legacy);
  });

  test('RA-14 normalized dir sharing, no <default> memory pollution, and LRU bound > 64 dirs',
      () async {
    // 1) Memory-only instances do not leak across each other.
    final memA = DishStorageRepository();
    final memB = DishStorageRepository();
    await memA.saveAll(
      activeDraft: auditDish(50, id: 'mem-a', title: 'A'),
      savedDishes: [auditDish(50, id: 'mem-a', title: 'A')],
    );
    expect((await memA.loadAll()).savedDishes.single.id, 'mem-a');
    expect((await memB.loadAll()).savedDishes, isEmpty);

    // 2) Equivalent path forms share directory state across instances.
    final s = await makeStore();
    final dotDir = Directory('${s.dir.path}${Platform.pathSeparator}.');
    final d = auditDish(100, id: 'norm', title: 'Норм');
    final dishMap = d.toJson()..['futureField'] = 'keep';
    await s.main.writeAsString(
      encodeDocument({
        'activeDraft': null,
        'savedDishes': [dishMap],
        'schemaVersion': 2,
      }),
      flush: true,
    );
    await DishStorageRepository(storageDirectory: s.dir).loadAll();
    await DishStorageRepository(storageDirectory: dotDir).saveAll(
      activeDraft: null,
      savedDishes: [d.copyWith(title: 'Через точку')],
    );
    final raw = jsonDecode(await s.main.readAsString()) as Map<String, dynamic>;
    final saved = (raw['savedDishes'] as List).single as Map<String, dynamic>;
    expect(saved['futureField'], 'keep');

    // 3) > 64 directories can be cycled without errors or cross-dir contamination.
    final root = await makeStore();
    for (var i = 0; i < 70; i++) {
      final sub = Directory('${root.dir.path}${Platform.pathSeparator}d$i');
      final r = DishStorageRepository(storageDirectory: sub);
      await r.saveAll(
        activeDraft: null,
        savedDishes: [auditDish(10 + i.toDouble(), id: 'id-$i')],
      );
      final back = await r.loadAll();
      expect(back.savedDishes.single.id, 'id-$i');
    }
  });
}
