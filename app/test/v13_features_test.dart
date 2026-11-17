import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/export_service.dart';
import 'package:povarspravka/core/theme/app_haptics.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/app_settings_repository.dart';
import 'package:povarspravka/data/repositories/backup_service.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/main.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/providers/settings_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';

const _potato = Product(
  id: 101,
  code: '01-101',
  name: 'Картофель',
  groupId: 1,
  source: 'skurikhin',
  wastePct: 20,
  protein: 2.0,
  fat: 0.4,
  carbs: 16.3,
  kcal: 77,
);

const _chicken = Product(
  id: 102,
  code: '02-102',
  name: 'Курица (грудка)',
  groupId: 101,
  source: 'bls',
  wastePct: 0,
  protein: 22.0,
  fat: 2.0,
  carbs: 0.0,
  kcal: 110,
);

const _customSauce = Product(
  id: -1,
  code: 'USER-1',
  name: 'Фирменный соус',
  nameNorm: 'фирменный соус',
  groupId: 0,
  source: 'custom',
  wastePct: 0,
  protein: 3.5,
  fat: 12.0,
  carbs: 6.0,
  kcal: 146,
  isDish: false,
);

class _MemStorage extends DishStorageRepository {
  Dish? activeDraft;
  List<Dish> savedDishes;

  _MemStorage({this.activeDraft, this.savedDishes = const []});

  @override
  Future<DishStorageData> loadAll() async => DishStorageData(
        activeDraft: activeDraft,
        savedDishes: savedDishes,
      );

  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {
    this.activeDraft = activeDraft;
    this.savedDishes = List<Dish>.from(savedDishes);
  }

  @override
  Future<String?> resolveStorageDirectoryPath() async => '/tmp/povarspravka';
}

class _MemCustomProductsRepo extends CustomProductsRepository {
  List<Product> items;

  _MemCustomProductsRepo([this.items = const []]);

  @override
  Future<List<Product>> loadAll() async => items;

  @override
  Future<void> saveAll(List<Product> products) async {
    items = List<Product>.from(products);
  }
}

class _MemSettingsRepo extends AppSettingsRepository {
  AppSettings stored = const AppSettings();

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async {
    stored = settings;
  }
}

class _FakeProductRepo extends ProductRepository {
  final List<Product> products = const [_potato, _chicken];
  final List<FoodGroup> groups = const [
    FoodGroup(id: 1, code: 'g1', name: 'Овощи и корнеплоды'),
    FoodGroup(id: 2, code: 'g2', name: 'Фрукты и ягоды'),
    FoodGroup(id: 3, code: 'g3', name: 'Крупы и бобовые'),
    FoodGroup(id: 4, code: 'g4', name: 'Хлеб и выпечка'),
    FoodGroup(id: 5, code: 'g5', name: 'Молочные продукты'),
    FoodGroup(id: 6, code: 'g6', name: 'Мясо и субпродукты'),
    FoodGroup(id: 7, code: 'g7', name: 'Рыба и морепродукты'),
    FoodGroup(id: 8, code: 'g8', name: 'Масла и жиры'),
    FoodGroup(id: 101, code: 'g101', name: 'Птица и дичь'),
  ];

