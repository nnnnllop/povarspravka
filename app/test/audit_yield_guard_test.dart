// Regression: an impossible yield must never reach the engine through the UI.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';

const beef = Product(
    id: 1,
    code: '3.1.3',
    name: 'Говядина 1 категории',
    groupId: 3,
    source: 'skurikhin',
    protein: 18.6,
    fat: 16,
    carbs: 0,
    kcal: 218,
    wastePct: 25);

class FixtureRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts(
          {String query = '',
          int? groupId,
          String? source,
          int limit = 60}) async =>
      const [beef];
  @override
  Future<List<FoodGroup>> getFoodGroups() async => const [];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('engine rejects yield below cooked macro mass', () {
    final notifier = DishNotifier();
    notifier.addIngredient(beef, 600);
    notifier.setCustomYield(10);
    expect(() => CalculationEngine.calculate(notifier.state),
        throwsA(isA<ArgumentError>()));
  });

  testWidgets('editor keeps a valid yield and explains the limit',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Arial')
      ..addFont(rootBundle.load('assets/fonts/arial.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final notifier = DishNotifier();
    notifier.addIngredient(beef, 600);
    notifier.setCustomYield(750);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        dishProvider.overrideWith((ref) => notifier),
        productRepositoryProvider.overrideWithValue(FixtureRepo()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const RecipeEditorScreen()),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('actual-yield'));
    expect(field, findsOneWidget);
    await tester.enterText(field, '10');
    await tester.pumpAndSettle();

    // The invalid value must be refused, not stored, and the screen must live.
    expect(tester.takeException(), isNull);
    expect(notifier.state.customYieldGrams, 750);
    expect(find.textContaining('выход'), findsWidgets);
  });
}
