import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/favorite_products_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/app_buttons.dart';
import 'package:povarspravka/presentation/widgets/batch_export_sheet.dart';
import 'package:povarspravka/presentation/widgets/calc_error_banner.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'package:povarspravka/presentation/widgets/custom_product_form_sheet.dart';
import 'package:povarspravka/presentation/widgets/dish_comparison_sheet.dart';
import 'package:povarspravka/presentation/widgets/menu_builder_sheet.dart';

/// Продукт с расхождением ккал по источнику (47,0) и по формуле 4/9/4 (44,4).
const _apple = Product(
  id: 101,
  code: 'apple',
  name: 'Яблоки свежие',
  groupId: 10,
  source: 'skurikhin',
  wastePct: 12,
  protein: 0.4,
  fat: 0.4,
  carbs: 9.8,
  kcal: 47.0,
);

const _halva = Product(
  id: 102,
  code: 'rahat',
  name: 'Рахат-лукум с орехом',
  groupId: 11,
  source: 'skurikhin',
  wastePct: 0,
  protein: 0.8,
  fat: 0.7,
  carbs: 79.5,
  kcal: 316.0,
);

const _potato = Product(
  id: 103,
  code: 'potato',
  name: 'Картофель',
  groupId: 8,
  source: 'skurikhin',
  wastePct: 20,
  protein: 2.0,
  fat: 0.4,
  carbs: 16.3,
  kcal: 77.0,
);

const _customSemi = Product(
  id: -1,
  code: 'USER-1',
  name: 'Соус домашний полуфабрикат',
  groupId: 0,
  source: 'custom',
  wastePct: 0,
  protein: 3.0,
  fat: 5.0,
  carbs: 10.0,
  kcal: 97.0,
  isDish: true,
);

class _MemDishStorage extends DishStorageRepository {
  Dish? _draft;
  List<Dish> _saved;
  final bool throwOnLoad;

  _MemDishStorage({
    Dish? activeDraft,
    List<Dish> savedDishes = const [],
    this.throwOnLoad = false,
  })  : _draft = activeDraft,
        _saved = List<Dish>.from(savedDishes);

  @override
  Future<DishStorageData> loadAll() async {
    if (throwOnLoad) throw Exception('disk read error');
    return DishStorageData(
      activeDraft: _draft,
      savedDishes: List<Dish>.from(_saved),
    );
  }

  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {
    _draft = activeDraft;
    _saved = List<Dish>.from(savedDishes);
  }
}

class _FakeProductRepo extends ProductRepository {
  final List<Product> items;
  _FakeProductRepo(this.items);

