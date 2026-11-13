// STATE-01 / LEAD-02 — SPECIFICATION (inverted from the defect probe).
//
// Formerly this file PROVED that `calculationResultProvider` threw
// `ArgumentError` straight out of `build()`, replacing the screen with a
// framework `ErrorWidget` (a red screen with a raw stack trace).
//
// The specification is the opposite: a dish whose data cannot be calculated
// must NOT take the UI down. The provider yields `null`, the screens render a
// `CalcErrorBanner`, the rest of the app keeps working, and a global
// `ErrorWidget.builder` guarantees no red screen can ever reach the user.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/calc_error_banner.dart';

const fatProduct = Product(
    id: 9001,
    code: 'f',
    name: 'Масло сливочное',
    groupId: 1,
    source: 'skurikhin',
    protein: 0,
    fat: 99.9,
    carbs: 0,
    kcal: 899);

const beet = Product(
    id: 9002,
    code: 'b',
    name: 'Свекла',
    groupId: 1,
    source: 'skurikhin',
    protein: 1.5,
    fat: .1,
    carbs: 8.8,
    kcal: 42);

/// A dish that is structurally VALID (the widget tree can hold it) but whose
/// calculation fails. Every ingredient and product is legal; the failure comes
/// from the dish-level yield, which the engine rejects (MATH-05: a sub-1 g
/// output is not a coefficient, it is a decimal-point typo).
Dish uncalculableDish() => Dish(
      id: 'uncalculable',
      title: 'Невычислимое блюдо',
      ingredients: const [
        Ingredient(id: 'i-1', product: fatProduct, weightGrams: 600),
      ],
      customYieldGrams: 0.1,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Dish healthyDish() => Dish(
      id: 'healthy',
      title: 'Свекла отварная',
      ingredients: const [
        Ingredient(id: 'i-1', product: beet, weightGrams: 200),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class NoopStorage extends DishStorageRepository {
  @override
  Future<DishStorageData> loadAll() async => const DishStorageData();
  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {}
}

class StaticRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts(
          {required String query,
          int? groupId,
          String? source,
          bool? isDish,
          int limit = 50}) async =>
      const [beet];
  @override
  Future<Map<String, int>> getCountBySource({bool? isDish}) async => const {};
  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int id) async =>
      const [];
}

void Function() disposeOnce(StateNotifier<dynamic> notifier) {
  var done = false;
  return () {
    if (done) return;
    done = true;
    try {
      notifier.dispose();
    } catch (_) {
      // Already disposed by the ProviderScope.
    }
  };
}

class UncalculableDishNotifier extends DishNotifier {
  UncalculableDishNotifier()
      : super(storage: NoopStorage(), savedDishesNotifier: null) {
    state = uncalculableDish();
    markClean();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STATE-01 the engine still rejects genuinely invalid data', () {
    test('a sub-1 g yield stays an error at the engine boundary', () {
      expect(() => CalculationEngine.calculate(uncalculableDish()),
          throwsA(isA<ArgumentError>()));
      expect(CalculationEngine.tryCalculate(uncalculableDish()), isNull);
    });

    test('control: a healthy dish calculates fine', () {
      final r = CalculationEngine.calculate(healthyDish());
      expect(r.yieldGrams, 200);
    });

    test('LOGIC-01: a butter-heavy dish with a small yield is CALCULABLE', () {
      final dense = Dish(
        id: 'dense',
        title: 'Жировой соус',
        ingredients: const [
          Ingredient(id: 'i-1', product: fatProduct, weightGrams: 100),
        ],
        customYieldGrams: 60,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(() => CalculationEngine.calculate(dense), returnsNormally);
      final r = CalculationEngine.calculate(dense);
      expect(r.yieldGrams, 60);
      expect(r.per100gKcal, greaterThan(0));
    });
  });

  group('STATE-01 provider yields null instead of throwing', () {
    test('source declares a nullable provider and an error provider', () {
      final src =
          File('lib/presentation/providers/dish_provider.dart').readAsStringSync();
      expect(src, contains('final calculationResultProvider = Provider<CalculationResult?>(('));
      expect(src, contains('final calculationErrorProvider = Provider<String?>('));
    });

    test('main() installs a friendly ErrorWidget.builder (no red screen)', () {
      final mainSrc = File('lib/main.dart').readAsStringSync();
      expect(mainSrc, contains('ErrorWidget.builder'));
      expect(mainSrc, contains('FriendlyErrorPane'));
    });

    test('reading the provider for a bad dish returns null, not a throw', () {
      final container = ProviderContainer(overrides: [
        dishStorageRepositoryProvider.overrideWithValue(NoopStorage()),
      ]);
      addTearDown(container.dispose);
      container.read(dishProvider.notifier).loadDish(uncalculableDish());
      expect(container.read(calculationResultProvider), isNull);
      expect(container.read(calculationErrorProvider), isNotNull);
    });

    test('reading the provider for a good dish returns a result', () {
      final container = ProviderContainer(overrides: [
        dishStorageRepositoryProvider.overrideWithValue(NoopStorage()),
      ]);
      addTearDown(container.dispose);
      container.read(dishProvider.notifier).loadDish(healthyDish());
      expect(container.read(calculationResultProvider), isNotNull);
      expect(container.read(calculationErrorProvider), isNull);
    });
  });

  group('STATE-01 / LEAD-02 screens degrade gracefully', () {
    testWidgets('RecipeEditorScreen shows CalcErrorBanner, not ErrorWidget',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = UncalculableDishNotifier();
      addTearDown(disposeOnce(notifier));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          productRepositoryProvider.overrideWithValue(StaticRepo()),
        ],
        child:
            MaterialApp(theme: AppTheme.light, home: const RecipeEditorScreen()),
      ));
      await tester.pump();

      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'a bad dish must never produce a red screen');
      expect(find.byType(CalcErrorBanner), findsOneWidget);
      expect(find.text('Проверьте выход и параметры блюда'), findsOneWidget);
      // The editor is still usable: the ingredient count header is rendered.
      expect(find.textContaining('Ингредиенты · 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomeScreen does not crash on the same dish', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = UncalculableDishNotifier();
      addTearDown(disposeOnce(notifier));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          savedDishesProvider
              .overrideWith((ref) => SavedDishesNotifier(NoopStorage())),
          productRepositoryProvider.overrideWithValue(StaticRepo()),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ));
      await tester.pump();

      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recovering the dish removes the banner', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = UncalculableDishNotifier();
      addTearDown(disposeOnce(notifier));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          dishProvider.overrideWith((ref) => notifier),
          productRepositoryProvider.overrideWithValue(StaticRepo()),
        ],
        child:
            MaterialApp(theme: AppTheme.light, home: const RecipeEditorScreen()),
      ));
      await tester.pump();
      expect(find.byType(CalcErrorBanner), findsOneWidget);

      notifier.loadDish(healthyDish());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CalcErrorBanner), findsNothing);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'entering a sub-1 g manual yield never throws out of the editor',
        (tester) async {
      final notifier = DishNotifier();
      addTearDown(notifier.dispose);
      notifier.addIngredient(fatProduct, 600);
      expect(() => CalculationEngine.calculate(notifier.state), returnsNormally);
      // MATH-05: the notifier rejects the value instead of storing it.
      notifier.setCustomYield(0.1);
      expect(notifier.state.customYieldGrams, isNull);
      expect(() => CalculationEngine.calculate(notifier.state), returnsNormally);
    });

    testWidgets('FriendlyErrorPane is what the global builder returns',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Material(child: FriendlyErrorPane()),
      ));
      expect(find.text('Не удалось показать этот экран'), findsOneWidget);
    });

    test('BlankPreviewScreen degrades through the same banner', () {
      final src = File('lib/presentation/screens/blank_preview_screen.dart')
          .readAsStringSync();
      expect(src, contains('ref.watch(calculationResultProvider)'));
      expect(src, contains('CalcErrorBanner'));
    });
  });
}
