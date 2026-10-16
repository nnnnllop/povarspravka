import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:povarspravka/presentation/providers/dish_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('CalculationEngine Tests', () {
    const pBeef = Product(
      id: 1,
      code: '3.1.1',
      name: 'Говядина 1 категории',
      groupId: 3,
      source: 'skurikhin',
      protein: 18.6,
      fat: 16.0,
      carbs: 0.0,
      kcal: 218.0,
      wastePct: 0.0,
    );

    const pPotato = Product(
      id: 2,
      code: '8.1.6.1',
      name: 'Картофель',
      groupId: 8,
      source: 'skurikhin',
      protein: 2.0,
      fat: 0.4,
      carbs: 16.3,
      kcal: 77.0,
      wastePct: 20.0, // 20% отходов брутто
    );

    test('Single ingredient net calculation', () {
      const ing = Ingredient(
        id: '1',
        product: pBeef,
        weightGrams: 100.0,
        isGross: false,
      );

      final dish = Dish(
        id: 'd1',
        ingredients: const [ing],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final res = CalculationEngine.calculate(dish);

      // Raw total
      expect(res.rawTotalWeight, equals(100.0));
      expect(res.rawTotalProtein, closeTo(18.6, 0.01));
      expect(res.rawTotalFat, closeTo(16.0, 0.01));
      expect(res.rawTotalCarbs, closeTo(0.0, 0.01));

      // Cooked with 94/88/91 retention
      expect(res.cookedProtein, closeTo(18.6 * 0.94, 0.01));
      expect(res.cookedFat, closeTo(16.0 * 0.88, 0.01));
      expect(res.cookedCarbs, closeTo(0.0 * 0.91, 0.01));

      // Formula: 4*P + 9*F + 4*C
      final expectedKcal = (res.cookedProtein * 4.0) + (res.cookedFat * 9.0);
      expect(res.cookedKcal, closeTo(expectedKcal, 0.1));
    });

    test('Gross mass calculation with waste percentage', () {
      // 200g gross with 20% waste -> 160g net
      const ing = Ingredient(
        id: '2',
        product: pPotato,
        weightGrams: 200.0,
        isGross: true,
      );

      expect(ing.netGrams, equals(160.0));
      expect(ing.proteinInDish, closeTo((160.0 * 2.0) / 100.0, 0.01)); // 3.2g
      expect(ing.fatInDish, closeTo((160.0 * 0.4) / 100.0, 0.01)); // 0.64g
      expect(ing.carbsInDish, closeTo((160.0 * 16.3) / 100.0, 0.01)); // 26.08g
    });

    test('BlankMode photoCross vs detailed & blankKcalInDish consistency', () {
      const ing = Ingredient(id: '1', product: pBeef, weightGrams: 100.0);
      expect(
          ing.blankKcalInDish, closeTo(18.6 * 4.0 + 16.0 * 9.0, 0.01)); // 218.4

      final dishCross = Dish(
        id: 'd_cross',
        blankMode: BlankMode.photoCross,
        ingredients: const [ing],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final resCross = CalculationEngine.calculate(dishCross);
      expect(resCross.rawTotalKcal, isNull);

      final dishDetailed = dishCross.copyWith(blankMode: BlankMode.detailed);
      final resDetailed = CalculationEngine.calculate(dishDetailed);
      expect(resDetailed.rawTotalKcal, isNotNull);
      expect(resDetailed.rawTotalKcal, closeTo(218.4, 0.01));
      // Raw blank kcal is never lower than cooked kcal
      expect(resDetailed.rawTotalKcal!, greaterThan(resDetailed.cookedKcal));
    });

    test('Column sums match 2-decimal rounded values exactly to 0.01', () {
      const fractionalProduct = Product(
        id: 3,
        code: '1.1',
        name: 'Сметана',
        groupId: 1,
        source: 'skurikhin',
        protein: 2.6,
        fat: 15.0,
        carbs: 3.6,
        kcal: 160.0,
      );

      final ingredients = List.generate(
        7,
        (i) => const Ingredient(
          id: 'frac',
          product: fractionalProduct,
          weightGrams: 33.0, // 33 * 2.6 / 100 = 0.858 -> rounds to 0.86
        ),
      );

      final dish = Dish(
        id: 'd_rounding',
        ingredients: ingredients,
        blankMode: BlankMode.detailed,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final res = CalculationEngine.calculate(dish);
      // Printed protein cell is 0,86; 7 * 0.86 = 6.02 (whereas 7 * 0.858 = 6.006)
      expect(res.rawTotalProtein, closeTo(7 * 0.86, 0.001));
    });

    test('Russian decimal comma formatting and parseInputDouble', () {
      expect(CalculationEngine.formatGrams(100.0), equals('100'));
      expect(CalculationEngine.formatGrams(145.4), equals('145,4'));
      expect(CalculationEngine.formatMacro(18.6), equals('18,60'));
      expect(CalculationEngine.formatKcal(196.64), equals('196,6'));

      expect(CalculationEngine.parseInputDouble('18,60'), closeTo(18.6, 0.001));
      expect(CalculationEngine.parseInputDouble('18.60'), closeTo(18.6, 0.001));
      expect(CalculationEngine.parseInputDouble('  '), isNull);
    });

    test(
        'Dish copyWith clearCustomYield and DishNotifier retention customization',
        () {
      final notifier = DishNotifier();
      notifier.addIngredient(pBeef, 200.0);
      notifier.setCustomYield(150.0);
      expect(notifier.state.customYieldGrams, equals(150.0));
      expect(notifier.state.effectiveYieldGrams, equals(150.0));

      // Clear custom yield back to null -> effectiveYieldGrams falls back to totalRawNetGrams (200.0)
      notifier.setCustomYield(null);
      expect(notifier.state.customYieldGrams, isNull);
      expect(notifier.state.effectiveYieldGrams, equals(200.0));

      // Customize retention to 100% (no thermal processing)
      notifier.setRetention(protein: 1.0, fat: 1.0, carbs: 1.0);
      final res = CalculationEngine.calculate(notifier.state);
      expect(res.cookedProtein, closeTo(res.rawTotalProtein, 0.001));
      expect(res.cookedFat, closeTo(res.rawTotalFat, 0.001));
      expect(res.cookedCarbs, closeTo(res.rawTotalCarbs, 0.001));
    });

    test('Unlimited ingredients (25 items) handles smoothly without overflow',
        () {
      final ingredients = List.generate(
        25,
        (i) => Ingredient(
          id: 'item_$i',
          product: i.isEven ? pBeef : pPotato,
          weightGrams: 50.0,
        ),
      );

      final dish = Dish(
        id: 'd_large',
        ingredients: ingredients,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final res = CalculationEngine.calculate(dish);
      expect(res.rawTotalWeight, equals(25 * 50.0));
      expect(res.cookedKcal, greaterThan(0));
    });

    test(
        'DOCX, XLSX, and PDF Blank Generators produce valid 1:1 blank documents',
        () async {
      final dish = Dish(
        id: 'd_export',
        title: 'Борщ сибирский',
        showTitleInExport: true,
        blankMode: BlankMode.photoCross,
        ingredients: const [
          Ingredient(id: '1', product: pBeef, weightGrams: 100.0),
          Ingredient(id: '2', product: pPotato, weightGrams: 150.0),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 1. Validate DOCX XML
      final docxBytes = DocxBlankGenerator.generate(dish);
      expect(docxBytes, isNotEmpty);
      final docxArchive = ZipDecoder().decodeBytes(docxBytes);
      final docXmlFile = docxArchive.findFile('word/document.xml');
      expect(docXmlFile, isNotNull);
      final docXmlStr = utf8.decode(docXmlFile!.content as List<int>);
      final parsedDocXml = XmlDocument.parse(docXmlStr);
      expect(parsedDocXml.rootElement.name.local, equals('document'));
      expect(docXmlStr,
          contains('Расчет энергетической и пищевой ценности блюда'));
      expect(docXmlStr, contains('Сохранность,%'));
      expect(docXmlStr, contains('После тепловой обработки'));
      expect(docXmlStr, contains('Сохранность после тепловой обработки:'));
      expect(docXmlStr, contains('= Сумма белков *94 /100'));
      expect(docXmlStr, contains('w:tl2br'));
      expect(docXmlStr, contains('w:tr2bl'));
      expect(docXmlStr, contains('w:vMerge'));

      // 2. Validate XLSX XML & Formulas
      final xlsxBytes = XlsxBlankGenerator.generate(dish);
      expect(xlsxBytes, isNotEmpty);
      final xlsxArchive = ZipDecoder().decodeBytes(xlsxBytes);
      final sheetXmlFile = xlsxArchive.findFile('xl/worksheets/sheet1.xml');
      expect(sheetXmlFile, isNotNull);
      final sheetXmlStr = utf8.decode(sheetXmlFile!.content as List<int>);
      final parsedSheetXml = XmlDocument.parse(sheetXmlStr);
      expect(parsedSheetXml.rootElement.name.local, equals('worksheet'));
      expect(sheetXmlStr, contains('<mergeCells'));
      expect(sheetXmlStr, contains('<f>ROUND('));
      expect(sheetXmlStr,
          contains('<pageSetup paperSize="9" orientation="landscape"'));
      expect(sheetXmlStr, contains('Сохранность,%'));
      expect(sheetXmlStr, contains('После тепловой обработки'));

      // 3. Validate PDF generation
      final pdfBytes = await PdfBlankGenerator.generate(dish);
      expect(pdfBytes.length, greaterThan(500));
      expect(String.fromCharCodes(pdfBytes.take(5)), equals('%PDF-'));
    });
  });
}
