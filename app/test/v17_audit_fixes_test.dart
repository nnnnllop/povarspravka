import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/favorite_products_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'package:povarspravka/presentation/widgets/ingredient_card.dart';

const _potato = Product(
  id: 1,
  code: 'potato',
  name: 'Картофель',
  groupId: 1,
  source: 'skurikhin',
  wastePct: 20,
  protein: 2.0,
  fat: 0.4,
  carbs: 16.3,
  kcal: 77.0,
  measures: [
    ProductMeasure(id: 1, productId: 1, name: 'клубень', grams: 80),
  ],
);

class _FakeStorage extends DishStorageRepository {
  final DishStorageData _data;
  _FakeStorage(this._data);
  @override
  Future<DishStorageData> loadAll() async => _data;
  @override
  Future<void> saveAll({
    required Dish? activeDraft,
    required List<Dish> savedDishes,
  }) async {}
}

class _FakeProductRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    bool? isDish,
    int limit = 50,
  }) async =>
      const [_potato];
  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async =>
      const [];
}

class _MemCustomRepo extends CustomProductsRepository {
  @override
  Future<List<Product>> loadAll() async => const [];
  @override
  Future<void> saveAll(List<Product> products) async {}
}

class _MemFavRepo extends FavoriteProductsRepository {
  @override
  Future<List<Product>> loadAll() async => const [];
  @override
  Future<void> saveAll(List<Product> favorites) async {}
}

void main() {
  testWidgets('F01 IngredientCard shows gross label only when isGross is true',
      (tester) async {
    const netIng = Ingredient(
      id: 'i-net',
      product: _potato,
      weightGrams: 100,
      isGross: false,
    );
    const grossIng = Ingredient(
      id: 'i-gross',
      product: _potato,
      weightGrams: 100,
      isGross: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              IngredientCard(
                index: 1,
                ingredient: netIng,
                onTap: () {},
                onDelete: () {},
              ),
              IngredientCard(
                index: 2,
                ingredient: grossIng,
                onTap: () {},
                onDelete: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Нетто 100 г'), findsOneWidget);
    expect(find.text('Нетто 80 г'), findsOneWidget);
    expect(find.text('Введено брутто 100 г · отходы 20 %'), findsOneWidget);
    expect(find.textContaining('брутто'), findsOneWidget);
  });

  testWidgets('F03 CustomNumpadSheet live kcal matches Ingredient.blankKcalInDish',
      (tester) async {
    const ing = Ingredient(
      id: 'p1',
      product: _potato,
      weightGrams: 100,
      isGross: false,
    );
    expect(ing.blankKcalInDish, 76.8);

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

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('numpad-live-macros')),
        matching: find.textContaining('76,8'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('numpad-live-macros')),
        matching: find.text('77 ккал'),
      ),
      findsNothing,
    );
  });

  testWidgets('F04 CustomNumpadSheet keys support SemanticsAction.tap',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final handle = tester.ensureSemantics();
    try {
      double? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomNumpadSheet(
                product: _potato,
                initialGrams: 100,
                onConfirm: (g, _) => confirmed = g,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      tester.semantics.tap(find.semantics.byLabel('7'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('0'));
      await tester.pumpAndSettle();
      tester.semantics.tap(
        find.semantics.byLabel('Удалить символ. Долгое нажатие — сброс'),
      );
      await tester.pumpAndSettle();
      expect(find.text('7'), findsWidgets);

      tester.semantics.tap(find.semantics.byLabel('Сбросить значение'));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsWidgets);

      tester.semantics.tap(find.semantics.byLabel('7'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('0'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Добавить'));
      await tester.pumpAndSettle();
      expect(confirmed, 70.0);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('HomeScreen selection mode starts empty (Выбрано: 0) and fits 320x568 @2x',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dishes = [
      Dish(
        id: 'd1',
        title: 'Блюдо 1',
        ingredients: const [Ingredient(id: 'i1', product: _potato, weightGrams: 100)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      Dish(
        id: 'd2',
        title: 'Блюдо 2',
        ingredients: const [Ingredient(id: 'i2', product: _potato, weightGrams: 150)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2.0),
        ),
        child: ProviderScope(
          overrides: [
            dishStorageRepositoryProvider
                .overrideWithValue(_FakeStorage(DishStorageData(savedDishes: dishes))),
            productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
            customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
            favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-select-mode-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Выбрано: 0'), findsOneWidget);
    expect(find.text('Сравнить'), findsOneWidget);
    expect(find.text('Меню'), findsOneWidget);
    expect(find.text('Экспорт'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CustomNumpadSheet keeps live caption visible on 320x568 @2.0x',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2.0),
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CustomNumpadSheet(
              product: _potato,
              initialGrams: 100,
              initialIsGross: true,
              onConfirm: (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final captionRect = tester.getRect(find.textContaining('съедобная часть 80 г'));
    final quickRect = tester.getRect(find.text('+10 г'));
    expect(captionRect.bottom, lessThanOrEqualTo(quickRect.top + 1.0));
    expect(find.text('Добавить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