  @override
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    bool? isDish,
    int limit = 50,
  }) async {
    final q = query.trim().toLowerCase();
    return products.where((p) {
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
      if (source != null && p.source != source) return false;
      if (groupId != null && p.groupId != groupId) return false;
      if (isDish != null && p.isDishOnly != isDish) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => groups;

  @override
  Future<Map<String, int>> getCountBySource({bool? isDish}) async {
    final matching =
        products.where((p) => isDish == null || p.isDishOnly == isDish);
    return {
      'skurikhin': matching.where((p) => p.source == 'skurikhin').length,
      'bls': matching.where((p) => p.source == 'bls').length,
      'supplement': 0,
    };
  }

  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('v1.3 AppSettingsRepository & AppSettingsNotifier', () {
    test('persists themeMode and hapticsEnabled atomically and handles corrupt json',
        () async {
      final dir = await Directory.systemTemp.createTemp('povarspravka_cfg_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final repo = AppSettingsRepository(storageDirectory: dir);
      final notifier = AppSettingsNotifier(repo);
      addTearDown(notifier.dispose);

      await notifier.flush();
      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.hapticsEnabled, isTrue);

      await notifier.setThemeMode(ThemeMode.dark);
      await notifier.setHapticsEnabled(false);
      await notifier.flush();

      expect(AppHaptics.enabled, isFalse);

      final reloaded = await AppSettingsRepository(storageDirectory: dir).load();
      expect(reloaded.themeMode, ThemeMode.dark);
      expect(reloaded.hapticsEnabled, isFalse);

      final cfgFile = File('${dir.path}${Platform.pathSeparator}app_settings.json');
      await cfgFile.writeAsString('{corrupt-json', flush: true);
      final fallback = await AppSettingsRepository(storageDirectory: dir).load();
      expect(fallback.themeMode, ThemeMode.system);
      expect(fallback.hapticsEnabled, isTrue);
    });
  });

  group('v1.3 BackupService & importProviders', () {
    test('encodes, validates and parses dishes and custom products', () {
      final dish = Dish.withProcess(
        id: 'dish-b1',
        title: 'Рагу',
        process: HeatProcess.stew,
        customYieldGrams: 350,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 200),
          Ingredient(id: 'i2', product: _customSauce, weightGrams: 50),
        ],
      );

      final jsonStr = BackupService.encodeBackup(
        savedDishes: [dish],
        customProducts: const [_customSauce],
        now: DateTime(2026, 11, 17, 12, 30),
      );
      final parsed = BackupService.parseBackup(jsonStr);

      expect(parsed.savedDishes.length, 1);
      expect(parsed.savedDishes.first.title, 'Рагу');
      expect(parsed.savedDishes.first.ingredients.length, 2);
      expect(parsed.customProducts.length, 1);
      expect(parsed.customProducts.first.name, 'Фирменный соус');
      expect(parsed.customProducts.first.source, 'custom');
      expect(parsed.exportedAt, DateTime(2026, 11, 17, 12, 30));

      expect(() => BackupService.parseBackup(''), throwsFormatException);
      expect(
        () => BackupService.parseBackup('{"format": "foreign"}'),
        throwsFormatException,
      );
      expect(
        () => BackupService.parseBackup('{"hello": "world"}'),
        throwsFormatException,
      );
    });

    test('SavedDishesNotifier.importDishes and CustomProductsNotifier.importProducts merge and replace',
        () async {
      final existingDish = Dish.withProcess(
        id: 'd1',
        title: 'Суп',
        process: HeatProcess.boil,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 150),
        ],
      );
      final storage = _MemStorage(savedDishes: [existingDish]);
      final savedNotifier = SavedDishesNotifier(storage);
      addTearDown(savedNotifier.dispose);
      savedNotifier.setInitialDishes([existingDish], null);

      // Identical ID + identical content is deduplicated; identical ID + changed
      // content gets a fresh copy ID instead of overwriting.
      final modifiedSameId = existingDish.copyWith(title: 'Суп обновлённый');
      final newDish = Dish.withProcess(
        id: 'd2',
        title: 'Салат',
        process: HeatProcess.cold,
        ingredients: const [
          Ingredient(id: 'i2', product: _chicken, weightGrams: 120),
        ],
      );

      final added = await savedNotifier.importDishes(
        [existingDish, modifiedSameId, newDish],
        replaceExisting: false,
      );
      expect(added, 2);
      expect(savedNotifier.state.length, 3);
      expect(
        savedNotifier.state.any((d) => d.title == 'Суп обновлённый'),
        isTrue,
      );

      final replaced = await savedNotifier.importDishes(
        [newDish],
        replaceExisting: true,
      );
      expect(replaced, 1);
      expect(savedNotifier.state.length, 1);
      expect(savedNotifier.state.first.id, 'd2');

      final customRepo = _MemCustomProductsRepo([_customSauce]);
      final customNotifier = CustomProductsNotifier(customRepo);
      addTearDown(customNotifier.dispose);
      await customNotifier.flush();

      final secondCustom = _customSauce.copyWith(
        id: -99,
        name: 'Сливки домашние',
        kcal: 205,
      );
      final productsAdded = await customNotifier.importProducts(
        [_customSauce, secondCustom],
        replaceExisting: false,
      );
      expect(productsAdded, 1);
      expect(customNotifier.state.length, 2);

      final productsReplaced = await customNotifier.importProducts(
        [secondCustom],
        replaceExisting: true,
      );
      expect(productsReplaced, 1);
      expect(customNotifier.state.length, 1);
      expect(customNotifier.state.first.name, 'Сливки домашние');
      expect(customNotifier.state.first.id, lessThan(0));
    });
  });

  group('v1.3 Recipe scaling, live custom sync & plain-text export', () {
    test('DishNotifier scales ingredients, restores snapshot and updates custom snapshots',
        () async {
      final storage = _MemStorage(
        activeDraft: Dish.withProcess(
          id: 'd-scale',
          title: 'Жаркое',
          process: HeatProcess.bake,
          customYieldGrams: 300,
          ingredients: const [
            Ingredient(id: 'i1', product: _potato, weightGrams: 100),
            Ingredient(id: 'i2', product: _customSauce, weightGrams: 50),
          ],
        ),
      );
      final notifier = DishNotifier(storage: storage);
      addTearDown(notifier.dispose);
      await notifier.flushPendingSaves();

      final before = notifier.state;
      expect(notifier.scaleIngredients(0), isFalse);
      expect(notifier.scaleIngredients(double.nan), isFalse);

      expect(notifier.scaleIngredients(2.0), isTrue);
      expect(notifier.state.ingredients[0].weightGrams, 200);
      expect(notifier.state.ingredients[1].weightGrams, 100);
      expect(notifier.state.customYieldGrams, 600);

      // Ignore restore for a different dish ID.
      notifier.restoreIngredientsSnapshot(
        dishId: 'other-dish',
        ingredients: before.ingredients,
        customYieldGrams: before.customYieldGrams,
      );
      expect(notifier.state.ingredients[0].weightGrams, 200);

      notifier.restoreIngredientsSnapshot(
        dishId: before.id,
        ingredients: before.ingredients,
        customYieldGrams: before.customYieldGrams,
      );
      expect(notifier.state.ingredients[0].weightGrams, 100);
      expect(notifier.state.customYieldGrams, 300);

      // Scaling without scaling yield leaves customYieldGrams intact.
      expect(
        notifier.scaleIngredients(1.5, scaleCustomYield: false),
        isTrue,
      );
      expect(notifier.state.ingredients[0].weightGrams, 150);
      expect(notifier.state.customYieldGrams, 300);

      // Live custom product edits update snapshots inside active dish.
      final updatedSauce = _customSauce.copyWith(name: 'Соус чесночный', kcal: 190);
      notifier.replaceProductSnapshots(updatedSauce);
      expect(notifier.state.ingredients[1].product.name, 'Соус чесночный');
      expect(notifier.state.ingredients[1].product.kcal, 190);
    });

    test('buildRecentProducts reflects edited custom product and excludes deleted one',
        () {
      final edited = _customSauce.copyWith(name: 'Соус острый', kcal: 175);
      final afterEdit = buildRecentProducts(
        sessionRecent: const [_potato, _customSauce],
        activeIngredients: const [],
        savedDishIngredients: const [],
        customProducts: [edited],
      );
      expect(afterEdit.map((p) => p.name), ['Картофель', 'Соус острый']);
      expect(afterEdit.last.kcal, 175);

      final afterDelete = buildRecentProducts(
        sessionRecent: const [_potato, _customSauce],
        activeIngredients: const [_customSauce],
        savedDishIngredients: const [
          [_customSauce]
        ],
        customProducts: const [],
      );
      expect(afterDelete.map((p) => p.id), [_potato.id]);
    });

    test('ExportService.formatPlainTextSummary builds crisp text for messengers',
        () {
      final dish = Dish.withProcess(
        id: 'd-txt',
        title: 'Борщ домашний',
        process: HeatProcess.boil,
        customYieldGrams: 500,
        ingredients: const [
          Ingredient(
            id: 'i1',
            product: _potato,
            weightGrams: 200,
            isGross: true,
          ),
          Ingredient(
            id: 'i2',
            product: _chicken,
            weightGrams: 150,
            isGross: false,
          ),
        ],
      );
      final calc = CalculationEngine.calculate(dish);
      final text = ExportService.formatPlainTextSummary(dish, calc);

      expect(text, contains('Борщ домашний'));
      expect(text, contains('На всё блюдо: Б '));
      expect(text, contains('На 100 г (выход 500 г): Б '));
      expect(text, contains('1. Картофель — 200 г брутто (160 г нетто)'));
      expect(text, contains('2. Курица (грудка) — 150 г'));
    });
  });

  group('v1.3 Widget integrations', () {
    testWidgets(
        'HomeScreen theme switch, haptics switch and backup restore flow work cleanly (including 320x568 @2x)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String copied = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String? ?? '';
        } else if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': copied};
        }
        return null;
      });

      final storage = _MemStorage(
        savedDishes: [
          Dish.withProcess(
            id: 'd-init',
            title: 'Омлет',
            process: HeatProcess.fry,
            ingredients: const [
              Ingredient(id: 'i1', product: _chicken, weightGrams: 100),
            ],
          ),
        ],
      );
      final settingsRepo = _MemSettingsRepo();
      final customRepo = _MemCustomProductsRepo([_customSauce]);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2.0),
          ),
          child: ProviderScope(
            overrides: [
              dishStorageRepositoryProvider.overrideWithValue(storage),
              productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
              customProductsRepositoryProvider.overrideWithValue(customRepo),
              appSettingsRepositoryProvider.overrideWithValue(settingsRepo),
            ],
            child: const PovarSpravkaApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Как считается'));
      await tester.pumpAndSettle();

      expect(find.text('Версия 1.3.0'), findsOneWidget);
      expect(find.text('Оформление и отклик'), findsOneWidget);
      expect(find.text('Резервная копия данных'), findsOneWidget);

      // Scroll to ThemeMode & Haptics controls at 2x scale on 320px width.
      final themeSeg = find.byKey(const ValueKey('theme-mode-segmented'));
      await tester.scrollUntilVisible(
        themeSeg,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тёмная'));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(settingsRepo.stored.themeMode, ThemeMode.dark);

      final hapticsSwitch = find.byKey(const ValueKey('haptics-switch'));
      await tester.scrollUntilVisible(
        hapticsSwitch,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(hapticsSwitch);
      await tester.pumpAndSettle();
      expect(AppHaptics.enabled, isFalse);
      expect(settingsRepo.stored.hapticsEnabled, isFalse);

      // Copy JSON backup, then open restore sheet and restore a new dish.
      final copyBtn = find.byKey(const ValueKey('backup-copy-btn'));
      await tester.scrollUntilVisible(
        copyBtn,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      expect(copied, contains('povarspravka-backup'));
      expect(copied, contains('Омлет'));

      final restoreBtn = find.byKey(const ValueKey('backup-restore-btn'));
      await tester.ensureVisible(restoreBtn);
      await tester.tap(restoreBtn);
      await tester.pumpAndSettle();

      final backupJson = BackupService.encodeBackup(
        savedDishes: [
          Dish.withProcess(
            id: 'd-imported',
            title: 'Запеканка из копии',
            process: HeatProcess.bake,
            ingredients: const [
              Ingredient(id: 'imp1', product: _potato, weightGrams: 180),
            ],
          ),
        ],
        customProducts: const [],
      );
      await tester.enterText(
        find.byKey(const ValueKey('backup-json-field')),
        backupJson,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('backup-preview-card')), findsOneWidget);
      expect(find.text('Готово к восстановлению'), findsOneWidget);

      final mergeBtn = find.byKey(const ValueKey('backup-merge-btn'));
      await tester.ensureVisible(mergeBtn);
      await tester.tap(mergeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Запеканка из копии'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'RecipeEditorScreen scales recipe with Undo and saves dish as semi-finished custom product',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage(
        activeDraft: Dish.withProcess(
          id: 'd-edit',
          title: 'Котлета паровая',
          process: HeatProcess.steam,
          customYieldGrams: 150,
          ingredients: const [
            Ingredient(id: 'i1', product: _chicken, weightGrams: 120),
          ],
        ),
      );
      final customRepo = _MemCustomProductsRepo();
      final container = ProviderContainer(
        overrides: [
          dishStorageRepositoryProvider.overrideWithValue(storage),
          productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
          customProductsRepositoryProvider.overrideWithValue(customRepo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RecipeEditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Сырьё нетто 120 г · выход 150 г'),
        findsOneWidget,
      );

      // Scale ×2 via popup menu and undo via SnackBar action.
      await tester.tap(find.byTooltip('Другие действия'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Масштабировать веса'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('scale-preset-2.0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scale-apply-btn')));
      await tester.pumpAndSettle();

      expect(container.read(dishProvider).ingredients.first.weightGrams, 240);
      expect(container.read(dishProvider).customYieldGrams, 300);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider).ingredients.first.weightGrams, 120);
      expect(container.read(dishProvider).customYieldGrams, 150);

      // Save current dish as semi-finished custom product.
      await tester.tap(find.byTooltip('Другие действия'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить как полуфабрикат'));
      await tester.pumpAndSettle();

      expect(find.text('Сохранить как полуфабрикат'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('custom-save-btn')));
      await tester.pumpAndSettle();

      final customs = container.read(customProductsProvider);
      expect(customs.length, 1);
      expect(customs.first.name, 'Котлета паровая');
      expect(customs.first.isDishOnly, isTrue);
    });

    testWidgets(
        'BlankPreviewScreen toggles blank options interactively and copies plain-text КБЖУ summary',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String copied = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String? ?? '';
        }
        return null;
      });

      final storage = _MemStorage(
        activeDraft: Dish.withProcess(
          id: 'd-blank',
          title: 'Пюре картофельное',
          process: HeatProcess.boil,
          customYieldGrams: 200,
          blankMode: BlankMode.photoCross,
          ingredients: const [
            Ingredient(id: 'i1', product: _potato, weightGrams: 250),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          dishStorageRepositoryProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BlankPreviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('blank-mode-banner')));
      await tester.pumpAndSettle();
      expect(find.text('Настройки бланка'), findsOneWidget);

      await tester.tap(find.text(BlankMode.detailed.shortName));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider).blankMode, BlankMode.detailed);

      Navigator.of(tester.element(find.text('Настройки бланка'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Экспорт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скопировать КБЖУ текстом'));
      await tester.pumpAndSettle();

      expect(copied, contains('Пюре картофельное'));
      expect(copied, contains('Картофель'));
    });

    testWidgets(
        'SearchProductModal shows Свои filter pill, searchable categories (>=8) and delete confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeProductRepo();
      final customRepo = _MemCustomProductsRepo([_customSauce]);
      final storage = _MemStorage(
        activeDraft: Dish.withProcess(id: 'd-search', process: HeatProcess.boil),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(repo),
            customProductsRepositoryProvider.overrideWithValue(customRepo),
            searchProvider.overrideWith(
              (ref) => SearchNotifier(
                repo,
                () => ref.read(customProductsProvider),
              ),
            ),
            sourceCountsProvider.overrideWith(
              (ref) async => const SourceCounts(
                skurikhin: 1,
                bls: 1,
                custom: 1,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SearchProductModal(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final customPill = find.byKey(const ValueKey('custom-source-pill'));
      expect(customPill, findsOneWidget);
      await tester.tap(customPill);
      await tester.pumpAndSettle();
      expect(find.text('Фирменный соус'), findsOneWidget);

      // Confirmation dialog prevents accidental custom product deletion.
      await tester.tap(find.byTooltip('Сведения о продукте').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить продукт'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить свой продукт?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(customRepo.items.length, 1);

      await tester.tap(find.byTooltip('Удалить продукт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(customRepo.items, isEmpty);

      // Reset source pill and open searchable category picker (>=8 groups).
      await tester.tap(customPill);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-filter-pill')));
      await tester.pumpAndSettle();

      final groupSearch = find.byKey(const ValueKey('group-filter-search'));
      expect(groupSearch, findsOneWidget);
      await tester.enterText(groupSearch, 'птица');
      await tester.pumpAndSettle();
      expect(find.text('Птица и дичь'), findsOneWidget);
    });
  });
}
