import 'dart:io';

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
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/batch_export_sheet.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'package:povarspravka/presentation/widgets/ingredient_card.dart';
import 'package:povarspravka/presentation/widgets/instrument_widgets.dart';

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
  test('Static token guardrails: zero Space.xN+2 and zero stray fontSize', () {
    final dirs = [
      Directory('lib/presentation'),
      Directory('lib/core/theme'),
    ];
    final arithmeticSpace = RegExp(r'Space\.x\d+\s*[+\-]\s*\d');
    final rawFontSize = RegExp(r'\bfontSize\s*:');
    final rawColorHex = RegExp(r'Color\(\s*0x');
    final strayIconSize = RegExp(r'\bIcon\([^)]*\bsize\s*:\s*(15|19|22)\b');
    final violations = <String>[];

    for (final dir in dirs) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final lineNum = i + 1;
          final line = lines[i];
          // Исключаем печатный документ бланка (>= 634) и определения AppTypography/AppColors.
          if (normalized.endsWith('blank_preview_screen.dart') &&
              lineNum >= 634) {
            continue;
          }
          if (arithmeticSpace.hasMatch(line)) {
            violations.add('$normalized:$lineNum arithmetic Space: $line');
          }
          if (!normalized.endsWith('app_typography.dart') &&
              rawFontSize.hasMatch(line)) {
            violations.add('$normalized:$lineNum raw fontSize: $line');
          }
          if (!normalized.endsWith('app_colors.dart') &&
              rawColorHex.hasMatch(line)) {
            violations.add('$normalized:$lineNum raw Color(0x...): $line');
          }
          if (strayIconSize.hasMatch(line)) {
            violations.add('$normalized:$lineNum stray Icon size: $line');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  testWidgets('IngredientCard preserves 3 colored macro dots and bold kcal',
      (tester) async {
    const ing = Ingredient(
      id: 'i1',
      product: _potato,
      weightGrams: 100,
      isGross: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: IngredientCard(
            index: 1,
            ingredient: ing,
            onTap: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3 круглые цветные точки (Б, Ж, У) и ни одной 4-й у ккал.
    final dots = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final dec = w.decoration;
      return dec is BoxDecoration && dec.shape == BoxShape.circle;
    });
    expect(dots, findsNWidgets(3));
    expect(find.textContaining('ккал'), findsOneWidget);
  });

  testWidgets(
      'CustomNumpadSheet and SimpleGramsNumpadSheet _onAdd do not clamp 150000 to 99999',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CustomNumpadSheet(
            product: _potato,
            initialGrams: 150000,
            onConfirm: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+10 г'));
    await tester.pumpAndSettle();
    expect(find.text('150010'), findsOneWidget);
    expect(find.text('99999'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SimpleGramsNumpadSheet(
            title: 'Выход',
            initialGrams: 150000,
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+10 г'));
    await tester.pumpAndSettle();
    expect(find.text('150010'), findsOneWidget);
  });

  testWidgets('HomeScreen multi-select shows hidden count, Снять всё and PopScope',
      (tester) async {
    final dishes = [
      Dish(
        id: 'd1',
        title: 'Борщ',
        ingredients: const [Ingredient(id: 'i1', product: _potato, weightGrams: 100)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      Dish(
        id: 'd2',
        title: 'Каша',
        ingredients: const [Ingredient(id: 'i2', product: _potato, weightGrams: 150)],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    final draft = Dish(
      id: 'draft',
      title: 'Открытый черновик',
      ingredients: const [Ingredient(id: 'i3', product: _potato, weightGrams: 120)],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dishStorageRepositoryProvider.overrideWithValue(
            _FakeStorage(DishStorageData(activeDraft: draft, savedDishes: dishes)),
          ),
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

    // _ActiveDraftCard больше не использует тёмную InstrumentSlab.
    expect(find.byType(InstrumentSlab), findsNothing);
    expect(find.byType(GroupedSurface), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-select-mode-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 0'), findsOneWidget);

    await tester.tap(find.text('Борщ'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-library-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-library-search')), 'Каша');
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 1 · скрыто 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('selection-clear-all-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано 0'), findsOneWidget);

    // PopScope выходит из режима выбора вместо закрытия экрана.
    final dynamic navState = tester.state(find.byType(Navigator));
    await navState.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Поварская справка'), findsOneWidget);
  });

  testWidgets('RecipeEditorScreen syncs Hero kcal basis with collapsed AppBar chip',
      (tester) async {
    final draft = Dish(
      id: 'd-sync',
      title: 'Суп картофельный',
      customYieldGrams: 500,
      ingredients: const [
        Ingredient(id: 'i1', product: _potato, weightGrams: 100),
        Ingredient(id: 'i2', product: _potato, weightGrams: 150),
        Ingredient(id: 'i3', product: _potato, weightGrams: 120),
        Ingredient(id: 'i4', product: _potato, weightGrams: 130),
      ],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dishStorageRepositoryProvider.overrideWithValue(
            _FakeStorage(DishStorageData(activeDraft: draft)),
          ),
          productRepositoryProvider.overrideWithValue(_FakeProductRepo()),
          customProductsRepositoryProvider.overrideWithValue(_MemCustomRepo()),
          favoriteProductsRepositoryProvider.overrideWithValue(_MemFavRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RecipeEditorScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hero-mode-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('После готовки · на 100 г'), findsOneWidget);

    // Прокрутим вниз, чтобы в AppBar появился сжатый чип на 100 г.
    final listFinder = find.descendant(
      of: find.byType(ReorderableListView),
      matching: find.byType(Scrollable),
    );
    await tester.drag(listFinder.first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('appbar-collapsed-kcal')),
        matching: find.textContaining('/ 100 г'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('BatchExportSheet tracks busy state independently without changing other button label',
      (tester) async {
    final dish = Dish(
      id: 'd-exp',
      title: 'Тестовое блюдо',
      ingredients: const [Ingredient(id: 'i1', product: _potato, weightGrams: 100)],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: BatchExportSheet(dishes: [dish])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PDF — сводка и бланки'), findsOneWidget);
    expect(find.text('Excel (.xlsx) — лист на блюдо'), findsOneWidget);
  });
}
