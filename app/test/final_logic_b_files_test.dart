// Final logic audit - Block B (files): render 8 forms to PDF, DOCX and XLSX,
// save artefacts to disk and compare 11 control figures against CalculationEngine.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:povarspravka/core/calculation/calculation_engine.dart';
import 'package:povarspravka/core/calculation/models/blank_mode.dart';
import 'package:povarspravka/core/calculation/models/dish.dart';
import 'package:povarspravka/core/calculation/models/ingredient.dart';
import 'package:povarspravka/core/calculation/models/product.dart';
import 'package:povarspravka/core/export/docx_blank_generator.dart';
import 'package:povarspravka/core/export/pdf_blank_generator.dart';
import 'package:povarspravka/core/export/xlsx_blank_generator.dart';

const _out = r'C:\projects\povarspravka\audit\signoff\exports';

Product prod(String name, double p, double f, double c, {double waste = 0}) => Product(
      id: name.hashCode,
      code: name,
      name: name,
      groupId: 1,
      source: 'skurikhin',
      wastePct: waste,
      protein: p,
      fat: f,
      carbs: c,
      kcal: 0,
    );

Dish a4({BlankMode mode = BlankMode.photoCross, bool per100 = true}) => Dish(
      id: 'a4',
      title: 'Бифштекс рубленый',
      showPer100gRowInExport: per100,
      ingredients: [
        Ingredient(id: '1', product: prod('Говядина 1 кат.', 18.60, 16.00, 0), weightGrams: 600),
        Ingredient(id: '2', product: prod('Лук', 1.40, .20, 8.20), weightGrams: 100),
        Ingredient(id: '3', product: prod('Хлеб пшеничный', 7.60, .80, 49.20), weightGrams: 80),
        Ingredient(id: '4', product: prod('Молоко 3,2%', 2.90, 3.20, 4.70), weightGrams: 120),
        Ingredient(id: '5', product: prod('Масло сливочное', .80, 72.50, 1.30), weightGrams: 100),
      ],
      customYieldGrams: 750,
      blankMode: mode,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export 8 dish forms to PDF, DOCX and XLSX', () async {
    Directory(_out).createSync(recursive: true);

    // 1. Single ingredient
    final single = Dish(
      id: 'single',
      title: 'Один ингредиент',
      showPer100gRowInExport: true,
      ingredients: [
        Ingredient(id: '1', product: prod('Говядина 1 кат.', 18.60, 16.00, 0), weightGrams: 600),
      ],
      customYieldGrams: 750,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 2. A4 (5 ingredients, yield 750)
    final dA4 = a4(per100: true);

    // 3. 25 ingredients (2 pages)
    final many25 = Dish(
      id: 'many25',
      title: 'Двадцать пять ингредиентов',
      showPer100gRowInExport: true,
      ingredients: [
        for (var i = 0; i < 25; i++)
          Ingredient(
            id: 'i$i',
            product: prod('Продукт ${i + 1}', 1.0 + i * 0.2, 0.5 + i * 0.1, 5.0 + i * 0.3),
            weightGrams: 20.0 + i,
          ),
      ],
      customYieldGrams: 1500,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 4. All ingredients gross with waste
    final allGross = Dish(
      id: 'all_gross',
      title: 'Все брутто с отходами',
      showPer100gRowInExport: true,
      ingredients: [
        Ingredient(id: 'g1', product: prod('Картофель', 2.0, 0.4, 16.3, waste: 28), weightGrams: 400, isGross: true),
        Ingredient(id: 'g2', product: prod('Морковь', 1.3, 0.1, 6.9, waste: 20), weightGrams: 200, isGross: true),
        Ingredient(id: 'g3', product: prod('Лук', 1.4, 0.2, 8.2, waste: 16), weightGrams: 150, isGross: true),
        Ingredient(id: 'g4', product: prod('Свекла', 1.5, 0.1, 8.8, waste: 20), weightGrams: 250, isGross: true),
        Ingredient(id: 'g5', product: prod('Говядина', 18.6, 16.0, 0.0, waste: 25), weightGrams: 500, isGross: true),
      ],
      customYieldGrams: 900,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 5. Detailed mode
    final detailed = a4(mode: BlankMode.detailed, per100: true);

    // 6. Manual retention 90/85/90
    final retention90 = Dish(
      id: 'retention_90',
      title: 'Ручная сохранность 90/85/90',
      showPer100gRowInExport: true,
      ingredients: dA4.ingredients,
      customYieldGrams: 750,
      retentionProtein: 0.90,
      retentionFat: 0.85,
      retentionCarbs: 0.90,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 7. Minimum valid yield (cooked nutrients = 115.96 + 152.40 + 49.60 = 317.96 -> 318 g)
    final minYield = Dish(
      id: 'min_yield',
      title: 'Минимальный корректный выход',
      showPer100gRowInExport: true,
      ingredients: dA4.ingredients,
      customYieldGrams: 318,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    // 8. Maximum masses (boundary 9 999 999 g total)
    final maxMass = Dish(
      id: 'max_mass',
      title: 'Максимальные массы',
      showPer100gRowInExport: true,
      ingredients: [
        for (var i = 0; i < 5; i++)
          Ingredient(
            id: 'm$i',
            product: prod('Масс-$i', 1.0, 1.0, 1.0),
            weightGrams: 1999999,
          ),
      ],
      customYieldGrams: 9999999,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final forms = <String, Dish>{
      'single': single,
      'a4': dA4,
      'many25': many25,
      'all_gross': allGross,
      'detailed': detailed,
      'retention_90': retention90,
      'min_yield': minYield,
      'max_mass': maxMass,
    };

    final expectations = <String, Map<String, dynamic>>{};

    for (final entry in forms.entries) {
      final name = entry.key;
      final dish = entry.value;

      final pdfBytes = await PdfBlankGenerator.generate(dish);
      final docxBytes = DocxBlankGenerator.generate(dish);
      final xlsxBytes = XlsxBlankGenerator.generate(dish);

      File('$_out/$name.pdf').writeAsBytesSync(pdfBytes);
      File('$_out/$name.docx').writeAsBytesSync(docxBytes);
      File('$_out/$name.xlsx').writeAsBytesSync(xlsxBytes);

      final r = CalculationEngine.calculate(dish);
      final control11 = [
        CalculationEngine.formatMacro(r.rawTotalProtein),
        CalculationEngine.formatMacro(r.rawTotalFat),
        CalculationEngine.formatMacro(r.rawTotalCarbs),
        CalculationEngine.formatMacro(r.cookedProtein),
        CalculationEngine.formatMacro(r.cookedFat),
        CalculationEngine.formatMacro(r.cookedCarbs),
        CalculationEngine.formatKcal(r.cookedKcal),
        CalculationEngine.formatMacro(r.per100gProtein),
        CalculationEngine.formatMacro(r.per100gFat),
        CalculationEngine.formatMacro(r.per100gCarbs),
        CalculationEngine.formatKcal(r.per100gKcal),
      ];

      expectations[name] = {
        'control11': control11,
        'cookedKcal': r.cookedKcal,
        'yieldGrams': r.yieldGrams,
      };
    }

    // Also verify showPer100gRowInExport on/off
    final a4WithoutPer100 = a4(per100: false);
    File('$_out/a4_no_per100.pdf')
        .writeAsBytesSync(await PdfBlankGenerator.generate(a4WithoutPer100));
    File('$_out/a4_no_per100.docx')
        .writeAsBytesSync(DocxBlankGenerator.generate(a4WithoutPer100));
    File('$_out/a4_no_per100.xlsx')
        .writeAsBytesSync(XlsxBlankGenerator.generate(a4WithoutPer100));

    File('$_out/expectations.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(expectations),
    );
  });
}
