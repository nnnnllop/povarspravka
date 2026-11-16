import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';

class _MemStorage extends DishStorageRepository {
  Dish? _draft;
  List<Dish> _saved = const [];

  @override
  Future<DishStorageData> loadAll() async =>
      DishStorageData(activeDraft: _draft, savedDishes: _saved);

  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {
    _draft = activeDraft;
    _saved = List<Dish>.from(savedDishes);
  }

  @override
  Future<String?> resolveStorageDirectoryPath() async => '/tmp/povarspravka';
}

const _potato = Product(
  id: 1,
  code: 'pot',
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
  id: 2,
  code: 'chk',
  name: 'Курица (грудка)',
  groupId: 101,
  source: 'bls',
  protein: 22.0,
  fat: 2.0,
  carbs: 0.0,
  kcal: 110,
);

class _FakeProductRepo extends ProductRepository {
  final List<Product> products = const [_potato, _chicken];

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
        FoodGroup(id: 101, code: 'meat', name: 'Птица'),
      ];

  @override
  Future<Map<String, int>> getCountBySource({bool? isDish}) async {
    final matching = products.where((p) => isDish == null || p.isDishOnly == isDish);
    return {
      'skurikhin': matching.where((p) => p.source == 'skurikhin').length,
      'bls': matching.where((p) => p.source == 'bls').length,
      'supplement': 0,
    };
  }

  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async => const [];
}

class _MemCustomProductsRepo extends CustomProductsRepository {
  List<Product> items = const [];

  @override
  Future<List<Product>> loadAll() async => items;

  @override
  Future<void> saveAll(List<Product> products) async {
    items = List<Product>.from(products);
  }
}

