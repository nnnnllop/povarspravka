import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/data/repositories/dish_storage_repository.dart';
import 'package:povarspravka/data/repositories/product_repository.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';
import 'package:povarspravka/presentation/providers/search_provider.dart';
import 'package:povarspravka/presentation/screens/search_product_modal.dart';
import 'package:povarspravka/presentation/widgets/custom_numpad.dart';
import 'culinary_logic_test.dart' show beet, fixture;

class CatalogRepo extends ProductRepository {
  final List<Product> products;
  CatalogRepo(this.products);
  @override
  Future<List<Product>> searchProducts(
          {required String query,
          int? groupId,
          String? source,
          int limit = 50}) async =>
      products;
  @override
  Future<List<FoodGroup>> getFoodGroups() async => [];
  @override
  Future<List<ProductNutrient>> getNutrientsForProduct(int productId) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auditRoot = Directory('../audit_artifacts/mega')
    ..createSync(recursive: true);
  final out = auditRoot.createTempSync('exports_');
  File('${auditRoot.path}/latest_exports.txt')
      .writeAsStringSync(out.absolute.path);
  for (final mode in BlankMode.values) {
    for (final n in [0, 1, 18, 19, 50, 100]) {
      test('MEGA export ${mode.name} $n unicode 500 codepoints', () async {
        await out.create(recursive: true);
        const special = '«Суп» " & < > \' \u00a0 — \n 🍲🥩 ';
        final title = String.fromCharCodes((special * 40).runes.take(500));
        final base = fixture(100);
        final d = base.copyWith(
            title: title,
            showTitleInExport: true,
            showPer100gRowInExport: true,
            blankMode: mode,
            ingredients: List.generate(
                n,
                (i) => base.ingredients.single.copyWith(
                    id: 'i$i',
                    product:
                        beet.copyWith(name: 'Ingredient-$i & < > «овощ»'))));
        final prefix = '${out.path}/${mode.name}_$n';
        await File('$prefix.docx').writeAsBytes(DocxBlankGenerator.generate(d));
        await File('$prefix.xlsx').writeAsBytes(XlsxBlankGenerator.generate(d));
        await File('$prefix.pdf')
            .writeAsBytes(await PdfBlankGenerator.generate(d));
      });
    }
  }
  for (final damage in ['empty', 'truncated', 'invalid_utf8', 'schema']) {
    test('MEGA backup recovery $damage preserves full previous library',
        () async {
      final dir = await Directory.systemTemp.createTemp('mega_crash_');
      try {
        final repo = DishStorageRepository(storageDirectory: dir);
        final previous = List.generate(
            10,
            (i) => fixture(100 + i.toDouble())
                .copyWith(id: 'd$i', title: 'Dish $i'));
        await repo.saveAll(activeDraft: previous.first, savedDishes: previous);
        await repo
            .saveAll(activeDraft: fixture(999), savedDishes: [fixture(999)]);
        final main = File('${dir.path}/povarspravka_user_dishes.json');
        final bak = File('${main.path}.bak');
        final before = await bak.readAsBytes();
        await main.writeAsBytes(
            switch (damage) {
              'empty' => <int>[],
              'truncated' => utf8.encode('{"savedDishes":['),
              'invalid_utf8' => <int>[255, 254, 0, 128],
              _ => utf8.encode('{"savedDishes":[123],"activeDraft":null}')
            },
            flush: true);
        final restored =
            await DishStorageRepository(storageDirectory: dir).loadAll();
        expect(restored.savedDishes.map((d) => d.toJson()).toList(),
            previous.map((d) => d.toJson()).toList());
        expect(restored.activeDraft!.toJson(), previous.first.toJson());
        expect(await bak.readAsBytes(), before);
        expect(
            (await DishStorageRepository(storageDirectory: dir).loadAll())
                .savedDishes
                .length,
            10);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
  test('MEGA ten concurrent mixed library mutations agree with restarted disk',
      () async {
    final dir = await Directory.systemTemp.createTemp('mega_race_');
    final s = DishStorageRepository(storageDirectory: dir);
    final n = SavedDishesNotifier(s);
    try {
      final a = fixture(100).copyWith(id: 'a'),
          b = fixture(200).copyWith(id: 'b'),
          c = fixture(300).copyWith(id: 'c');
      final jobs = <Future<Object?>>[
        n.saveDish(a),
        n.saveDish(b),
        n.duplicateDish(a),
        n.deleteDish('a'),
        n.saveDish(c),
        n.duplicateDish(b),
        n.deleteDish('b'),
        n.saveDish(a),
        n.duplicateDish(c),
        n.deleteDish('c')
      ];
      await Future.wait(jobs);
      expect(n.state.length, 4);
      expect(n.state.map((d) => d.id).toSet().length, 4);
      final disk = await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(disk.savedDishes.map((d) => d.toJson()).toList(),
          n.state.map((d) => d.toJson()).toList());
    } finally {
      n.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('MEGA locale, five deletions and manual-auto yield roundtrip', () async {
    expect(CalculationEngine.parseInputDouble('100.5'), 100.5);
    expect(CalculationEngine.parseInputDouble('100,5'), 100.5);
    final n = DishNotifier();
    try {
      for (var i = 0; i < 5; i++) {
        n.addIngredient(beet, 100.5);
      }
      final initial = CalculationEngine.calculate(n.state);
      n.setCustomYield(1000);
      n.setCustomYield(null);
      expect(CalculationEngine.calculate(n.state).rawTotalWeight,
          initial.rawTotalWeight);
      for (final id in n.state.ingredients.map((i) => i.id).toList()) {
        n.removeIngredient(id);
      }
      final r = CalculationEngine.calculate(n.state);
      expect(r.yieldGrams, 0);
      expect(r.cookedKcal, 0);
      await n.flushPendingSaves();
    } finally {
      n.dispose();
    }
  });
  testWidgets(
      'MEGA 10 gross/net cycles preserve edible grams at 33.333 percent waste',
      (tester) async {
    double? saved;
    bool? gross;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomNumpadSheet(
                product: beet.copyWith(wastePct: 33.333),
                initialGrams: 100.5,
                onConfirm: (g, b) {
                  saved = g;
                  gross = b;
                }))));
    for (var i = 0; i < 20; i++) {
      final toggle = find.byType(Switch);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    final add = find.text('Добавить в блюдо');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(gross, false);
    expect(saved, closeTo(100.5, .00000001));
  });
  test(
      'MEGA single bit corruption of a valid number recovers previous snapshot',
      () async {
    final dir = await Directory.systemTemp.createTemp('mega_bit_');
    try {
      final s = DishStorageRepository(storageDirectory: dir);
      await s.saveAll(activeDraft: fixture(100), savedDishes: [fixture(100)]);
      await s.saveAll(activeDraft: fixture(200), savedDishes: [fixture(200)]);
      final main = File('${dir.path}/povarspravka_user_dishes.json');
      final text = await main.readAsString();
      expect(text, contains('200.0'));
      await main.writeAsString(text.replaceFirst('200.0', '201.0'),
          flush: true);
      final restored =
          await DishStorageRepository(storageDirectory: dir).loadAll();
      expect(restored.activeDraft!.ingredients.single.weightGrams, 100);
      expect(restored.savedDishes.single.ingredients.single.weightGrams, 100);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  // Numeric regression fixtures mirror the two catalog anomalies; the separate
  // mega_fuzz.dart tool verifies every actual catalog row through Product.fromJson.
  for (final id in [167611, 167702]) {
    final product = beet.copyWith(
        id: id,
        source: 'usda',
        name: 'Аномальный продукт $id',
        protein: id == 167611 ? .56 : .11,
        fat: id == 167611 ? 99.6 : 99.98,
        carbs: 0);
    testWidgets('MEGA invalid $id search selection is guarded', (tester) async {
      final dn = DishNotifier();
      await tester.pumpWidget(ProviderScope(overrides: [
        productRepositoryProvider.overrideWithValue(CatalogRepo([product])),
        dishProvider.overrideWith((ref) => dn)
      ], child: const MaterialApp(home: Scaffold(body: SearchProductModal()))));
      await tester.pumpAndSettle();
      expect(find.text(product.name), findsOneWidget);
      await tester.tap(find.text(product.name));
      await tester.pumpAndSettle();
      expect(find.textContaining('недоступен для расчёта'), findsOneWidget);
      expect(find.byType(CustomNumpadSheet), findsNothing);
      expect(dn.state.ingredients, isEmpty);
      expect(tester.takeException(), isNull);
    });
    testWidgets('MEGA invalid $id info card disables adding', (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(CatalogRepo([product]))
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: ProductInfoCardSheet(
                      product: product,
                      onAddToRecipe: () {
                        throw StateError('invalid product callback');
                      })))));
      await tester.pumpAndSettle();
      final warning = find.textContaining('доступен только для справки');
      await tester.ensureVisible(warning);
      expect(warning, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
