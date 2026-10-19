import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/calculation/calculation_validation.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/screens/blank_preview_screen.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';

const sample = Product(
    id: 1,
    code: 'qa',
    name: 'Картофель проверочный',
    groupId: 1,
    source: 'skurikhin',
    protein: 2,
    fat: 0.4,
    carbs: 17,
    kcal: 80);

class FixtureRepo extends ProductRepository {
  final List<Product> products;
  FixtureRepo({this.products = const [sample]});
  @override
  Future<List<Product>> searchProducts(
          {String query = '',
          int? groupId,
          String? source,
          int limit = 60}) async =>
      products;
  @override
  Future<List<FoodGroup>> getFoodGroups() async =>
      [const FoodGroup(id: 1, code: 'qa', name: 'Овощи и картофель')];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async =>
      [];
}

Future<DishNotifier> mount(WidgetTester t, Widget home, double scale, Size size,
    {FixtureRepo? repo}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final font = FontLoader('Arial')
    ..addFont(rootBundle.load('assets/fonts/arial.ttf'));
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final n = DishNotifier();
  for (var i = 0; i < 10; i++) {
    n.addIngredient(sample, 100.25 + i);
  }
  n.setCustomYield(777.77);
  await t.pumpWidget(ProviderScope(
      overrides: [
        dishProvider.overrideWith((ref) => n),
        productRepositoryProvider.overrideWithValue(repo ?? FixtureRepo())
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: home)));
  await t.pumpAndSettle();
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scale in [1.5, 2.0]) {
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      final screens = <String, Widget>{
        'Home': const HomeScreen(),
        'Editor': const RecipeEditorScreen(),
        'Search': const Scaffold(
            body: SearchProductModal(mode: SearchMode.browseCatalog)),
        'Preview': const BlankPreviewScreen()
      };
      for (final e in screens.entries) {
        testWidgets('360 layout ${e.key} scale=$scale size=$size', (t) async {
          await mount(t, e.value, scale, size);
          expect(t.takeException(), isNull);
        });
      }
    }
  }

  for (final id in [167611, 167702]) {
    final rows =
        jsonDecode(File('../audit/final360_catalog.json').readAsStringSync())
            as List;
    final bad = Product.fromMap(
        Map<String, dynamic>.from(rows.firstWhere((r) => r['id'] == id)));
    testWidgets('360 quarantine $id search selection warns without mutation',
        (t) async {
      final n = await mount(t, const Scaffold(body: SearchProductModal()), 1,
          const Size(390, 844),
          repo: FixtureRepo(products: [bad]));
      final before = jsonEncode(n.state.toJson());
      await t.tap(find.byType(ListTile).first);
      await t.pumpAndSettle();
      expect(find.textContaining('недоступен для расчёта'), findsOneWidget);
      expect(find.byType(CustomNumpadSheet), findsNothing);
      expect(jsonEncode(n.state.toJson()), before);
      expect(t.takeException(), isNull);
    });
    testWidgets('360 quarantine $id info card disables adding and warns',
        (t) async {
      var called = false;
      await mount(
          t,
          Scaffold(
              body: ProductInfoCardSheet(
                  product: bad,
                  onAddToRecipe: () {
                    called = true;
                  })),
          1,
          const Size(390, 844));
      final button = find
          .byWidgetPredicate((w) => w is ElevatedButton && w.onPressed == null);
      expect(button, findsOneWidget);
      expect(t.widget<ElevatedButton>(button).onPressed, isNull);
      expect(find.textContaining('Продукт доступен только для справки'),
          findsOneWidget);
      expect(called, false);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('360 preview text is not ellipsized at 2x', (t) async {
    await mount(t, const BlankPreviewScreen(), 2, const Size(320, 640));
    final clipped = <String>[];
    for (final e in find.byType(RichText).evaluate()) {
      final obj = e.renderObject;
      if (obj is RenderParagraph &&
          (obj.didExceedMaxLines ||
              (obj.hasSize &&
                  obj.computeMaxIntrinsicHeight(obj.size.width) >
                      obj.size.height + 0.5))) {
        clipped.add(obj.text.toPlainText());
      }
    }
    File('../audit/final360_text_clipping.json').writeAsStringSync(jsonEncode({
      'screen': 'BlankPreviewScreen',
      'scale': 2,
      'size': '320x640',
      'ellipsized_texts': clipped,
      'note': 'Regression asserts no ellipsis.'
    }));
    expect(clipped, isEmpty, reason: 'Preview must not truncate content at 2x');
    expect(t.takeException(), isNull);
  });
  testWidgets('360 preview wraps long catalog name at 2x', (t) async {
    final n =
        await mount(t, const BlankPreviewScreen(), 2, const Size(320, 640));
    final rows =
        jsonDecode(File('../audit/final360_catalog.json').readAsStringSync())
            as List;
    rows.sort((a, b) =>
        (b['name'] as String).length.compareTo((a['name'] as String).length));
    n.addIngredient(
        Product.fromMap(Map<String, dynamic>.from(rows.first)), 123);
    await t.pumpAndSettle();
    final clipped = <String>[];
    for (final e in find.byType(RichText).evaluate()) {
      final obj = e.renderObject;
      if (obj is RenderParagraph &&
          (obj.didExceedMaxLines ||
              (obj.hasSize &&
                  obj.computeMaxIntrinsicHeight(obj.size.width) >
                      obj.size.height + 0.5))) {
        clipped.add(obj.text.toPlainText());
      }
    }
    File('../audit/final360_long_name_clipping.json')
        .writeAsStringSync(jsonEncode({
      'screen': 'BlankPreviewScreen',
      'scale': 2,
      'size': '320x640',
      'ellipsized_texts': clipped,
      'note': 'Regression asserts no ellipsis.'
    }));
    expect(clipped, isEmpty, reason: 'Preview must not truncate content at 2x');
    expect(t.takeException(), isNull);
  });
  testWidgets('360 rotation preserves recipe and yield in provider', (t) async {
    final n =
        await mount(t, const RecipeEditorScreen(), 1, const Size(390, 844));
    final before = jsonEncode(n.state.toJson());
    t.view.physicalSize = const Size(844, 390);
    await t.pumpAndSettle();
    expect(jsonEncode(n.state.toJson()), before);
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    expect(jsonEncode(n.state.toJson()), before);
    expect(t.takeException(), isNull);
  });
  for (final kind in ['search', 'info', 'numpad']) {
    testWidgets('360 Android framework back closes $kind only', (t) async {
      final n = await mount(
          t,
          Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () {
                        showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => kind == 'search'
                                ? const SearchProductModal(
                                    mode: SearchMode.browseCatalog)
                                : kind == 'info'
                                    ? ProductInfoCardSheet(
                                        product: sample, onAddToRecipe: () {})
                                    : CustomNumpadSheet(
                                        product: sample,
                                        initialGrams: 100,
                                        onConfirm: (_, __) {}));
                      },
                      child: const Text('open')))),
          1,
          const Size(390, 844));
      final before = jsonEncode(n.state.toJson());
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(jsonEncode(n.state.toJson()), before);
      expect(t.takeException(), isNull);
    });
  }
  test(
      '360 fresh repository and notifier restore ten ingredients exactly after completed autosave',
      () async {
    final dir = await Directory.systemTemp.createTemp('povar_360_restore_');
    try {
      final n =
          DishNotifier(storage: DishStorageRepository(storageDirectory: dir));
      await n.flushPendingSaves();
      n.setTitle('QA 10 ингредиентов');
      for (var i = 0; i < 10; i++) {
        n.addIngredient(sample, 100.25 + i);
      }
      n.setCustomYield(777.77);
      await n.flushPendingSaves();
      final snapshot = jsonEncode(n.state.toJson());
      n.dispose();
      final fresh =
          DishNotifier(storage: DishStorageRepository(storageDirectory: dir));
      await fresh.flushPendingSaves();
      expect(jsonEncode(fresh.state.toJson()), snapshot);
      fresh.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
      '360 all catalog rows use production validation and quarantine rejects programmatic add',
      () {
    final rows =
        jsonDecode(File('../audit/final360_catalog.json').readAsStringSync())
            as List;
    final rejected = <String>[];
    for (final row in rows) {
      final p = Product.fromMap(Map<String, dynamic>.from(row as Map));
      try {
        CalculationValidation.product(p);
      } on ArgumentError {
        rejected.add(p.id.toString());
      }
    }
    expect(rejected.toSet(), {'167611', '167702'});
    final n = DishNotifier();
    for (final row in rows
        .where((r) => ['167611', '167702'].contains(r['id'].toString()))) {
      expect(
          () => n.addIngredient(
              Product.fromMap(Map<String, dynamic>.from(row)), 100),
          throwsArgumentError);
    }
    expect(n.state.ingredients, isEmpty);
    n.dispose();
  });
  test('360 generate fresh PDF DOCX XLSX ten ingredients', () async {
    final n = DishNotifier();
    for (var i = 0; i < 10; i++) {
      n.addIngredient(sample, 100.25 + i);
    }
    n.setCustomYield(777.77);
    final out = Directory('../audit/final360_exports')
      ..createSync(recursive: true);
    File('${out.path}/photoCross.pdf')
        .writeAsBytesSync(await PdfBlankGenerator.generate(n.state));
    File('${out.path}/photoCross.docx')
        .writeAsBytesSync(DocxBlankGenerator.generate(n.state));
    File('${out.path}/photoCross.xlsx')
        .writeAsBytesSync(XlsxBlankGenerator.generate(n.state));
    n.dispose();
  });
}
