import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/loss_group.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/backup_service.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/favorite_products_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';

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

const _butter = Product(
  id: 102,
  code: '05-102',
  name: 'Масло сливочное',
  groupId: 5,
  source: 'skurikhin',
  wastePct: 0,
  protein: 0.8,
  fat: 82.5,
  carbs: 0.8,
  kcal: 748,
);

const _chicken = Product(
  id: 103,
  code: '03-103',
  name: 'Курица (грудка)',
  groupId: 101,
  source: 'bls',
  wastePct: 0,
  protein: 23.0,
  fat: 1.9,
  carbs: 0.0,
  kcal: 113,
);

const _turkey = Product(
  id: 104,
  code: '03-104',
  name: 'Индейка (филе)',
  groupId: 101,
  source: 'bls',
  wastePct: 0,
  protein: 21.6,
  fat: 1.5,
  carbs: 0.0,
  kcal: 104,
);

const _customSauce = Product(
  id: -1,
  code: 'USER-1',
  name: 'Соус демиглас',
  nameNorm: 'соус демиглас',
  groupId: 0,
  source: 'custom',
  wastePct: 0,
  protein: 4.0,
  fat: 8.0,
  carbs: 6.0,
  kcal: 112,
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

class _MemCustomRepo extends CustomProductsRepository {
  List<Product> items = const [];

  @override
  Future<List<Product>> loadAll() async => items;

  @override
  Future<void> saveAll(List<Product> products) async {
    items = List<Product>.from(products);
  }
}

class _MemFavRepo extends FavoriteProductsRepository {
  List<Product> items = const [];

  @override
  Future<List<Product>> loadAll() async => items;

  @override
  Future<void> saveAll(List<Product> products) async {
    items = List<Product>.from(products);
  }
}

class _FakeProductRepo extends ProductRepository {
  final List<Product> products = const [_potato, _butter, _chicken, _turkey];

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
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [
        FoodGroup(id: 1, code: 'veg', name: 'Овощи'),
        FoodGroup(id: 5, code: 'oil', name: 'Масла'),
        FoodGroup(id: 101, code: 'poultry', name: 'Птица'),
      ];

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('v1.4 Core models, repositories & single-recipe share', () {
    test('Dish.category serializes only when set and stays backward compatible',
        () {
      final legacy = Dish(
        id: 'old-1',
        title: 'Старое блюдо',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final legacyJson = legacy.toJson();
      expect(legacyJson.containsKey('category'), isFalse);
      expect(Dish.fromJson(legacyJson).category, isNull);

      final categorized = legacy.copyWith(category: DishCategories.first);
      final catJson = categorized.toJson();
      expect(catJson['category'], DishCategories.first);
      expect(Dish.fromJson(catJson).category, DishCategories.first);
      expect(DishCategories.labelOf(DishCategories.first), 'Первые');

      final cleared = categorized.copyWith(clearCategory: true);
      expect(cleared.category, isNull);
    });

    test('FavoriteProductsRepository persists atomically and handles corrupt json',
        () async {
      final dir = await Directory.systemTemp.createTemp('povarspravka_fav_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final repo = FavoriteProductsRepository(storageDirectory: dir);
      final notifier = FavoriteProductsNotifier(repo);
      addTearDown(notifier.dispose);
      await notifier.flush();

      expect(await notifier.toggleFavorite(_butter), isTrue);
      expect(notifier.isFavorite(_butter.id), isTrue);
      await notifier.flush();

      final reloaded =
          await FavoriteProductsRepository(storageDirectory: dir).loadAll();
      expect(reloaded.map((p) => p.id), [_butter.id]);

      expect(await notifier.toggleFavorite(_butter), isFalse);
      expect(notifier.isFavorite(_butter.id), isFalse);
      await notifier.flush();

      final file =
          File('${dir.path}${Platform.pathSeparator}favorite_products.json');
      await file.writeAsString('{broken', flush: true);
      final fallback =
          await FavoriteProductsRepository(storageDirectory: dir).loadAll();
      expect(fallback, isEmpty);
    });

    test('BackupService includes favorites and encodes single dish with referenced custom products',
        () {
      final dish = Dish.withProcess(
        id: 'd-share',
        title: 'Стейк с соусом',
        category: DishCategories.main,
        process: HeatProcess.fry,
        customYieldGrams: 250,
        ingredients: const [
          Ingredient(id: 'i1', product: _chicken, weightGrams: 200),
          Ingredient(id: 'i2', product: _customSauce, weightGrams: 50),
        ],
      );

      final singleJson = BackupService.encodeSingleDishBackup(
        dish,
        customProducts: const [_customSauce],
      );
      final parsedSingle = BackupService.parseBackup(singleJson);
      expect(parsedSingle.savedDishes.length, 1);
      expect(parsedSingle.savedDishes.first.title, 'Стейк с соусом');
      expect(parsedSingle.savedDishes.first.category, DishCategories.main);
      expect(parsedSingle.customProducts.length, 1);
      expect(parsedSingle.customProducts.first.name, 'Соус демиглас');
      expect(parsedSingle.favoriteProducts, isEmpty);

      final fullJson = BackupService.encodeBackup(
        savedDishes: [dish],
        customProducts: const [_customSauce],
        favoriteProducts: const [_butter, _potato],
      );
      final parsedFull = BackupService.parseBackup(fullJson);
      expect(parsedFull.favoriteProducts.map((p) => p.id),
          [_butter.id, _potato.id]);
    });

    test('DishNotifier.replaceIngredientProduct keeps weight, isGross and processOverride while clearing groupOverride',
        () async {
      final storage = _MemStorage(
        activeDraft: Dish.withProcess(
          id: 'd-rep',
          title: 'Филе',
          process: HeatProcess.bake,
          ingredients: const [
            Ingredient(
              id: 'ing-1',
              product: _chicken,
              weightGrams: 180,
              isGross: true,
              groupOverride: LossGroup.meat,
              processOverride: HeatProcess.fry,
            ),
          ],
        ),
      );
      final notifier = DishNotifier(storage: storage);
      addTearDown(notifier.dispose);
      await notifier.flushPendingSaves();

      expect(notifier.replaceIngredientProduct('ing-1', _turkey), isTrue);
      final ing = notifier.state.ingredients.single;
      expect(ing.product.id, _turkey.id);
      expect(ing.weightGrams, 180);
      expect(ing.isGross, isTrue);
      expect(ing.processOverride, HeatProcess.fry);
      expect(ing.groupOverride, isNull);
    });
  });

  group('v1.4 Widget flows', () {
    testWidgets(
        'RecipeEditorScreen: scale by target weight, replace product with Undo, and share single recipe',
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
          id: 'd-v14',
          title: 'Пюре с курицей',
          process: HeatProcess.boil,
          customYieldGrams: 400,
          ingredients: const [
            Ingredient(id: 'i1', product: _chicken, weightGrams: 200),
            Ingredient(id: 'i2', product: _potato, weightGrams: 250),
          ],
        ),
      );
      final repo = _FakeProductRepo();
      final container = ProviderContainer(
        overrides: [
          dishStorageRepositoryProvider.overrideWithValue(storage),
          productRepositoryProvider.overrideWithValue(repo),
          customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
          favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
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

      // 1) Scale by target weight: 400 g yield -> 1000 g yield (×2.5).
      await tester.tap(find.byTooltip('Другие действия'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Масштабировать веса'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Целевой вес'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scale-target-preset-1000')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scale-computed-factor')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scale-apply-btn')));
      await tester.pumpAndSettle();

      expect(container.read(dishProvider).customYieldGrams, 1000);
      expect(container.read(dishProvider).ingredients[0].weightGrams, 500);
      expect(container.read(dishProvider).ingredients[1].weightGrams, 625);

      // 2) Replace ingredient product via CustomNumpadSheet header button.
      await tester.tap(find.text('Курица (грудка)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('numpad-replace-product')));
      await tester.pumpAndSettle();

      expect(find.byType(SearchProductModal), findsOneWidget);
      await tester.tap(find.text('Индейка (филе)'));
      await tester.pumpAndSettle();

      expect(container.read(dishProvider).ingredients.first.product.id, _turkey.id);
      expect(container.read(dishProvider).ingredients.first.weightGrams, 500);

      // Undo replacement restores original product.
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider).ingredients.first.product.id, _chicken.id);

      // 3) Share single recipe as JSON.
      await tester.tap(find.byTooltip('Другие действия'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Поделиться рецептом'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-recipe-copy-btn')));
      await tester.pumpAndSettle();

      final parsed = BackupService.parseBackup(copied);
      expect(parsed.savedDishes.length, 1);
      expect(parsed.savedDishes.first.title, 'Пюре с курицей');
    });

    testWidgets(
        'SearchProductModal pins favorites in ProductInfoCardSheet and shows Избранное section and pill',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeProductRepo();
      final favRepo = _MemFavRepo();
      final storage = _MemStorage(
        activeDraft: Dish.withProcess(id: 'd-fav', process: HeatProcess.cold),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(repo),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(favRepo),
            searchProvider.overrideWith(
              (ref) => SearchNotifier(repo, () => ref.read(customProductsProvider)),
            ),
            sourceCountsProvider.overrideWith(
              (ref) async => const SourceCounts(skurikhin: 2, bls: 2),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SearchProductModal(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open info card of first product and star it.
      await tester.tap(find.byTooltip('Сведения о продукте').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('toggle-favorite-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закрыть').last);
      await tester.pumpAndSettle();

      expect(favRepo.items.length, 1);
      expect(find.byKey(const ValueKey('favorites-filter-pill')), findsOneWidget);
      expect(find.text('Избранное'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('favorites-filter-pill')));
      await tester.pumpAndSettle();
      expect(find.text(favRepo.items.first.name), findsOneWidget);
    });

    testWidgets(
        'MacroSummaryBar inspector displays ingredient contribution breakdown with Ккал / Б / Ж / У tabs at 320x568 @2x',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dish = Dish.withProcess(
        id: 'd-contrib',
        title: 'Курица со сливочным маслом',
        process: HeatProcess.bake,
        customYieldGrams: 220,
        ingredients: const [
          Ingredient(id: 'i1', product: _chicken, weightGrams: 200),
          Ingredient(id: 'i2', product: _butter, weightGrams: 50),
        ],
      );
      final calc = CalculationEngine.calculate(dish);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: MacroSummaryBar(
                result: calc,
                compact: true,
                ingredients: dish.ingredients,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Инспектор расчёта'));
      await tester.pumpAndSettle();

      final section = find.byKey(const ValueKey('inspector-contribution-section'));
      await tester.scrollUntilVisible(
        section,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(section, findsOneWidget);
      expect(find.text('Масло сливочное'), findsOneWidget);
      expect(find.text('Курица (грудка)'), findsOneWidget);

      await tester.tap(find.text('Б'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'HomeScreen filters dishes by category, sorts by title and kcal/100g, and shares single dish',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dishA = Dish.withProcess(
        id: 'd-a',
        title: 'Борщ',
        category: DishCategories.first,
        process: HeatProcess.boil,
        customYieldGrams: 500,
        updatedAt: DateTime(2026, 11, 10),
        ingredients: const [
          Ingredient(id: 'ia', product: _potato, weightGrams: 200),
        ],
      );
      final dishB = Dish.withProcess(
        id: 'd-b',
        title: 'Арбузный салат с маслом',
        category: DishCategories.salad,
        process: HeatProcess.cold,
        customYieldGrams: 100,
        updatedAt: DateTime(2026, 11, 18),
        ingredients: const [
          Ingredient(id: 'ib', product: _butter, weightGrams: 50),
        ],
      );
      final storage = _MemStorage(savedDishes: [dishA, dishB]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Category chips appear for used categories.
      expect(find.byKey(const ValueKey('home-cat-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-cat-first')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-cat-salad')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-cat-first')));
      await tester.pumpAndSettle();
      expect(find.text('Борщ'), findsOneWidget);
      expect(find.text('Арбузный салат с маслом'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-cat-all')));
      await tester.pumpAndSettle();
      expect(find.text('Борщ'), findsOneWidget);
      expect(find.text('Арбузный салат с маслом'), findsOneWidget);

      // Sort by title (А–Я) puts 'Арбузный...' above 'Борщ'.
      await tester.tap(find.byKey(const ValueKey('home-library-sort-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По названию (А–Я)'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Арбузный салат с маслом')).dy,
        lessThan(tester.getTopLeft(find.text('Борщ')).dy),
      );

      // Sort by kcal/100g keeps higher-density butter dish above potato dish.
      await tester.tap(find.byKey(const ValueKey('home-library-sort-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По ккал на 100 г'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Арбузный салат с маслом')).dy,
        lessThan(tester.getTopLeft(find.text('Борщ')).dy),
      );
    });
  });
}