  @override
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    bool? isDish,
    int limit = 50,
  }) async {
    return items.where((p) {
      if (isDish != null && p.isDishOnly != isDish) return false;
      if (source != null && p.source != source) return false;
      if (groupId != null && p.groupId != groupId) return false;
      if (query.trim().isNotEmpty &&
          !p.name.toLowerCase().contains(query.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [];

  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async =>
      const [];
}

class _MemCustomRepo extends CustomProductsRepository {
  final List<Product> _items;
  _MemCustomRepo([List<Product> items = const []])
      : _items = List<Product>.from(items);

  @override
  Future<List<Product>> loadAll() async => List<Product>.from(_items);

  @override
  Future<void> saveAll(List<Product> products) async {
    _items
      ..clear()
      ..addAll(products);
  }
}

class _MemFavRepo extends FavoriteProductsRepository {
  final List<Product> _items;
  _MemFavRepo([List<Product> items = const []])
      : _items = List<Product>.from(items);

  @override
  Future<List<Product>> loadAll() async => List<Product>.from(_items);

  @override
  Future<void> saveAll(List<Product> favorites) async {
    _items
      ..clear()
      ..addAll(favorites);
  }
}

void main() {
  group('v1.9.0 Data Safety (B-01..B-05, P2-7)', () {
    test('B-03 & P2-7: setCategory marks isDirty and setDishCategory keeps updatedAt',
        () async {
      final initialTs = DateTime(2026, 1, 10, 12, 0);
      final dish = Dish(
        id: 'd-cat',
        title: 'Суп',
        category: DishCategories.first,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 100),
        ],
        createdAt: initialTs,
        updatedAt: initialTs,
      );
      final storage = _MemDishStorage(activeDraft: dish, savedDishes: [dish]);
      final n = DishNotifier(storage: storage);
      final saved = SavedDishesNotifier(storage);
      saved.setInitialDishes([dish], dish);
      addTearDown(n.dispose);
      addTearDown(saved.dispose);
      await n.flushPendingSaves();

      expect(n.isDirty, isFalse);
      n.setCategory(DishCategories.main);
      expect(n.state.category, DishCategories.main);
      expect(n.isDirty, isTrue);

      await saved.setDishCategory('d-cat', DishCategories.main);
      expect(saved.state.single.category, DishCategories.main);
      expect(saved.state.single.updatedAt, initialTs);
    });

    test('B-04: clearIngredients keeps metadata/id and Undo restores items',
        () async {
      final dish = Dish.withProcess(
        id: 'd-clear',
        title: 'Гарнир',
        category: DishCategories.side,
        process: HeatProcess.boil,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 150),
        ],
      );
      final n = DishNotifier(storage: _MemDishStorage(activeDraft: dish));
      addTearDown(n.dispose);
      await n.flushPendingSaves();

      final prev = n.clearIngredients();
      expect(prev.ingredients.length, 1);
      expect(n.state.id, 'd-clear');
      expect(n.state.title, 'Гарнир');
      expect(n.state.category, DishCategories.side);
      expect(n.state.process, HeatProcess.boil);
      expect(n.state.ingredients, isEmpty);

      n.restoreIngredientsSnapshot(
        dishId: prev.id,
        ingredients: prev.ingredients,
        customYieldGrams: prev.customYieldGrams,
      );
      expect(n.state.ingredients.length, 1);
      expect(n.state.ingredients.single.weightGrams, 150);
    });

    testWidgets(
        'B-01: HomeScreen auto-saves clean unsaved draft content before opening saved dish',
        (tester) async {
      final unsavedDraft = Dish(
        id: 'new-unsaved',
        title: 'Несохранённый после перезапуска',
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 200),
        ],
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 2, 1),
      );
      final savedDish = Dish(
        id: 'saved-1',
        title: 'Старый суп',
        ingredients: const [
          Ingredient(id: 'i2', product: _apple, weightGrams: 100),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final storage = _MemDishStorage(
        activeDraft: unsavedDraft,
        savedDishes: [savedDish],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo(const [])),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(c.read(dishProvider.notifier).hasUnsavedDraftContent, isTrue);

      await tester.tap(find.text('Старый суп'));
      await tester.pumpAndSettle();

      final savedIds = c.read(savedDishesProvider).map((d) => d.id).toList();
      expect(savedIds, contains('new-unsaved'));
      expect(c.read(dishProvider).id, 'saved-1');
    });

    testWidgets(
        'B-02: deleting active dish from library clears draft and Undo restores both',
        (tester) async {
      final dish = Dish(
        id: 'd-active',
        title: 'Удаляемый суп',
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 120),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final storage = _MemDishStorage(activeDraft: dish, savedDishes: [dish]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo(const [])),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Действия с блюдом'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();

      final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(c.read(savedDishesProvider), isEmpty);
      expect(c.read(dishProvider).ingredients, isEmpty);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(c.read(savedDishesProvider).length, 1);
      expect(c.read(dishProvider).id, 'd-active');
      expect(c.read(dishProvider).ingredients.length, 1);
    });

    testWidgets(
        'P1-12: persistence load error shows load banner and hides _EmptyLibrary',
        (tester) async {
      final storage = _MemDishStorage(throwOnLoad: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(storage),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo(const [])),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('persistence-error-banner')), findsOneWidget);
      expect(find.textContaining('Не удалось прочитать'), findsOneWidget);
      expect(find.text('Сохранённых блюд пока нет'), findsNothing);
    });
  });

  group('v1.9.0 Unified 4/9/4 Kcal, Numpad & Search (B-07..B-12, A-01..A-04)', () {
    test('UiFormat uses 4/9/4 and prints source footnote when diff >= 1 kcal',
        () {
      expect(UiFormat.productKcal(_apple), 44.4);
      expect(UiFormat.sourceKcalFootnote(_apple), 'по источнику 47,0');
      expect(UiFormat.sourceKcalFootnote(_potato), isNull);
    });

    testWidgets('B-07: Search list, ProductInfoCardSheet & CustomNumpad agree on 44,4 kcal',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _FakeProductRepo(const [_apple]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(_MemDishStorage()),
            productRepositoryProvider.overrideWithValue(repo),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SearchProductModal()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('44,4 ккал'), findsOneWidget);
      await tester.tap(find.byTooltip('Сведения о продукте'));
      await tester.pumpAndSettle();
      expect(find.text('44,4 ккал'), findsOneWidget);
      expect(find.textContaining('по источнику 47,0'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Яблоки свежие'));
      await tester.pumpAndSettle();
      expect(find.textContaining('44,4 ккал / 100 г'), findsOneWidget);
      expect(find.text('по источнику 47,0'), findsOneWidget);
    });

    testWidgets('B-09: temporary wastePct edit in numpad does not pollute recent list',
        (tester) async {
      final repo = _FakeProductRepo(const [_potato]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider.overrideWithValue(_MemDishStorage()),
            productRepositoryProvider.overrideWithValue(repo),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SearchProductModal()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Картофель'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('35%'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('waste-edit-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('numpad-confirm')));
      await tester.pumpAndSettle();

      final c = ProviderScope.containerOf(
        tester.element(find.byType(SearchProductModal)),
      );
      expect(c.read(dishProvider).ingredients.single.product.wastePct, 35);
      expect(c.read(sessionRecentProductsProvider).single.wastePct, 20);
    });

    testWidgets(
        'B-10 & A-02..A-04: numpad commits weight before ⋮ action, immediate >=100% waste error, strict presets, liveRegion',
        (tester) async {
      double? committedGrams;
      var lossOpened = false;

      // 1. Рахат-лукум must NOT get ГОСТ 16% onion seasonal preset.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CustomNumpadSheet(
              key: const ValueKey('halva-numpad'),
              product: _halva,
              initialGrams: 100,
              onConfirm: (_, __) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('numpad-extras-toggle')), findsNothing);

      // 2. Картофель editing: modify weight, immediate >=100% error, commit before loss menu.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CustomNumpadSheet(
              key: const ValueKey('potato-numpad'),
              product: _potato,
              initialGrams: 100,
              initialIsGross: true,
              isEditing: true,
              onConfirm: (g, _) => committedGrams = g,
              onEditLoss: () => lossOpened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Immediate >=100% validation in waste mode + waste chip semantics.
      await tester.tap(find.byKey(const ValueKey('waste-edit-toggle')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Установить отходы 15%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('key-1')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();
      expect(find.textContaining('0 до 99,9'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('waste-edit-cancel')));
      await tester.pumpAndSettle();

      // Enter 250g and tap ⋮ -> Группа и обработка (commits 250g first).
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('numpad-more-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('numpad-edit-loss')));
      await tester.pumpAndSettle();
      expect(committedGrams, 250);
      expect(lossOpened, isTrue);
    });

    test('B-11: custom semi-finished dish appears in default Продукты filter',
        () async {
      final repo = _FakeProductRepo(const [_potato]);
      final notifier = SearchNotifier(repo, () => const [_customSemi]);
      addTearDown(notifier.dispose);
      notifier.setIsDishFilter(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.results.any((p) => p.id == _customSemi.id), isTrue);

      notifier.setIsDishFilter(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.state.results.any((p) => p.id == _customSemi.id), isTrue);
      expect(notifier.state.results.any((p) => p.id == _potato.id), isFalse);
    });

    testWidgets('B-06: BlankPreviewScreen shows CalcErrorBanner on invalid dish',
        (tester) async {
      final bad = Dish(
        id: 'bad',
        title: 'Плохой',
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 100),
        ],
        retentionProtein: 0,
        retentionFat: 0,
        retentionCarbs: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dishStorageRepositoryProvider
                .overrideWithValue(_MemDishStorage(activeDraft: bad)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const BlankPreviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalcErrorBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.9.0 Secondary Sheets (B-13..B-15, P1-5, P1-7)', () {
    testWidgets('MenuBuilderSheet shows no-yield banner and keeps sheet open on copy',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') return null;
        return null;
      });
      final dNoYield = Dish.withProcess(
        id: 'm1',
        title: 'Салат без веса',
        process: HeatProcess.cold,
        ingredients: const [
          Ingredient(id: 'i1', product: _apple, weightGrams: 100),
        ],
      );
      final dWithYield = Dish.withProcess(
        id: 'm2',
        title: 'Суп с весом',
        process: HeatProcess.boil,
        customYieldGrams: 60,
        ingredients: const [
          Ingredient(id: 'i2', product: _potato, weightGrams: 100),
        ],
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: MenuBuilderSheet(dishes: [dNoYield, dWithYield])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-no-yield-banner')), findsOneWidget);
      expect(find.textContaining('Салат без веса'), findsWidgets);

      // Decrement clamps to 10 g (60 - 50 = 10 g).
      await tester.ensureVisible(find.byKey(const ValueKey('menu-dec-m2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-dec-m2')));
      await tester.pumpAndSettle();
      expect(find.text('Порция · 10 г'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('menu-copy-text-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-builder-sheet')), findsOneWidget);
      expect(find.text('Сводка меню скопирована'), findsOneWidget);
    });

    testWidgets('DishComparisonSheet swaps dishes and uses full legend',
        (tester) async {
      final first = Dish.withProcess(
        id: 'c1',
        title: 'Борщ классический длинное название',
        process: HeatProcess.boil,
        customYieldGrams: 250,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 100),
        ],
      );
      final second = Dish.withProcess(
        id: 'c2',
        title: 'Каша рисовая молочная',
        process: HeatProcess.boil,
        customYieldGrams: 200,
        ingredients: const [
          Ingredient(id: 'i2', product: _apple, weightGrams: 100),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DishComparisonSheet(first: first, second: second),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 — Борщ классический длинное название'), findsOneWidget);
      expect(find.text('2 — Каша рисовая молочная'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('compare-swap-btn')));
      await tester.pumpAndSettle();
      expect(find.text('1 — Каша рисовая молочная'), findsOneWidget);
      expect(find.text('2 — Борщ классический длинное название'), findsOneWidget);
    });

    testWidgets('BatchExportSheet pluralizes and truncates skipped list at 5',
        (tester) async {
      final badDishes = [
        for (var i = 1; i <= 7; i++)
          Dish(
            id: 'bad-$i',
            title: 'Ошибочное $i',
            ingredients: const [
              Ingredient(id: 'i1', product: _potato, weightGrams: 100),
            ],
            retentionProtein: 0,
            retentionFat: 0,
            retentionCarbs: 0,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: BatchExportSheet(dishes: badDishes)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Выбрано 7 блюд'), findsOneWidget);
      expect(find.textContaining('и ещё 2'), findsOneWidget);
    });

    testWidgets('CustomProductFormSheet recalculates kcal on button tap',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: CustomProductFormSheet(
                initialName: 'Тест',
                initialProtein: 10,
                initialFat: 10,
                initialCarbs: 10,
                initialKcal: 999,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('custom-kcal-recalc-btn')));
      await tester.pumpAndSettle();
      final kcalField =
          tester.widget<TextField>(find.byKey(const ValueKey('custom-kcal')));
      expect(kcalField.controller?.text, '170,0');
    });
  });
}
