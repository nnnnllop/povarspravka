import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/calculation_math.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/recipe_editor_screen.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'package:povarspravka/presentation/widgets/macro_summary_bar.dart';
import 'culinary_logic_test.dart' show beet, fixture;

String part(List<int> bytes, String name) => utf8.decode(
    ZipDecoder().decodeBytes(bytes).findFile(name)!.content as List<int>);

class FakeProducts extends ProductRepository {
  final requests = <String, Completer<List<Product>>>{};
  @override
  Future<List<Product>> searchProducts(
          {required String query,
          int? groupId,
          String? source,
          int limit = 50}) =>
      requests.putIfAbsent(query, () => Completer<List<Product>>()).future;
}

class FailingStorage extends DishStorageRepository {
  @override
  Future<DishStorageData> loadAll() async => const DishStorageData();
  @override
  Future<void> saveAll(
      {required Dish? activeDraft, required List<Dish> savedDishes}) async {
    throw const FileSystemException('Simulated disk failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Gross/net boundaries and inverse: no division by zero at 100%', () {
    for (final waste in [0.0, 50.0, 100.0]) {
      final ing = Ingredient(
          id: 'x',
          product: beet.copyWith(wastePct: waste),
          weightGrams: 100,
          isGross: true);
      expect(ing.netGrams, 100 - waste);
      expect(Ingredient.netFromGross(100, waste), ing.netGrams);
      expect(
          ing.proteinInDish, CalculationMath.round2(1.5 * (1 - waste / 100)));
    }
    expect(Ingredient.grossFromNet(50, 50), 100);
    expect(Ingredient.grossFromNet(50, 0), 50);
    expect(Ingredient.grossFromNet(50, 100), isNull);
    expect(Ingredient.grossFromNet(0, 100), 0);
  });
  for (final value in [double.nan, double.infinity, -1.0, 101.0]) {
    test('Invalid product nutrients fail explicitly: $value', () {
      final d = fixture(100).copyWith(ingredients: [
        Ingredient(
            id: 'bad', weightGrams: 100, product: beet.copyWith(protein: value))
      ]);
      expect(() => CalculationEngine.calculate(d), throwsArgumentError);
    });
  }
  test('Invalid retention, waste and extreme masses fail without NaN results',
      () {
    for (final value in [double.nan, double.infinity, -1.0, 1.01]) {
      expect(
          () => CalculationEngine.calculate(
              fixture(100).copyWith(retentionProtein: value)),
          throwsArgumentError);
    }
    for (final value in [-1.0, double.infinity, 1e300]) {
      expect(() => CalculationEngine.calculate(fixture(value)),
          throwsArgumentError);
    }
    for (final value in [-1.0, 101.0, double.nan]) {
      expect(() => Ingredient.netFromGross(100, value), throwsArgumentError);
    }
    expect(() => CalculationMath.round1(double.nan), throwsArgumentError);
  });
  test('Exact quotient HALF-UP, including binary division trap', () {
    expect(CalculationMath.ratioRounded(1.15, 200, 2), .58);
    expect(CalculationMath.ratioRounded(1.41, 200, 2), .71);
    expect(CalculationMath.ratioRounded(38.5, 200, 1), 19.3);
    expect(() => CalculationMath.ratioRounded(1, 0, 2), throwsArgumentError);
    for (var cents = 0; cents < 2000; cents++) {
      expect(CalculationMath.ratioRounded(cents / 100, 100, 2), cents / 100);
    }
  });
  test('Display rounding matches HALF-UP in every text export', () {
    expect(CalculationEngine.formatMacro(1.005), '1,01');
    expect(CalculationEngine.formatKcal(1.15), '1,2');
    expect(CalculationEngine.formatPercent(.9456), '94,56');
    expect(CalculationEngine.formatPercent(1), '100');
    expect(CalculationEngine.formatPercent(0), '0');
  });
  test('Provider rejects invalid inputs without changing prior valid state',
      () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    n.addIngredient(beet, 100);
    final id = n.state.ingredients.single.id;
    for (final value in [double.nan, double.infinity, -1.0, .0001, 1e300]) {
      n.updateIngredient(id, value);
      n.addIngredient(beet, value);
      expect(n.state.ingredients.length, 1);
      expect(n.state.ingredients.single.weightGrams, 100);
    }
    for (final value in [double.nan, double.infinity, -1.0, 1.01]) {
      n.setRetention(protein: value, fat: 0);
      expect(n.state.retentionProtein, .94);
      expect(n.state.retentionFat, .88);
    }
    n.setRetention(protein: 0, fat: 1, carbs: 1);
    expect(CalculationEngine.calculate(n.state).cookedProtein, 0);
    await n.flushPendingSaves();
  });
  test('Custom yield boundaries 0, micro, 999999 and junk', () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    n.addIngredient(beet, 100);
    n.setCustomYield(200);
    for (final text in ['0', '0.0001', 'abc', 'NaN', '1e300']) {
      final v = CalculationEngine.parseInputDouble(text);
      if (v != null) n.setCustomYield(v);
      expect(n.state.customYieldGrams, 200);
    }
    n.setCustomYield(999999);
    final r = CalculationEngine.calculate(n.state);
    expect(r.yieldGrams, 999999);
    expect(r.per100gKcal.isFinite, isTrue);
    await n.flushPendingSaves();
  });
  test('Dish total is sum of visible rows; mode changes presentation only', () {
    final d = fixture(100).copyWith(
        ingredients: List.generate(
            150,
            (i) =>
                Ingredient(id: '$i', product: beet, weightGrams: .3 + i / 10)));
    final a = CalculationEngine.calculate(d);
    final b =
        CalculationEngine.calculate(d.copyWith(blankMode: BlankMode.detailed));
    final cents = d.ingredients
        .fold<int>(0, (sum, ing) => sum + (ing.proteinInDish * 100).round());
    expect(a.rawTotalProtein, cents / 100);
    expect(a.cookedKcal, b.cookedKcal);
    expect(a.rawTotalKcal, isNull);
    expect(b.rawTotalKcal, isNotNull);
  });
  test('Portions use whole-dish values, not rounded per100', () {
    final r = CalculationEngine.calculate(fixture(100, yieldGrams: 200));
    final p = r.portion(200);
    expect(p.protein, r.cookedProtein);
    expect(p.kcal, r.cookedKcal);
    expect(p.protein, isNot(r.per100gProtein * 2));
    expect(() => r.portion(0), throwsArgumentError);
    expect(() => CalculationEngine.calculate(fixture(0)).portion(200),
        throwsStateError);
  });
  test('Library is an independent persisted snapshot; explicit save updates it',
      () async {
    final dir = await Directory.systemTemp.createTemp('system_logic_');
    final storage = DishStorageRepository(storageDirectory: dir);
    final saved = SavedDishesNotifier(storage);
    final n = DishNotifier(storage: storage, savedDishesNotifier: saved);
    try {
      n.addIngredient(beet, 100);
      n.setTitle('Original');
      await n.saveCurrentToLibrary();
      final originalId = n.state.id;
      n.setTitle('Draft only');
      n.updateIngredient(n.state.ingredients.single.id, 200);
      await n.flushPendingSaves();
      expect(saved.state.single.title, 'Original');
      expect(saved.state.single.ingredients.single.weightGrams, 100);
      final data = await storage.loadAll();
      expect(data.activeDraft!.title, 'Draft only');
      expect(data.savedDishes.single.title, 'Original');
      await n.saveCurrentToLibrary();
      expect(saved.state.single.id, originalId);
      expect(saved.state.single.title, 'Draft only');
      n.createNewDish();
      await n.flushPendingSaves();
      n.loadDish(saved.state.single);
      n.setTitle('Unsaved change');
      await n.flushPendingSaves();
      expect(saved.state.single.title, 'Draft only');
    } finally {
      n.dispose();
      saved.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
      'duplicateDish regenerates dish and ingredient IDs and deep-copies lists',
      () async {
    final storage = DishStorageRepository();
    final n = SavedDishesNotifier(storage);
    addTearDown(n.dispose);
    final d = fixture(100);
    final a = await n.duplicateDish(d);
    final b = await n.duplicateDish(d);
    expect({d.id, a.id, b.id}.length, 3);
    expect(
        {
          d.ingredients.single.id,
          a.ingredients.single.id,
          b.ingredients.single.id
        }.length,
        3);
    expect(identical(a.ingredients, d.ingredients), isFalse);
    expect(
        identical(a.ingredients.single.product, d.ingredients.single.product),
        isFalse);
    await storage.loadAll(); // waits for all repository writes
  });
  test('Rapid two-field changes survive restart without altering saved recipe',
      () async {
    final dir = await Directory.systemTemp.createTemp('system_logic_');
    final storage = DishStorageRepository(storageDirectory: dir);
    final saved = SavedDishesNotifier(storage);
    final n = DishNotifier(storage: storage, savedDishesNotifier: saved);
    try {
      n.addIngredient(beet, 100);
      await n.saveCurrentToLibrary();
      for (var i = 1; i <= 30; i++) {
        n.setTitle('Title $i');
        n.updateIngredient(n.state.ingredients.single.id, 100.0 + i);
      }
      await n.flushPendingSaves();
      final restarted =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(restarted.activeDraft!.title, 'Title 30');
      expect(restarted.activeDraft!.ingredients.single.weightGrams, 130);
      expect(restarted.savedDishes.single.ingredients.single.weightGrams, 100);
    } finally {
      n.dispose();
      saved.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('Explicit save failure is observable, not a premature success',
      () async {
    final storage = FailingStorage();
    final saved = SavedDishesNotifier(storage);
    final n = DishNotifier(storage: storage, savedDishesNotifier: saved);
    addTearDown(n.dispose);
    addTearDown(saved.dispose);
    n.addIngredient(beet, 100);
    await expectLater(
        n.saveCurrentToLibrary(), throwsA(isA<FileSystemException>()));
    expect(n.lastPersistenceError, isNotNull);
  });
  test('Corrupt numeric main file is recovered from validated backup',
      () async {
    final dir = await Directory.systemTemp.createTemp('system_logic_');
    try {
      final s = DishStorageRepository(storageDirectory: dir);
      await s.saveAll(activeDraft: fixture(100), savedDishes: []);
      await s.saveAll(activeDraft: fixture(200), savedDishes: []);
      final raw = fixture(200).toJson();
      raw['retentionProtein'] = -1;
      await File('${dir.path}/povarspravka_user_dishes.json')
          .writeAsString(jsonEncode({'activeDraft': raw, 'savedDishes': []}));
      expect(
          (await s.loadAll()).activeDraft!.ingredients.single.weightGrams, 100);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
      'Undo restores exact position, weight and gross flag; exports preserve reorder',
      () async {
    final n = DishNotifier();
    addTearDown(n.dispose);
    for (var i = 0; i < 3; i++)
      n.addIngredient(beet.copyWith(name: 'P$i'), 100.0 + i, isGross: i == 1);
    final removed = n.state.ingredients[1];
    n.removeIngredient(removed.id);
    n.restoreIngredient(removed, 1);
    expect(n.state.ingredients[1], same(removed));
    n.reorderIngredients(0, 3);
    expect(n.state.ingredients.map((i) => i.product.name), ['P1', 'P2', 'P0']);
    final xml = part(DocxBlankGenerator.generate(n.state), 'word/document.xml');
    expect(xml.indexOf('P1'), lessThan(xml.indexOf('P2')));
    expect(xml.indexOf('P2'), lessThan(xml.indexOf('P0')));
    await n.flushPendingSaves();
  });
  test(
      'Debounced search cancellation completes its Future and ignores stale results',
      () async {
    final repo = FakeProducts();
    final n = SearchNotifier(repo);
    final canceled = n.search('old');
    final latest = n.search('new');
    await canceled.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 180));
    repo.requests['new']!.complete([beet]);
    await latest;
    repo.requests['']!.complete([]);
    await Future<void>.delayed(Duration.zero);
    expect(n.state.query, 'new');
    expect(n.state.results, [beet]);
    final pending = n.search('dispose');
    n.dispose();
    await pending.timeout(const Duration(seconds: 1));
    // dispose above is explicit; remove the registered teardown by using a mounted guard.
  });
  for (final mode in BlankMode.values) {
    test(
        'Fractional retention, actual yield and numeric formats exported: ${mode.name}',
        () async {
      final d = fixture(100, yieldGrams: 200).copyWith(
          blankMode: mode,
          retentionProtein: .9456,
          retentionFat: .8812,
          retentionCarbs: .9134,
          showPer100gRowInExport: true);
      final word = part(DocxBlankGenerator.generate(d), 'word/document.xml');
      expect(word, contains('94,56'));
      expect(word, contains('88,12'));
      expect(word, contains('91,34'));
      expect(word, contains('200'));
      final bytes = XlsxBlankGenerator.generate(d);
      final sheet = part(bytes, 'xl/worksheets/sheet1.xml');
      final styles = part(bytes, 'xl/styles.xml');
      expect(sheet, contains('IF(C'));
      expect(sheet, contains('94,56'));
      expect(styles, contains(r'[$-419]0.00'));
      expect(styles, contains(r'[$-419]0.0'));
      final out = Directory('../audit_artifacts/system_logic');
      await out.create(recursive: true);
      await File('${out.path}/${mode.name}.xlsx').writeAsBytes(bytes);
      await File('${out.path}/${mode.name}.docx')
          .writeAsBytes(DocxBlankGenerator.generate(d));
    });
  }

  test(
      'Unverified OCR measures are not offered; explicitly sourced egg and cream measures work',
      () {
    final wrong = beet.copyWith(name: 'Яйцо под майонезом', measures: const [
      ProductMeasure(id: 1, productId: 1, name: 'ложка', grams: 15)
    ]);
    expect(wrong.calculationMeasures, isEmpty);
    final egg = beet.copyWith(name: 'Яйцо куриное');
    expect(egg.calculationMeasures.single.grams, 47);
    expect(egg.calculationMeasures.single.name, contains('1 категория'));
    final cream = beet.copyWith(name: 'Сметана 10,0% жирности');
    expect(cream.calculationMeasures.first.grams, 250);
    expect(
        beet.copyWith(
            name: 'Мука пшеничная 1 сорта из зерна мягкой пшеницы',
            measures: const [
              ProductMeasure(id: 1, productId: 1, name: 'стакан', grams: 1160)
            ]).calculationMeasures,
        isEmpty);
    expect(
        beet
            .copyWith(source: 'usda', measures: const [
              ProductMeasure(id: 1, productId: 1, name: 'cup', grams: 99)
            ])
            .calculationMeasures
            .single
            .grams,
        99);
  });
  testWidgets('Two eggs in a named category convert to grams, not 2 grams',
      (tester) async {
    double? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomNumpadSheet(
                product: beet.copyWith(name: 'Яйцо куриное'),
                initialGrams: 100,
                onConfirm: (g, _) => saved = g))));
    await tester.tap(find.textContaining('1 шт. (1 категория'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('measure-count')), '2');
    await tester.tap(find.text('Использовать'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить в блюдо'));
    await tester.tap(find.text('Добавить в блюдо'));
    await tester.pumpAndSettle();
    expect(saved, 94);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Gross/net toggle preserves edible mass instead of reinterpreting the number',
      (tester) async {
    double? saved;
    bool? gross;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomNumpadSheet(
                product: beet.copyWith(wastePct: 50),
                initialGrams: 50,
                onConfirm: (g, b) {
                  saved = g;
                  gross = b;
                }))));
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Добавить в блюдо'));
    await tester.tap(find.text('Добавить в блюдо'));
    await tester.pumpAndSettle();
    expect(saved, 100);
    expect(gross, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Opening and confirming mass editor preserves original precision',
      (tester) async {
    double? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomNumpadSheet(
                product: beet,
                initialGrams: .15,
                isEditing: true,
                onConfirm: (g, _) => saved = g))));
    await tester.ensureVisible(find.text('Сохранить изменения'));
    await tester.tap(find.text('Сохранить изменения'));
    await tester.pumpAndSettle();
    expect(saved, .15);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Retention settings preserve decimals and accept zero, reject junk',
      (tester) async {
    final n = DishNotifier();
    n.addIngredient(beet, 100);
    n.setRetention(protein: .9456);
    await tester.pumpWidget(ProviderScope(
        overrides: [dishProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: RecipeEditorScreen())));
    await tester.tap(find.byTooltip('Параметры'));
    await tester.pumpAndSettle();
    final p = find.widgetWithText(TextField, 'Белки %');
    expect(tester.widget<TextField>(p).controller!.text, '94,56');
    await tester.enterText(p, 'junk');
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(find.text('Введите каждый процент от 0 до 100.'), findsOneWidget);
    expect(n.state.retentionProtein, .9456);
    await tester.enterText(p, '0');
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(n.state.retentionProtein, 0);
    expect(tester.takeException(), isNull);
    await n.flushPendingSaves();
  });
  testWidgets(
      'Portion 200 g equals whole dish even when rounded per100 does not',
      (tester) async {
    final r = CalculationEngine.calculate(fixture(100, yieldGrams: 200));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: MacroSummaryBar(result: r)))));
    expect(find.textContaining('Порция 200 г: Б: 1,41'), findsOneWidget);
    final field = find.byKey(const ValueKey('portion-grams'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(find.text('Введите массу от 0,1 до 9999999 г'), findsOneWidget);
    await tester.enterText(field, '100');
    await tester.pump();
    expect(find.textContaining('Порция 100 г: Б: 0,71'), findsOneWidget);
  });
}
