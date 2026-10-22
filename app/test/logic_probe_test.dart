// Logic audit probe: computes reference recipes through the real engine and
// writes every displayed number plus PDF/DOCX/XLSX artefacts for cross-checking.
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

const _root = r'C:\temp_audit';
const _out = r'C:\temp_audit\exports';

Dish buildDish(String key, Map<String, dynamic> data, {BlankMode? mode}) {
  final products = data['products'] as Map<String, dynamic>;
  final recipe = (data['recipes'] as Map<String, dynamic>)[key] as Map<String, dynamic>;
  final retention = (recipe['retention'] as List<dynamic>?) ?? const [0.94, 0.88, 0.91];
  final items = (recipe['items'] as List<dynamic>).cast<List<dynamic>>();
  final ings = <Ingredient>[];
  var i = 0;
  for (final item in items) {
    final p = Product.fromJson((products[item[0]] as Map).cast<String, dynamic>());
    ings.add(Ingredient(
        id: 'ing-${i++}',
        product: p,
        weightGrams: (item[1] as num).toDouble(),
        isGross: item[2] as bool));
  }
  return Dish(
    id: key,
    title: recipe['title'] as String,
    ingredients: ings,
    customYieldGrams: (recipe['yield'] as num?)?.toDouble(),
    retentionProtein: (retention[0] as num).toDouble(),
    retentionFat: (retention[1] as num).toDouble(),
    retentionCarbs: (retention[2] as num).toDouble(),
    blankMode: mode ?? BlankMode.photoCross,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

Map<String, dynamic> dishNumbers(Dish dish) {
  final r = CalculationEngine.calculate(dish);
  final rows = <Map<String, dynamic>>[];
  for (final ing in dish.ingredients) {
    rows.add({
      'name': ing.product.name,
      'gross': ing.weightGrams,
      'isGross': ing.isGross,
      'waste': ing.product.wastePct,
      'net': ing.netGramsRounded,
      'netText': CalculationEngine.formatGrams(ing.netGramsRounded),
      'p100': CalculationEngine.formatMacro(ing.product.protein),
      'p100raw': ing.product.protein,
      'pDish': CalculationEngine.formatMacro(ing.proteinInDish),
      'f100': CalculationEngine.formatMacro(ing.product.fat),
      'fDish': CalculationEngine.formatMacro(ing.fatInDish),
      'c100': CalculationEngine.formatMacro(ing.product.carbs),
      'cDish': CalculationEngine.formatMacro(ing.carbsInDish),
      'kcal': CalculationEngine.formatKcal(ing.blankKcalInDish),
      'kcalHandbook': ing.kcalInDish,
      'energyCheck': ing.product.protein * 4 + ing.product.fat * 9 + ing.product.carbs * 4,
      'handbookKcal': ing.product.kcal,
    });
  }
  return {
    'mode': dish.blankMode.name,
    'yield': CalculationEngine.formatGrams(r.yieldGrams),
    'yieldRaw': r.yieldGrams,
    'rawTotalWeight': CalculationEngine.formatGrams(r.rawTotalWeight),
    'rawTotalProtein': CalculationEngine.formatMacro(r.rawTotalProtein),
    'rawTotalFat': CalculationEngine.formatMacro(r.rawTotalFat),
    'rawTotalCarbs': CalculationEngine.formatMacro(r.rawTotalCarbs),
    'rawTotalKcal': r.rawTotalKcal == null ? null : CalculationEngine.formatKcal(r.rawTotalKcal!),
    'pctProtein': CalculationEngine.formatPercent(r.retentionProtein),
    'pctFat': CalculationEngine.formatPercent(r.retentionFat),
    'pctCarbs': CalculationEngine.formatPercent(r.retentionCarbs),
    'cookedProtein': CalculationEngine.formatMacro(r.cookedProtein),
    'cookedFat': CalculationEngine.formatMacro(r.cookedFat),
    'cookedCarbs': CalculationEngine.formatMacro(r.cookedCarbs),
    'cookedKcal': CalculationEngine.formatKcal(r.cookedKcal),
    'per100p': CalculationEngine.formatMacro(r.per100gProtein),
    'per100f': CalculationEngine.formatMacro(r.per100gFat),
    'per100c': CalculationEngine.formatMacro(r.per100gCarbs),
    'per100k': CalculationEngine.formatKcal(r.per100gKcal),
    'rows': rows,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('emit logic probe', () async {
    // Audit harness: needs the generated fixture bundle, skips elsewhere.
    if (!File('$_root\\recipes.json').existsSync()) return;
    final data = jsonDecode(File('$_root\\recipes.json').readAsStringSync())
        as Map<String, dynamic>;
    Directory(_out).createSync(recursive: true);
    final report = <String, dynamic>{};

    for (final key in ['A1', 'A2', 'A3', 'A4', 'A5']) {
      for (final mode in [BlankMode.photoCross, BlankMode.detailed]) {
        final dish = buildDish(key, data, mode: mode);
        final suffix = mode == BlankMode.photoCross ? 'photo' : 'detail';
        report['${key}_$suffix'] = dishNumbers(dish);
        expect(() => CalculationEngine.calculate(dish), returnsNormally);
      }
      final dish = buildDish(key, data);
      final pdf = await PdfBlankGenerator.generate(dish);
      File('$_out\\${key}_photo.pdf').writeAsBytesSync(pdf);
      final docx = DocxBlankGenerator.generate(dish);
      File('$_out\\${key}_photo.docx').writeAsBytesSync(docx);
      final xlsx = XlsxBlankGenerator.generate(dish);
      File('$_out\\${key}_photo.xlsx').writeAsBytesSync(xlsx);
      if (key == 'A4') {
        final withPer100 = dish.copyWith(showPer100gRowInExport: true);
        File('$_out\\A4_per100.pdf')
            .writeAsBytesSync(await PdfBlankGenerator.generate(withPer100));
        File('$_out\\A4_per100.docx')
            .writeAsBytesSync(DocxBlankGenerator.generate(withPer100));
        File('$_out\\A4_per100.xlsx')
            .writeAsBytesSync(XlsxBlankGenerator.generate(withPer100));
        final detailed = withPer100.copyWith(blankMode: BlankMode.detailed);
        File('$_out\\A4_detail.pdf')
            .writeAsBytesSync(await PdfBlankGenerator.generate(detailed));
        File('$_out\\A4_detail.docx')
            .writeAsBytesSync(DocxBlankGenerator.generate(detailed));
        File('$_out\\A4_detail.xlsx')
            .writeAsBytesSync(XlsxBlankGenerator.generate(detailed));
      }
    }

    // Block B toggles on A4.
    final a4 = buildDish('A4', data);
    final variants = <String, Dish>{
      'detail': a4.copyWith(blankMode: BlankMode.detailed),
      'gross': a4.copyWith(
          ingredients: a4.ingredients
              .map((i) => i.copyWith(
                  isGross: !i.isGross,
                  weightGrams: i.isGross
                      ? i.netGramsRounded
                      : Ingredient.grossFromNet(i.weightGrams, i.product.wastePct) ??
                          i.weightGrams))
              .toList()),
      'retention100': a4.copyWith(
          retentionProtein: 1.0, retentionFat: 1.0, retentionCarbs: 1.0),
      'per100row': a4.copyWith(showPer100gRowInExport: true),
    };
    final toggleReport = <String, dynamic>{};
    for (final e in variants.entries) {
      toggleReport[e.key] = dishNumbers(e.value);
    }
    toggleReport['base'] = dishNumbers(a4);
    report['toggles'] = toggleReport;

    // Same dish after JSON round-trip (save -> restart -> load -> duplicate).
    final roundTrip = Dish.fromJson(jsonDecode(jsonEncode(a4.toJson())) as Map<String, dynamic>);
    report['roundtrip'] = dishNumbers(roundTrip);
    report['roundtripEqual'] =
        jsonEncode(dishNumbers(roundTrip)) == jsonEncode(dishNumbers(a4));

    // Scenario exports: empty recipe, 25 ingredients, custom retention.
    final empty = Dish(
        id: 'empty',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1));
    File('$_out\\scenario_empty.pdf')
        .writeAsBytesSync(await PdfBlankGenerator.generate(empty));
    File('$_out\\scenario_empty.docx')
        .writeAsBytesSync(DocxBlankGenerator.generate(empty));
    File('$_out\\scenario_empty.xlsx')
        .writeAsBytesSync(XlsxBlankGenerator.generate(empty));

    final products = data['products'] as Map<String, dynamic>;
    final potato =
        Product.fromJson((products['potato'] as Map).cast<String, dynamic>());
    final many = Dish(
        id: 'many25',
        ingredients: [
          for (var i = 0; i < 25; i++)
            Ingredient(id: 'm$i', product: potato, weightGrams: 100)
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1));
    File('$_out\\scenario_25.pdf')
        .writeAsBytesSync(await PdfBlankGenerator.generate(many));
    File('$_out\\scenario_25.docx')
        .writeAsBytesSync(DocxBlankGenerator.generate(many));

    final custom = buildDish('A4', data).copyWith(
        retentionProtein: 0.90, retentionFat: 0.85, retentionCarbs: 0.90);
    File('$_out\\scenario_retention.pdf')
        .writeAsBytesSync(await PdfBlankGenerator.generate(custom));
    report['retention_custom'] = dishNumbers(custom);

    File('$_root\\probe.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(report));
  });
}
