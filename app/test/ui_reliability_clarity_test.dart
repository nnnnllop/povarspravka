import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/calculation_result.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/calc_error_banner.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';

class _ControllableStorage extends DishStorageRepository {
  bool failLoad = false;
  bool failSave = false;
  DishStorageData data;
  String? dirPath;
  String? compatNotice;
  int saveCalls = 0;

  _ControllableStorage({
    this.data = const DishStorageData(),
    this.dirPath =
        '/storage/emulated/0/Android/data/ru.povarspravka.app/files/long/diagnostics/path',
    this.compatNotice,
  });

  @override
  Future<String?> resolveStorageDirectoryPath() async => dirPath;

  @override
  String? consumeCompatibilityNotice() {
    final notice = compatNotice;
    compatNotice = null;
    return notice;
  }

  @override
  Future<DishStorageData> loadAll() async {
    if (failLoad) {
      throw const FileSystemException('Simulated read error');
    }
    return data;
  }

  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {
    saveCalls++;
    if (failSave) {
      throw const FileSystemException('Simulated write error');
    }
    data = DishStorageData(
      activeDraft: activeDraft,
      savedDishes: savedDishes,
    );
  }
}

Product _chickenProduct() => const Product(
      id: 1,
      code: 'p1',
      name: 'Курица (филе)',
      groupId: 1,
      source: 'skurikhin',
      protein: 23.6,
      fat: 1.9,
      carbs: 0.4,
      kcal: 113.0,
    );

Product _carrotProduct() => const Product(
      id: 2,
      code: 'p2',
      name: 'Морковь',
      groupId: 5,
      source: 'skurikhin',
      protein: 1.3,
      fat: 0.1,
      carbs: 6.9,
      kcal: 34.0,
    );

Product _oilProduct() => const Product(
      id: 3,
      code: 'p3',
      name: 'Масло подсолнечное',
      groupId: 12,
      source: 'skurikhin',
      protein: 0.0,
      fat: 99.9,
      carbs: 0.0,
      kcal: 899.0,
    );

