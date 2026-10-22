import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';
import 'package:archive/archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Product makeProduct({required String name, double waste = 0}) => Product(
        id: name.hashCode,
        code: name,
        name: name,
        groupId: 1,
        source: 'skurikhin',
        wastePct: waste,
        protein: 10,
        fat: 5,
        carbs: 20,
        kcal: 165,
      );

  test('Export warns when gross ingredient has 0% waste (LOGIC-B16)', () async {
    final dishWithZeroWasteGross = Dish(
      id: 'd_warn',
      title: 'Предупреждение по отходам',
      ingredients: [
        Ingredient(
          id: '1',
          product: makeProduct(name: 'Редкий продукт', waste: 0),
          weightGrams: 200,
          isGross: true,
        ),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // PDF
    final pdfBytes = await PdfBlankGenerator.generate(dishWithZeroWasteGross);
    expect(pdfBytes.length, greaterThan(500));

    // DOCX
    final docxBytes = DocxBlankGenerator.generate(dishWithZeroWasteGross);
    final docxArchive = ZipDecoder().decodeBytes(docxBytes);
    final docXml = utf8.decode(
        docxArchive.findFile('word/document.xml')!.content as List<int>);
    expect(docXml, contains('Предупреждение: для сырья брутто без указания отходов'));
    expect(docXml, contains('Редкий продукт'));

    // XLSX
    final xlsxBytes = XlsxBlankGenerator.generate(dishWithZeroWasteGross);
    final xlsxArchive = ZipDecoder().decodeBytes(xlsxBytes);
    final sheetXml = utf8.decode(
        xlsxArchive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheetXml, contains('Предупреждение: для сырья брутто без указания отходов'));
    expect(sheetXml, contains('Редкий продукт'));
  });

  test('Export does NOT warn when gross ingredient has specified waste > 0', () async {
    final dishWithKnownWasteGross = Dish(
      id: 'd_nowarn',
      title: 'Без предупреждения',
      ingredients: [
        Ingredient(
          id: '1',
          product: makeProduct(name: 'Картофель', waste: 28),
          weightGrams: 200,
          isGross: true,
        ),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final docxBytes = DocxBlankGenerator.generate(dishWithKnownWasteGross);
    final docxArchive = ZipDecoder().decodeBytes(docxBytes);
    final docXml = utf8.decode(
        docxArchive.findFile('word/document.xml')!.content as List<int>);
    expect(docXml, isNot(contains('Предупреждение')));

    final xlsxBytes = XlsxBlankGenerator.generate(dishWithKnownWasteGross);
    final xlsxArchive = ZipDecoder().decodeBytes(xlsxBytes);
    final sheetXml = utf8.decode(
        xlsxArchive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheetXml, isNot(contains('Предупреждение')));
  });
}
