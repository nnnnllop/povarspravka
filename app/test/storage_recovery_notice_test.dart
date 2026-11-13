// Задача 2026-11-03, хранилище: «при расхождении — восстановление с уведомлением».
//
// Репозиторий и раньше восстанавливал повреждённые документы из `.bak`, но
// делал это молча: флаг `didRecoverFromBackup` никто не читал. Теперь
// репозиторий формулирует уведомление, DishNotifier передаёт его в
// `storageRecoveryNoticeProvider`, а главный экран показывает баннер.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';

Dish _dish(String id, String title) =>
    Dish.withProcess(id: id, process: HeatProcess.cold).copyWith(title: title);

File _main(Directory dir) => File('${dir.path}/povarspravka_user_dishes.json');
File _draft(Directory dir) => File('${_main(dir).path}.draft.json');

/// Два поколения библиотеки и черновика — чтобы у обоих документов была
/// резервная копия.
Future<void> _twoGenerations(Directory dir) async {
  final repo = DishStorageRepository(storageDirectory: dir);
  // Одни и те же экземпляры блюд: отпечаток библиотеки включает метки
  // времени, и только так «библиотека не изменилась» действительно верно.
  final a = _dish('a', 'блюдо A');
  final b = _dish('b', 'блюдо B');
  final draft = _dish('d', 'черновик');
  await repo.saveAll(
      activeDraft: draft.copyWith(title: 'черновик 1'), savedDishes: [a]);
  await repo.saveAll(
      activeDraft: draft.copyWith(title: 'черновик 2'), savedDishes: [a, b]);
  // Библиотека не меняется → быстрый путь пишет только `draft.json`; вторая
  // такая запись оставляет и его резервную копию.
  await repo.saveAll(
      activeDraft: draft.copyWith(title: 'черновик 3'), savedDishes: [a, b]);
  await repo.saveAll(
      activeDraft: draft.copyWith(title: 'черновик 4'), savedDishes: [a, b]);
}

void main() {
  late Directory dir;

  setUp(() async {
    DishStorageRepository.resetForTesting();
    dir = await Directory.systemTemp.createTemp('povar_notice_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('чистая загрузка — уведомления нет', () async {
    await _twoGenerations(dir);
    final repo = DishStorageRepository(storageDirectory: dir);
    final data = await repo.loadAll();
    expect(data.savedDishes.length, 2);
    expect(repo.didRecoverFromBackup, isFalse);
    expect(repo.didRecoverDraftFromBackup, isFalse);
    expect(repo.recoveryNotice, isNull);
  });

  test('повреждённая библиотека → резервная копия + уведомление', () async {
    await _twoGenerations(dir);
    expect(await File('${_main(dir).path}.bak').exists(), isTrue);
    await _main(dir).writeAsString('{broken');
    final repo = DishStorageRepository(storageDirectory: dir);
    final data = await repo.loadAll();
    expect(data.savedDishes, isNotEmpty, reason: 'данные взяты из .bak');
    expect(repo.didRecoverFromBackup, isTrue);
    expect(repo.recoveryNotice, contains('резервной копии'));
    expect(repo.recoveryNotice, contains('Файл с блюдами'));

    // После восстановления основной файл переписан — следующая загрузка
    // чистая, и уведомление сбрасывается.
    final again = DishStorageRepository(storageDirectory: dir);
    await again.loadAll();
    expect(again.recoveryNotice, isNull);
  });

  test('повреждённый draft.json → резервная копия черновика + уведомление',
      () async {
    await _twoGenerations(dir);
    expect(await _draft(dir).exists(), isTrue);
    expect(await File('${_draft(dir).path}.bak').exists(), isTrue);
    await _draft(dir).writeAsString('{broken');
    final repo = DishStorageRepository(storageDirectory: dir);
    final data = await repo.loadAll();
    expect(data.activeDraft, isNotNull);
    expect(data.savedDishes.length, 2, reason: 'библиотека не затронута');
    expect(repo.didRecoverFromBackup, isFalse);
    expect(repo.didRecoverDraftFromBackup, isTrue);
    expect(repo.recoveryNotice, contains('Черновик был повреждён'));
  });

  test('DishNotifier передаёт уведомление после загрузки', () async {
    await _twoGenerations(dir);
    await _main(dir).writeAsString('{broken');
    final received = <String>[];
    final notifier = DishNotifier(
      storage: DishStorageRepository(storageDirectory: dir),
      onRecoveryNotice: received.add,
    );
    addTearDown(notifier.dispose);
    await notifier.flushPendingSaves();
    expect(received, hasLength(1));
    expect(notifier.storageRecoveryNotice, received.single);
    expect(received.single, contains('резервной копии'));
  });

  test('DishNotifier: чистая загрузка — колбэк не вызывается', () async {
    await _twoGenerations(dir);
    final received = <String>[];
    final notifier = DishNotifier(
      storage: DishStorageRepository(storageDirectory: dir),
      onRecoveryNotice: received.add,
    );
    addTearDown(notifier.dispose);
    await notifier.flushPendingSaves();
    expect(received, isEmpty);
    expect(notifier.storageRecoveryNotice, isNull);
  });

  testWidgets('главный экран: баннер восстановления и кнопка «Понятно»',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late ProviderContainer container;
    await tester.runAsync(() async {
      await _twoGenerations(dir);
      await _main(dir).writeAsString('{broken');
      container = ProviderContainer(overrides: [
        dishStorageRepositoryProvider
            .overrideWithValue(DishStorageRepository(storageDirectory: dir)),
      ]);
      await container.read(dishProvider.notifier).flushPendingSaves();
    });
    addTearDown(container.dispose);
    expect(container.read(storageRecoveryNoticeProvider), isNotNull,
        reason: 'dishProvider передал уведомление в провайдер');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    ));
    await tester.pump();
    expect(find.byKey(const Key('storage-recovery-banner')), findsOneWidget);
    expect(find.textContaining('восстановлены из резервной копии'),
        findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pump();
    expect(find.byKey(const Key('storage-recovery-banner')), findsNothing);
    expect(container.read(storageRecoveryNoticeProvider), isNull);
  });
}