Dish _sampleDish({
  String id = 'dish-1',
  String title = 'Котлета паровая',
  HeatProcess process = HeatProcess.cold,
  double? customYieldGrams,
  List<Ingredient>? ingredients,
}) {
  final now = DateTime(2026, 11, 13, 12);
  return Dish.withProcess(
    id: id,
    process: process,
    title: title,
    customYieldGrams: customYieldGrams,
    ingredients: ingredients ??
        [
          Ingredient(
            id: 'ing-1',
            product: _chickenProduct(),
            weightGrams: 100,
            groupOverride: LossGroup.meat,
          ),
        ],
    createdAt: now,
    updatedAt: now,
  );
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets(
      'RecipeEditorScreen banner has Retry button and clears on write recovery',
      (tester) async {
    _setViewport(tester, const Size(320, 640));
    final storage = _ControllableStorage();
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);

    storage.failSave = true;
    await tester.enterText(
      find.widgetWithText(TextField, 'Название блюда'),
      'Борщ тестовый',
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('persistence-error-retry')), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    // Retry while disk still fails keeps the banner visible.
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);

    // Once disk recovers, Retry writes draft and clears the banner.
    storage.failSave = false;
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);
    expect(storage.data.activeDraft?.title, 'Борщ тестовый');
  });

  testWidgets(
      'Save-and-exit keeps editor open when saveCurrentToLibrary fails and Retry completes it',
      (tester) async {
    final storage = _ControllableStorage();
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecipeEditorScreen(),
                    ),
                  );
                },
                child: const Text('Открыть редактор'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Открыть редактор'));
    await tester.pumpAndSettle();

    storage.failSave = true;
    await tester.enterText(
      find.widgetWithText(TextField, 'Название блюда'),
      'Сохранённый суп',
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Сохранить и выйти'), findsOneWidget);
    await tester.tap(find.text('Сохранить и выйти'));
    await tester.pumpAndSettle();

    // Must remain on RecipeEditorScreen and show the Retry banner.
    expect(find.byType(RecipeEditorScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
    expect(storage.data.savedDishes, isEmpty);

    storage.failSave = false;
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);
    expect(storage.data.savedDishes, hasLength(1));
    expect(storage.data.savedDishes.single.title, 'Сохранённый суп');
    expect(container.read(dishProvider.notifier).isDirty, isFalse);
  });

  testWidgets(
      'HomeScreen surfaces SavedDishesNotifier, newCalculation errors, compatibility notice, and retries cleanly at 320x640',
      (tester) async {
    _setViewport(tester, const Size(320, 640));
    final savedDish = _sampleDish(id: 'saved-1', title: 'Сохранённый салат');
    final activeDraft = _sampleDish(id: 'draft-1', title: 'Активный черновик');
    final storage = _ControllableStorage(
      data: DishStorageData(
        activeDraft: activeDraft,
        savedDishes: [savedDish],
      ),
      compatNotice: 'Файл создан более новой версией приложения.',
    );
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('storage-compatibility-banner')), findsOneWidget);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storage-compatibility-banner')), findsNothing);

    // _newCalculation must NOT lose the active draft when saveCurrentToLibrary fails.
    storage.failSave = true;
    await tester.tap(find.text('Новый расчёт'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
    expect(container.read(dishProvider).id, 'draft-1');
    expect(container.read(dishProvider).ingredients, hasLength(1));

    storage.failSave = false;
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);

    // Deleting a saved dish while disk fails surfaces error banner and Retry deletes it.
    storage.failSave = true;
    final menuBtn = find.byTooltip('Действия с блюдом').first;
    await tester.ensureVisible(menuBtn);
    await tester.tap(menuBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
    expect(container.read(savedDishesProvider), hasLength(2));

    storage.failSave = false;
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);
    expect(container.read(savedDishesProvider), hasLength(1));
    expect(container.read(savedDishesProvider).single.id, 'saved-1');
  });

  testWidgets(
      'HomeScreen exposes startup load error immediately and recovers on Retry',
      (tester) async {
    final savedDish = _sampleDish(id: 'saved-init', title: 'После повтора');
    final storage = _ControllableStorage(
      data: DishStorageData(savedDishes: [savedDish]),
    )..failLoad = true;
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
    expect(container.read(savedDishesProvider), isEmpty);

    storage.failLoad = false;
    await tester.tap(find.byKey(const ValueKey('persistence-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('persistence-error-banner')), findsNothing);
    expect(find.text('После повтора'), findsOneWidget);
  });

  testWidgets(
      'IO-07 shows and copies long storage directory path in How It Works sheet at 320x640',
      (tester) async {
    _setViewport(tester, const Size(320, 640));
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const longPath =
        '/storage/emulated/0/Android/data/ru.povarspravka.app/files/nested/support/diagnostics/recipes_dir';
    final storage = _ControllableStorage(dirPath: longPath);
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Как считается'));
    await tester.pumpAndSettle();

    // A3-SRC-01/02 rules also appear in How It Works.
    expect(find.textContaining('без слива отвара'), findsOneWidget);
    expect(find.textContaining('оценочный переход нутриентов'), findsOneWidget);
    expect(find.textContaining('50 % добавленного жира'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('storage-dir-path')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text(longPath), findsOneWidget);
    expect(find.textContaining(storage.storageFileName), findsOneWidget);

    final copyBtn = find.byKey(const ValueKey('copy-storage-dir-btn'));
    await tester.ensureVisible(copyBtn);
    await tester.tap(copyBtn);
    await tester.pumpAndSettle();

    expect(copiedText, longPath);
  });

  test('IO-07 DishStorageRepository resolveStorageDirectoryPath contract',
      () async {
    final dir = await Directory.systemTemp.createTemp('io07_ui_test_');
    addTearDown(() => dir.delete(recursive: true));

    final repo = DishStorageRepository(storageDirectory: dir);
    expect(await repo.resolveStorageDirectoryPath(), dir.path);
    expect(repo.storageFileName, isNotEmpty);

    // Without storageDirectory in pure VM test, path_provider throws MissingPluginException -> null.
    final defaultRepo = DishStorageRepository();
    expect(await defaultRepo.resolveStorageDirectoryPath(), isNull);
  });

  test('CalculationValidation.warnsImpossiblePer100g unit behavior', () {
    const noYield = CalculationResult(
      blankMode: BlankMode.detailed,
      yieldGrams: 0,
      rawTotalWeight: 100,
      rawTotalProtein: 20,
      rawTotalFat: 10,
      rawTotalCarbs: 5,
      retentionProtein: 1,
      retentionFat: 1,
      retentionCarbs: 1,
      cookedProtein: 20,
      cookedFat: 10,
      cookedCarbs: 5,
      cookedKcal: 190,
      per100gProtein: 0,
      per100gFat: 0,
      per100gCarbs: 0,
      per100gKcal: 0,
      process: HeatProcess.cold,
    );
    expect(CalculationValidation.warnsImpossiblePer100g(noYield), isFalse);

    // 26.67 + 26.67 + 26.66 == 80.00 g matches 80 g yield; per-100g rounds to 33.34+33.34+33.33=100.01 -> must NOT warn.
    const exactDryEdge = CalculationResult(
      blankMode: BlankMode.detailed,
      yieldGrams: 80,
      rawTotalWeight: 80,
      rawTotalProtein: 26.67,
      rawTotalFat: 26.67,
      rawTotalCarbs: 26.66,
      retentionProtein: 1,
      retentionFat: 1,
      retentionCarbs: 1,
      cookedProtein: 26.67,
      cookedFat: 26.67,
      cookedCarbs: 26.66,
      cookedKcal: 453.3,
      per100gProtein: 33.34,
      per100gFat: 33.34,
      per100gCarbs: 33.33,
      per100gKcal: 566.6,
      process: HeatProcess.cold,
    );
    expect(CalculationValidation.warnsImpossiblePer100g(exactDryEdge), isFalse);

    const impossible = CalculationResult(
      blankMode: BlankMode.detailed,
      yieldGrams: 1,
      rawTotalWeight: 100,
      rawTotalProtein: 18,
      rawTotalFat: 0,
      rawTotalCarbs: 0,
      retentionProtein: 1,
      retentionFat: 1,
      retentionCarbs: 1,
      cookedProtein: 18,
      cookedFat: 0,
      cookedCarbs: 0,
      cookedKcal: 72,
      per100gProtein: 1800,
      per100gFat: 0,
      per100gCarbs: 0,
      per100gKcal: 7200,
      process: HeatProcess.cold,
    );
    expect(CalculationValidation.warnsImpossiblePer100g(impossible), isTrue);
  });

  testWidgets(
      'A3-INPUT-01 shows soft non-blocking warning in editor, portion stage, and inspector without altering yield at 320x640',
      (tester) async {
    _setViewport(tester, const Size(320, 640));
    final smallYieldDish = _sampleDish(
      id: 'b10-like',
      title: 'Плотный бульон',
      process: HeatProcess.cold,
      customYieldGrams: 5.0,
    );
    final storage = _ControllableStorage(
      data: DishStorageData(activeDraft: smallYieldDish),
    );
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('yield-density-warning')), findsOneWidget);
    expect(find.byType(CalcErrorBanner), findsNothing);
    // Custom yield set by cook must NOT be auto-modified.
    expect(container.read(dishProvider).customYieldGrams, 5.0);

    // Open inspector sheet and check warning there too.
    await tester.tap(find.byTooltip('Инспектор расчёта'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('inspector-yield-density-warning')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('inspector-yield-density-warning')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Понятно'));
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    // Non-compact MacroSummaryBar renders portion-stage warning as well.
    final calc = CalculationEngine.calculate(container.read(dishProvider));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MacroSummaryBar(result: calc, compact: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('portion-yield-density-warning')),
      findsOneWidget,
    );
  });

  testWidgets(
      'A3-SRC-01/02 dynamic clarity hints in process dialog, ingredient loss dialog, and inspector',
      (tester) async {
    _setViewport(tester, const Size(320, 640));
    final dish = _sampleDish(
      id: 'src-dish',
      title: 'Суп с овощами',
      process: HeatProcess.cold,
      customYieldGrams: 300,
      ingredients: [
        Ingredient(
          id: 'ing-veg',
          product: _carrotProduct(),
          weightGrams: 100,
          groupOverride: LossGroup.vegetable,
        ),
        Ingredient(
          id: 'ing-oil',
          product: _oilProduct(),
          weightGrams: 20,
          groupOverride: LossGroup.fatOil,
        ),
      ],
    );
    final storage = _ControllableStorage(
      data: DishStorageData(activeDraft: dish),
    );
    final container = ProviderContainer(
      overrides: [dishStorageRepositoryProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecipeEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Process dialog dynamic hints
    await tester.tap(find.byTooltip('Параметры'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('process-clarity-hint')), findsNothing);

    Future<void> selectDishProcess(HeatProcess p) async {
      await tester.tap(find.byKey(const ValueKey('heat-process')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(p.label).last);
      await tester.pumpAndSettle();
    }

    await selectDishProcess(HeatProcess.boil);
    expect(find.byKey(const ValueKey('process-clarity-hint')), findsOneWidget);
    expect(find.textContaining('без слива отвара'), findsOneWidget);

    await selectDishProcess(HeatProcess.stock);
    expect(find.textContaining('оценочный переход нутриентов'), findsOneWidget);

    await selectDishProcess(HeatProcess.fry);
    expect(find.textContaining('50 % добавленного жира'), findsOneWidget);

    // Switch back to boil and save dialog.
    await selectDishProcess(HeatProcess.boil);
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();

    // 2. Ingredient loss dialog hints (vegetable + boil)
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('loss-ing-veg')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('loss-ing-veg')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ingredient-loss-clarity-hint')),
      findsOneWidget,
    );
    expect(find.textContaining('без слива отвара'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    // Change ing-oil processOverride to fry via provider & check inspector hints.
    container
        .read(dishProvider.notifier)
        .setIngredientProcess('ing-oil', HeatProcess.fry);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Инспектор расчёта'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('inspector-loss-clarity-hints')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('inspector-loss-clarity-hints')),
      findsOneWidget,
    );
    expect(find.textContaining('без слива отвара'), findsOneWidget);
    expect(find.textContaining('50 % добавленного жира'), findsOneWidget);
  });
}