Widget _wrapWithHost(
  Widget child, {
  required _MemStorage storage,
  _FakeProductRepo? repo,
  _MemCustomProductsRepo? customRepo,
}) {
  return ProviderScope(
    overrides: [
      dishStorageRepositoryProvider.overrideWithValue(storage),
      productRepositoryProvider.overrideWithValue(repo ?? _FakeProductRepo()),
      customProductsRepositoryProvider
          .overrideWithValue(customRepo ?? _MemCustomProductsRepo()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v1.2 P0-1: dirty-state & discardChanges', () {
    test('edits stay dirty across autosaves and discardChanges reverts saved dish',
        () async {
      final storage = _MemStorage();
      final saved = Dish(
        id: 'dish-1',
        title: 'Пюре',
        ingredients: const [
          Ingredient(id: 'ing-1', product: _potato, weightGrams: 100),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      storage._saved = [saved];

      final savedNotifier = SavedDishesNotifier(storage);
      final dishNotifier = DishNotifier(
        storage: storage,
        savedDishesNotifier: savedNotifier,
      );
      addTearDown(dishNotifier.dispose);
      addTearDown(savedNotifier.dispose);
      await dishNotifier.flushPendingSaves();

      dishNotifier.loadDish(saved);
      expect(dishNotifier.isDirty, isFalse);

      dishNotifier.setTitle('Пюре новое');
      await dishNotifier.flushPendingSaves();
      expect(dishNotifier.isDirty, isTrue,
          reason: 'autosave writes draft only and must not clear isDirty');

      dishNotifier.discardChanges();
      await dishNotifier.flushPendingSaves();
      expect(dishNotifier.state.title, 'Пюре');
      expect(dishNotifier.isDirty, isFalse);

      // New unsaved draft: discardChanges clears back to empty clean draft.
      dishNotifier.createNewDish();
      dishNotifier.addIngredient(_chicken, 150);
      await dishNotifier.flushPendingSaves();
      expect(dishNotifier.isDirty, isTrue);

      dishNotifier.discardChanges();
      await dishNotifier.flushPendingSaves();
      expect(dishNotifier.state.ingredients, isEmpty);
      expect(dishNotifier.isDirty, isFalse);
    });

    testWidgets(
        'RecipeEditorScreen explicit save button & _confirmDiscardChanges actions',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      final original = Dish(
        id: 'dish-edit',
        title: 'Исходный суп',
        ingredients: const [
          Ingredient(id: 'i-1', product: _potato, weightGrams: 200),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      storage._saved = [original];

      await tester.pumpWidget(_wrapWithHost(const HomeScreen(), storage: storage));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Исходный суп'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Название блюда'),
        'Испорченное имя',
      );
      await tester.pump();

      // Back -> "Выйти без сохранения" reverts dish to original snapshot.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Не сохранять изменения?'), findsOneWidget);
      await tester.tap(find.text('Выйти без сохранения'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      expect(container.read(dishProvider).title, 'Исходный суп');
      expect(container.read(savedDishesProvider).single.title, 'Исходный суп');

      // Re-open, edit, and save explicitly via AppBar bookmark button.
      await tester.tap(find.text('Исходный суп').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название блюда'),
        'Суп v1.2',
      );
      await tester.pump();
      expect(container.read(dishProvider.notifier).isDirty, isTrue);

      await tester.tap(find.byKey(const ValueKey('save-recipe-btn')));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider.notifier).isDirty, isFalse);
      expect(container.read(savedDishesProvider).single.title, 'Суп v1.2');

      // Edit again and test "Сохранить и выйти".
      await tester.enterText(
        find.widgetWithText(TextField, 'Название блюда'),
        'Суп финальный',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить и выйти'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        container.read(savedDishesProvider).single.title,
        'Суп финальный',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2 P0-2 & P0-3: HomeScreen draft guard & catalog add', () {
    testWidgets(
        'title-only active draft shows Продолжить расчёт and preserves title; '
        'SavedDishCard confirms dirty replacement with Сохранить и продолжить',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      final savedOther = Dish(
        id: 'other',
        title: 'Котлеты',
        ingredients: const [
          Ingredient(id: 'o-1', product: _chicken, weightGrams: 180),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      storage._saved = [savedOther];

      await tester.pumpWidget(_wrapWithHost(const HomeScreen(), storage: storage));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      container.read(dishProvider.notifier).setTitle('Название без продуктов');
      await tester.pumpAndSettle();

      expect(find.text('Открытый расчёт'), findsOneWidget);
      expect(find.text('Название без продуктов'), findsOneWidget);
      expect(find.text('Ингредиенты ещё не добавлены'), findsOneWidget);
      expect(find.text('Продолжить расчёт'), findsOneWidget);

      await tester.tap(find.text('Продолжить расчёт'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);
      expect(container.read(dishProvider).title, 'Название без продуктов');

      // Add an ingredient so "Сохранить и продолжить" is available, go back cleanly.
      container.read(dishProvider.notifier).addIngredient(_potato, 120);
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Не сохранять изменения?'), findsOneWidget);
      await tester.tap(find.text('Остаться'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);

      // Navigate back via Navigator.pop to reach HomeScreen with dirty draft.
      Navigator.of(tester.element(find.byType(RecipeEditorScreen))).pop();
      await tester.pumpAndSettle();

      // Tapping SavedDishCard asks confirmation; Cancel stays, Save & Continue persists.
      await tester.tap(find.text('Котлеты'));
      await tester.pumpAndSettle();
      expect(find.text('Сохранить текущее блюдо?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.text('Котлеты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить и продолжить'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorScreen), findsOneWidget);
      expect(container.read(dishProvider).id, 'other');
      expect(
        container.read(savedDishesProvider).any(
              (d) => d.title == 'Название без продуктов',
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SearchMode.browseCatalog -> ProductInfoCardSheet -> CustomNumpadSheet adds '
        'ingredient, closes modal, and calls onAddedFromCatalog', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      await tester.pumpWidget(_wrapWithHost(const HomeScreen(), storage: storage));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Справочник'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchProductModal), findsOneWidget);

      await tester.tap(find.text('Картофель').first);
      await tester.pumpAndSettle();
      expect(find.byType(ProductInfoCardSheet), findsOneWidget);
      expect(find.text('Добавить в расчет'), findsOneWidget);

      await tester.tap(find.text('Добавить в расчет'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomNumpadSheet), findsOneWidget);

      await tester.ensureVisible(find.text('Добавить в блюдо'));
      await tester.tap(find.text('Добавить в блюдо'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchProductModal), findsNothing);
      expect(find.byType(RecipeEditorScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)),
      );
      expect(container.read(dishProvider).ingredients, hasLength(1));
      expect(container.read(dishProvider).ingredients.single.product.id, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2 P0-4 & UI controls', () {
    testWidgets(
        '_RecipeSettingsDialog buffers HeatProcess until Применить; '
        'MacroSummaryBar portion preset chips update portion grams',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      final dish = Dish(
        id: 'd-settings',
        title: 'Каша',
        process: HeatProcess.cold,
        ingredients: const [
          Ingredient(id: 'i-1', product: _potato, weightGrams: 300),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      storage._draft = dish;

      await tester.pumpWidget(
        _wrapWithHost(const RecipeEditorScreen(), storage: storage),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)),
      );
      expect(container.read(dishProvider).process, HeatProcess.cold);

      await tester.tap(find.byTooltip('Параметры'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('heat-process')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(HeatProcess.boil.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider).process, HeatProcess.cold,
          reason: 'Cancel must discard buffered HeatProcess change');

      await tester.tap(find.byTooltip('Параметры'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('heat-process')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(HeatProcess.boil.label).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(container.read(dishProvider).process, HeatProcess.boil);

      // Portion preset chips on MacroSummaryBar.
      final calc = CalculationEngine.calculate(
        container.read(dishProvider).copyWith(customYieldGrams: 300),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: MacroSummaryBar(result: calc)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('portion-preset-200')));
      await tester.tap(find.byKey(const ValueKey('portion-preset-200')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Порция 200 г:'), findsOneWidget);
      final portionField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('portion-grams')),
      );
      expect(portionField.controller?.text, '200');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SearchProductModal source menu "all", alreadyInDish edit + numpad-delete, '
        'and PopScope filter reset on exit', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      final repo = _FakeProductRepo();
      final draft = Dish(
        id: 'd-pick',
        title: 'Салат',
        ingredients: const [
          Ingredient(id: 'i-1', product: _potato, weightGrams: 100),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      storage._draft = draft;

      await tester.pumpWidget(_wrapWithHost(const HomeScreen(), storage: storage, repo: repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить расчёт'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Добавить продукт'));
      await tester.pumpAndSettle();

      // Badge shows product already in dish.
      expect(find.text('в блюде · 100 г'), findsOneWidget);

      // Source filter: Skurikhin -> hides chicken, then "Все источники" shows both.
      await tester.tap(find.byTooltip('Источник справочника'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Скурихин').last);
      await tester.pumpAndSettle();
      expect(find.text('Курица (грудка)'), findsNothing);

      await tester.tap(find.byTooltip('Источник справочника'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Все источники').last);
      await tester.pumpAndSettle();
      expect(find.text('Все базы'), findsOneWidget);
      expect(find.text('Курица (грудка)'), findsOneWidget);

      // Type a query and verify Картофель row opens edit numpad with numpad-delete.
      await tester.enterText(find.byType(TextField).first, 'Карт');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Картофель').first);
      await tester.pumpAndSettle();
      expect(find.text('Сохранить изменения'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('numpad-delete')));
      await tester.tap(find.byKey(const ValueKey('numpad-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Удалено: Картофель'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchProductModal)),
      );
      expect(container.read(dishProvider).ingredients, isEmpty);

      // Re-select source filter before popping via Android/Nav back; PopScope resets filters.
      await tester.tap(find.byTooltip('Источник справочника'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('BLS').last);
      await tester.pumpAndSettle();
      expect(container.read(searchProvider).selectedSource, 'bls');
      expect(container.read(searchProvider).query, 'Карт');

      Navigator.of(tester.element(find.byType(SearchProductModal))).pop();
      await tester.pumpAndSettle();
      expect(container.read(searchProvider).query, isEmpty);
      expect(container.read(searchProvider).selectedSource, isNull);
      expect(container.read(searchProvider).selectedIsDish, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'CustomNumpadSheet key-C resets to 0 and numpad-live-macros updates live',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomNumpadSheet(
                product: _potato.copyWith(wastePct: 0),
                initialGrams: 100,
                onConfirm: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial 100g of _potato (77 kcal, P 2.0) -> live macros show 77 ккал.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('numpad-live-macros')),
          matching: find.textContaining('77'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('key-2')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.tap(find.byKey(const ValueKey('key-0')));
      await tester.pump();

      // 200g -> 154 ккал.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('numpad-live-macros')),
          matching: find.textContaining('154'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('key-C')));
      await tester.tap(find.byKey(const ValueKey('key-C')));
      await tester.pump();
      final readout = tester
          .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
          .child as Text;
      expect(readout.data, '0');
      expect(tester.takeException(), isNull);
    });
  });

  group('v1.2 polish: custom products, filters, yield numpad & inspector portion',
      () {
    test('CustomProductsRepository roundtrips custom products atomically',
        () async {
      final dir = Directory.systemTemp.createTempSync('custom_prod_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final repo = CustomProductsRepository(storageDirectory: dir);
      expect(await repo.loadAll(), isEmpty);

      const custom = Product(
        id: -1000,
        code: 'USER-1000',
        name: 'Соус фирменный',
        nameNorm: 'соус фирменный',
        groupId: 0,
        source: 'custom',
        protein: 3.5,
        fat: 12.0,
        carbs: 8.5,
        kcal: 156.0,
      );
      await repo.saveAll([custom]);

      final reloaded = await repo.loadAll();
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, -1000);
      expect(reloaded.single.name, 'Соус фирменный');
      expect(reloaded.single.source, 'custom');
      expect(CustomProductsRepository.nextId(reloaded), -1001);
    });

    testWidgets(
        'HomeScreen confirms recipe delete with Undo and searches saved dishes',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      storage._saved = [
        Dish(
          id: 's-1',
          title: 'Суп куриный',
          ingredients: const [
            Ingredient(id: 'i-1', product: _chicken, weightGrams: 150),
          ],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        Dish(
          id: 's-2',
          title: 'Пюре картофельное',
          ingredients: const [
            Ingredient(id: 'i-2', product: _potato, weightGrams: 200),
          ],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];

      await tester.pumpWidget(_wrapWithHost(const HomeScreen(), storage: storage));
      await tester.pumpAndSettle();

      // Search saved dishes.
      await tester.tap(find.byKey(const ValueKey('home-library-search-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('home-library-search')), 'Пюре');
      await tester.pumpAndSettle();
      expect(find.text('Пюре картофельное'), findsOneWidget);
      expect(find.text('Суп куриный'), findsNothing);

      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Суп куриный'), findsOneWidget);

      // Delete first dish -> Cancel keeps both -> Delete removes + Undo restores.
      await tester.tap(find.byTooltip('Действия с блюдом').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить блюдо?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('Суп куриный'), findsOneWidget);

      await tester.tap(find.byTooltip('Действия с блюдом').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').last);
      await tester.pumpAndSettle();
      expect(find.text('Суп куриный'), findsNothing);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(find.text('Суп куриный'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'RecipeEditorScreen yield-numpad-btn & Inspector Step 5 portion calculator',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      storage._draft = Dish(
        id: 'd-yield',
        title: 'Пюре',
        process: HeatProcess.boil,
        ingredients: const [
          Ingredient(id: 'i-1', product: _potato, weightGrams: 250, isGross: true),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _wrapWithHost(const RecipeEditorScreen(), storage: storage),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('yield-numpad-btn')));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleGramsNumpadSheet), findsOneWidget);

      await tester.tap(find.text('+250 г'));
      await tester.tap(find.text('+100 г'));
      await tester.pump();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(RecipeEditorScreen)),
      );
      expect(container.read(dishProvider).customYieldGrams, 350.0);
      expect(find.textContaining('/ 100 г'), findsOneWidget);

      // Open Инспектор расчёта -> verify Step 5 portion calculator works live.
      await tester.tap(find.byTooltip('Инспектор расчёта'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('inspector-portion-preset-250')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('inspector-portion-preset-250')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Порция 250 г:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SearchProductModal category filter, multi-existing sheet & custom product creation',
        (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final storage = _MemStorage();
      final customRepo = _MemCustomProductsRepo();
      storage._draft = Dish(
        id: 'd-multi',
        title: 'Сборное',
        ingredients: const [
          Ingredient(id: 'i-1', product: _potato, weightGrams: 100),
          Ingredient(id: 'i-2', product: _potato, weightGrams: 150),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      await tester.pumpWidget(
        _wrapWithHost(
          const HomeScreen(),
          storage: storage,
          customRepo: customRepo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить расчёт'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить продукт'));
      await tester.pumpAndSettle();

      // Category filter: Овощи hides Курица.
      await tester.tap(find.byKey(const ValueKey('group-filter-pill')));
      await tester.pumpAndSettle();
      expect(find.text('Категория продуктов'), findsOneWidget);
      await tester.tap(find.text('Овощи').last);
      await tester.pumpAndSettle();
      expect(find.text('Курица (грудка)'), findsNothing);

      // Reset category filter back to all.
      await tester.tap(find.byKey(const ValueKey('group-filter-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Все категории').last);
      await tester.pumpAndSettle();
      expect(find.text('Курица (грудка)'), findsOneWidget);

      // Tapping Картофель (already added twice) opens multi-existing chooser.
      await tester.tap(find.text('Картофель').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Изменить позицию 1'), findsOneWidget);
      expect(find.textContaining('Изменить позицию 2'), findsOneWidget);
      await tester.tap(find.text('Добавить ещё раз'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomNumpadSheet), findsOneWidget);
      Navigator.pop(tester.element(find.byType(CustomNumpadSheet)));
      await tester.pumpAndSettle();

      // Create custom product -> opens CustomNumpadSheet -> adds to dish.
      await tester.tap(find.byKey(const ValueKey('create-custom-product-btn')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('custom-name')), 'Соус песто');
      await tester.enterText(find.byKey(const ValueKey('custom-protein')), '4');
      await tester.enterText(find.byKey(const ValueKey('custom-fat')), '30');
      await tester.enterText(find.byKey(const ValueKey('custom-carbs')), '5');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('custom-kcal'))).controller?.text,
        '306,0',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('custom-save-btn')));
      await tester.tap(find.byKey(const ValueKey('custom-save-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(CustomNumpadSheet), findsOneWidget);
      await tester.tap(find.text('Добавить в блюдо'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchProductModal)),
      );
      expect(
        container.read(dishProvider).ingredients.last.product.name,
        'Соус песто',
      );
      expect(
        container.read(dishProvider).ingredients.last.product.source,
        'custom',
      );
      expect(customRepo.items, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
