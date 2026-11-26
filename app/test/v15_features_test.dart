import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/macro_balance.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/heat_process.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/core/theme/app_theme.dart';
import 'package:povarspravka/data/repositories/custom_products_repository.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/favorite_products_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/home_screen.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';
import 'package:povarspravka/presentation/widgets/menu_builder_sheet.dart';

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

class _MemStorage extends DishStorageRepository {
  Dish? activeDraft;
  List<Dish> savedDishes;

  _MemStorage({this.savedDishes = const []});

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
  @override
  Future<List<Product>> searchProducts({
    required String query,
    int? groupId,
    String? source,
    bool? isDish,
    int limit = 50,
  }) async =>
      const [_potato, _butter, _chicken];

  @override
  Future<List<FoodGroup>> getFoodGroups({bool? isDish}) async => const [];

  @override
  Future<Map<String, int>> getCountBySource({bool? isDish}) async =>
      const {'skurikhin': 2, 'bls': 1, 'supplement': 0};

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

  group('v1.5 Core features (#3 batch export, #4 menu, #6 macro balance)', () {
    test('MacroBalance computes clean 100% sum, zero-energy edge case and ratio',
        () {
      final zero = MacroBalance.fromMacros(protein: 0, fat: 0, carbs: 0);
      expect(zero.hasEnergy, isFalse);
      expect(zero.proteinPct, 0);
      expect(zero.fatPct, 0);
      expect(zero.carbsPct, 0);
      expect(zero.ratioLabel, isNull);

      // 10g P (40), 10g F (90), 40g C (160) -> total 290
      final b = MacroBalance.fromMacros(protein: 10, fat: 10, carbs: 40);
      expect(b.hasEnergy, isTrue);
      expect(b.proteinPct + b.fatPct + b.carbsPct, 100);
      expect(b.proteinPct, 14);
      expect(b.fatPct, 31);
      expect(b.carbsPct, 55);
      expect(b.ratioLabel, '1 : 1 : 4');
    });

    test('PdfBlankGenerator.generateBatch generates multi-dish PDF and rejects empty list',
        () async {
      await expectLater(
        PdfBlankGenerator.generateBatch(const []),
        throwsArgumentError,
      );

      final d1 = Dish.withProcess(
        id: 'pdf-1',
        title: 'Суп картофельный',
        process: HeatProcess.boil,
        customYieldGrams: 500,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 250),
        ],
      );
      final d2 = Dish.withProcess(
        id: 'pdf-2',
        title: 'Филе без выхода',
        process: HeatProcess.bake,
        ingredients: const [
          Ingredient(id: 'i2', product: _chicken, weightGrams: 200),
        ],
      );

      final bytes = await PdfBlankGenerator.generateBatch([d1, d2]);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('XlsxBlankGenerator.generateBatch creates Summary + unique sanitized dish sheets',
        () {
      expect(() => XlsxBlankGenerator.generateBatch(const []), throwsArgumentError);

      final longUnsafeTitle =
          '[Овощи/мясо:*?\\:] Очень длинное название блюда для листа Excel №1';
      final d1 = Dish.withProcess(
        id: 'xlsx-1',
        title: longUnsafeTitle,
        process: HeatProcess.boil,
        customYieldGrams: 300,
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 200),
        ],
      );
      final d2 = Dish.withProcess(
        id: 'xlsx-2',
        title: longUnsafeTitle,
        process: HeatProcess.cold,
        ingredients: const [
          Ingredient(id: 'i2', product: _butter, weightGrams: 25),
        ],
      );

      final bytes = XlsxBlankGenerator.generateBatch([d1, d2]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = {for (final f in archive) f.name: f};

      expect(files.containsKey('xl/workbook.xml'), isTrue);
      expect(files.containsKey('xl/worksheets/sheet1.xml'), isTrue);
      expect(files.containsKey('xl/worksheets/sheet2.xml'), isTrue);
      expect(files.containsKey('xl/worksheets/sheet3.xml'), isTrue);

      final workbookXml = utf8.decode(files['xl/workbook.xml']!.content as List<int>);
      expect(workbookXml, contains('name="Сводка"'));
      expect(workbookXml, contains('(2)'));

      final sheetNames = RegExp(r'name="([^"]+)"')
          .allMatches(workbookXml)
          .map((m) => m.group(1)!)
          .toList();
      expect(sheetNames.length, 3);
      expect(sheetNames.toSet().length, 3);
      for (final name in sheetNames) {
        expect(name.length, lessThanOrEqualTo(31));
        expect(RegExp(r'[\\/?*\[\]:]').hasMatch(name), isFalse);
      }

      final summaryXml =
          utf8.decode(files['xl/worksheets/sheet1.xml']!.content as List<int>);
      expect(summaryXml, contains('SUM(D3:D4)'));
      expect(summaryXml, contains('ИТОГО по сборнику'));
    });

    test('computeMenuSummary & formatMenuPlainText handle portions and no-yield dishes',
        () {
      final dYield = Dish.withProcess(
        id: 'm1',
        title: 'Курица с картофелем',
        process: HeatProcess.bake,
        customYieldGrams: 400,
        ingredients: const [
          Ingredient(id: 'i1', product: _chicken, weightGrams: 200),
          Ingredient(id: 'i2', product: _potato, weightGrams: 250),
        ],
      );
      final dNoYield = Dish.withProcess(
        id: 'm2',
        title: 'Масло порционное',
        process: HeatProcess.cold,
        ingredients: const [
          Ingredient(id: 'i3', product: _butter, weightGrams: 20),
        ],
      );

      final c1 = CalculationEngine.calculate(dYield);
      final c2 = CalculationEngine.calculate(dNoYield);

      final items = [
        MenuItemDraft(
          dish: dYield,
          calc: c1,
          portionGrams: 200,
          usesWholeDish: false,
        ),
        MenuItemDraft(
          dish: dNoYield,
          calc: c2,
          portionGrams: 0,
          usesWholeDish: true,
        ),
      ];

      final summary = computeMenuSummary(items);
      expect(summary.totalGrams, 200);
      expect(summary.hasWholeDishWithoutYield, isTrue);
      expect(summary.balance.hasEnergy, isTrue);
      expect(
        summary.balance.proteinPct +
            summary.balance.fatPct +
            summary.balance.carbsPct,
        100,
      );

      final txt = formatMenuPlainText(items, summary);
      expect(txt, contains('Набор блюд (2):'));
      expect(txt, contains('Курица с картофелем (200 г)'));
      expect(txt, contains('Масло порционное (всё блюдо)'));
      expect(txt, contains('Баланс КБЖУ:'));
    });
  });

  group('v1.5 Widget flows (320x568 @2x safe)', () {
    testWidgets(
        'MacroSummaryBar inspector renders MacroBalanceBar cleanly at 320x568 @2x',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dish = Dish.withProcess(
        id: 'd-bal',
        title: 'Курица со сливочным маслом',
        process: HeatProcess.bake,
        customYieldGrams: 220,
        ingredients: const [
          Ingredient(id: 'i1', product: _chicken, weightGrams: 200),
          Ingredient(id: 'i2', product: _butter, weightGrams: 30),
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

      final contribAcc = find.byKey(const ValueKey('inspector-acc-contrib'));
      await tester.scrollUntilVisible(
        contribAcc,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(contribAcc);
      await tester.pumpAndSettle();

      final bal = find.byKey(const ValueKey('inspector-macro-balance'));
      await tester.scrollUntilVisible(
        bal,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(bal, findsOneWidget);
      expect(find.textContaining('Соотношение Б : Ж : У ='), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'HomeScreen selection mode opens DishComparisonSheet, MenuBuilderSheet and BatchExportSheet cleanly',
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
        }
        return null;
      });

      final dish1 = Dish.withProcess(
        id: 'd1',
        title: 'Пюре с маслом',
        category: DishCategories.side,
        process: HeatProcess.boil,
        customYieldGrams: 300,
        updatedAt: DateTime(2026, 11, 20),
        ingredients: const [
          Ingredient(id: 'i1', product: _potato, weightGrams: 250),
          Ingredient(id: 'i2', product: _butter, weightGrams: 20),
        ],
      );
      final dish2 = Dish.withProcess(
        id: 'd2',
        title: 'Куриная грудка запечённая',
        category: DishCategories.main,
        process: HeatProcess.bake,
        customYieldGrams: 180,
        updatedAt: DateTime(2026, 11, 19),
        ingredients: const [
          Ingredient(id: 'i3', product: _chicken, weightGrams: 220),
        ],
      );
      final storage = _MemStorage(savedDishes: [dish1, dish2]);

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

      // Enter selection mode via long-press on first dish, then tap second dish.
      await tester.longPress(find.text('Пюре с маслом'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано 1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Куриная грудка запечённая'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Куриная грудка запечённая'));
      await tester.pumpAndSettle();
      expect(find.text('Выбрано 2'), findsOneWidget);

      // 1) Open DishComparisonSheet (#5) and switch between На 100 г / На всё блюдо.
      await tester.tap(find.byKey(const ValueKey('selection-compare-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Сравнение блюд'), findsOneWidget);
      await tester.tap(find.text('На всё блюдо'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('Сравнение блюд'))).pop();
      await tester.pumpAndSettle();

      // 2) Open MenuBuilderSheet (#4), increment portion, copy text.
      await tester.tap(find.byKey(const ValueKey('selection-menu-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-builder-sheet')), findsOneWidget);

      final incD2 = find.byKey(const ValueKey('menu-inc-d2'));
      await tester.scrollUntilVisible(
        incD2,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(incD2);
      await tester.pumpAndSettle();

      final copyMenuBtn = find.byKey(const ValueKey('menu-copy-text-btn'));
      await tester.scrollUntilVisible(
        copyMenuBtn,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(copyMenuBtn);
      await tester.pumpAndSettle();

      expect(copied, contains('Набор блюд (2):'));
      expect(copied, contains('Баланс КБЖУ:'));
      expect(find.text('Сводка меню скопирована'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('menu-builder-sheet'))),
      ).pop();
      await tester.pumpAndSettle();

      // 3) Open BatchExportSheet (#3) and verify PDF + Excel buttons exist.
      await tester.tap(find.byKey(const ValueKey('selection-export-btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-export-pdf-btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-export-xlsx-btn')), findsOneWidget);
      Navigator.of(tester.element(find.text('Пакетный экспорт'))).pop();
      await tester.pumpAndSettle();

      // Exit selection mode cleanly.
      await tester.tap(find.byKey(const ValueKey('selection-close-btn')));
      await tester.pumpAndSettle();
      expect(find.text('Поварская справка'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
