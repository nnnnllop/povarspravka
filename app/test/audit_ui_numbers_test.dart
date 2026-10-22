// Dumps every visible number in the editor, inspector and preview for A4.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';

const _root = r'C:\temp_audit';

class FixtureRepo extends ProductRepository {
  @override
  Future<List<Product>> searchProducts(
          {String query = '',
          int? groupId,
          String? source,
          int limit = 60}) async =>
      const [];
  @override
  Future<List<FoodGroup>> getFoodGroups() async => const [];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async =>
      const [];
}

Dish buildA4() {
  final data = jsonDecode(File('$_root\\recipes.json').readAsStringSync())
      as Map<String, dynamic>;
  final products = data['products'] as Map<String, dynamic>;
  final recipe = (data['recipes'] as Map<String, dynamic>)['A4']
      as Map<String, dynamic>;
  final ings = <Ingredient>[];
  var i = 0;
  for (final item in (recipe['items'] as List<dynamic>).cast<List<dynamic>>()) {
    ings.add(Ingredient(
        id: 'ing-$i',
        product:
            Product.fromJson((products[item[0]] as Map).cast<String, dynamic>()),
        weightGrams: (item[1] as num).toDouble(),
        isGross: item[2] as bool));
    i++;
  }
  return Dish(
    id: 'a4',
    title: 'A4',
    ingredients: ings,
    customYieldGrams: 750,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

List<String> texts(WidgetTester tester) {
  final out = <String>[];
  for (final w in tester.allWidgets) {
    if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
      out.add(w.data!);
    }
  }
  return out;
}

bool get _fixtureAvailable => File(_root + '/recipes.json').existsSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dump editor and inspector numbers', (tester) async {
    if (!_fixtureAvailable) return;
    tester.view.physicalSize = const Size(1000, 3000);
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
    notifier.loadDish(buildA4());
    final container = ProviderContainer(overrides: [
      dishProvider.overrideWith((ref) => notifier),
      productRepositoryProvider.overrideWithValue(FixtureRepo()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light, home: const RecipeEditorScreen()),
    ));
    await tester.pumpAndSettle();

    final editorTexts = texts(tester);

    // Open the calculation inspector from the summary card.
    await tester.tap(find.text('Инспектор расчёта').first);
    await tester.pumpAndSettle();
    final inspectorTexts = texts(tester);

    File('$_root\\ui_editor.txt')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'editor': editorTexts,
      'inspector': inspectorTexts,
    }));
  });

  testWidgets('dump preview numbers', (tester) async {
    if (!_fixtureAvailable) return;
    tester.view.physicalSize = const Size(1400, 3000);
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
    notifier.loadDish(buildA4());
    final container = ProviderContainer(overrides: [
      dishProvider.overrideWith((ref) => notifier),
      productRepositoryProvider.overrideWithValue(FixtureRepo()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light, home: const BlankPreviewScreen()),
    ));
    await tester.pumpAndSettle();
    File('$_root\\ui_preview.txt')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(texts(tester)));
  });
}
