import 'openxml_text.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../calculation/calculation_engine.dart';
import '../calculation/calculation_math.dart';
import '../calculation/loss_table.dart';
import '../calculation/models/blank_mode.dart';
import '../calculation/models/dish.dart';

class XlsxBlankGenerator {
  static String _titleText(String title) =>
      title.trim().replaceAll(RegExp(r'\s+'), ' ');

  // Merged rows do not support Excel AutoFit. Reserve conservative line height
  // for the full title (including 500-codepoint stress titles), not a fixed 18pt.
  static int _titleHeight(String title) =>
      (18 * ((_titleText(title).runes.length + 59) ~/ 60))
          .clamp(18, 409)
          .toInt();

  static double _round2(double v) => CalculationMath.round2(v);
  static double _productRounded(double a, double b, int digits,
          {bool divideBy100 = false}) =>
      CalculationMath.productRounded(a, b, digits, divideBy100: divideBy100);

  /// Потери, % — как в таблице (`15`, `7.5`), для живой формулы Excel.
  static String _pctLiteral(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  /// Генерация бинарного файла .xlsx с объединением ячеек, диагональным крестом и живыми формулами Excel
  static Uint8List generate(Dish dish) {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';
    _addFile(archive, '[Content_Types].xml', contentTypesXml);

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', relsXml);

    // 3. xl/_rels/workbook.xml.rels
    const wbRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';
    _addFile(archive, 'xl/_rels/workbook.xml.rels', wbRelsXml);

    // 4. xl/workbook.xml
    const wbXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Бланк расчета" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>''';
    _addFile(archive, 'xl/workbook.xml', wbXml);
    _addFile(archive, 'xl/styles.xml', _stylesXml);
    _addFile(archive, 'xl/worksheets/sheet1.xml', _buildDishSheetXml(dish));

    final zipEncoder = ZipEncoder();
    final bytes = zipEncoder.encode(archive);
    return Uint8List.fromList(bytes ?? []);
  }

  /// Пакетный экспорт в одну книгу Excel: лист «Сводка» + отдельный лист на
  /// каждое выбранное блюдо.
  static Uint8List generateBatch(List<Dish> dishes) {
    if (dishes.isEmpty) {
      throw ArgumentError('Выберите хотя бы одно блюдо для экспорта');
    }
    final archive = Archive();
    final usedNamesLower = <String>{'сводка'};
    final sheetSpecs = <({String name, String xml})>[
      (name: 'Сводка', xml: _buildSummarySheetXml(dishes)),
    ];
    for (final d in dishes) {
      final title = d.title.trim().isEmpty ? 'Блюдо' : d.title.trim();
      final sheetName = _uniqueSheetName(title, usedNamesLower);
      sheetSpecs.add((
        name: sheetName,
        xml: _buildDishSheetXml(d.copyWith(showTitleInExport: true)),
      ));
    }

    final overridesSb = StringBuffer();
    final wbRelsSb = StringBuffer();
    final sheetsSb = StringBuffer();
    for (var i = 0; i < sheetSpecs.length; i++) {
      final idx = i + 1;
      overridesSb.writeln(
        '  <Override PartName="/xl/worksheets/sheet$idx.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
      wbRelsSb.writeln(
        '  <Relationship Id="rId$idx" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet$idx.xml"/>',
      );
      sheetsSb.writeln(
        '    <sheet name="${_escape(sheetSpecs[i].name)}" '
        'sheetId="$idx" r:id="rId$idx"/>',
      );
      _addFile(archive, 'xl/worksheets/sheet$idx.xml', sheetSpecs[i].xml);
    }

    final stylesRid = sheetSpecs.length + 1;
    final contentTypesXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.main+xml"/>
$overridesSb  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>''';
    _addFile(archive, '[Content_Types].xml', contentTypesXml);
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', relsXml);
    _addFile(
      archive,
      'xl/_rels/workbook.xml.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$wbRelsSb  <Relationship Id="rId$stylesRid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''',
    );
    _addFile(
      archive,
      'xl/workbook.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
$sheetsSb  </sheets>
</workbook>''',
    );
    _addFile(archive, 'xl/styles.xml', _stylesXml);

    final zipEncoder = ZipEncoder();
    final bytes = zipEncoder.encode(archive);
    return Uint8List.fromList(bytes ?? []);
  }

  static String _uniqueSheetName(String rawTitle, Set<String> usedLower) {
    var cleaned = rawTitle
        .replaceAll(RegExp(r'[\\/?*\[\]:]+'), ' ')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) cleaned = 'Блюдо';
    if (cleaned.length > 31) cleaned = cleaned.substring(0, 31).trim();
    if (cleaned.isEmpty) cleaned = 'Блюдо';

    var candidate = cleaned;
    var suffixNum = 2;
    while (usedLower.contains(candidate.toLowerCase())) {
      final suffix = ' ($suffixNum)';
      final maxPrefix = 31 - suffix.length;
      final prefix = cleaned.length > maxPrefix
          ? cleaned.substring(0, maxPrefix).trim()
          : cleaned;
      candidate = '$prefix$suffix';
      suffixNum++;
    }
    usedLower.add(candidate.toLowerCase());
    return candidate;
  }

  static String _buildSummarySheetXml(List<Dish> dishes) {
    final sb = StringBuffer();
    sb.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
  <cols>
    <col min="1" max="1" width="5" customWidth="1"/>
    <col min="2" max="2" width="34" customWidth="1"/>
    <col min="3" max="3" width="12" customWidth="1"/>
    <col min="4" max="4" width="12" customWidth="1"/>
    <col min="5" max="5" width="12" customWidth="1"/>
    <col min="6" max="6" width="12" customWidth="1"/>
    <col min="7" max="7" width="13" customWidth="1"/>
    <col min="8" max="8" width="12" customWidth="1"/>
    <col min="9" max="9" width="12" customWidth="1"/>
    <col min="10" max="10" width="12" customWidth="1"/>
    <col min="11" max="11" width="13" customWidth="1"/>
  </cols>
  <sheetData>
    <row r="1" ht="22" customHeight="1">
      <c r="A1" s="2" t="inlineStr"><is><t>Сводная таблица КБЖУ сборника (${dishes.length} блюд)</t></is></c>
    </row>
    <row r="2" ht="24" customHeight="1">
      <c r="A2" s="1" t="inlineStr"><is><t>№</t></is></c>
      <c r="B2" s="1" t="inlineStr"><is><t>Наименование блюда</t></is></c>
      <c r="C2" s="1" t="inlineStr"><is><t>Выход, г</t></is></c>
      <c r="D2" s="1" t="inlineStr"><is><t>Б, г</t></is></c>
      <c r="E2" s="1" t="inlineStr"><is><t>Ж, г</t></is></c>
      <c r="F2" s="1" t="inlineStr"><is><t>У, г</t></is></c>
      <c r="G2" s="1" t="inlineStr"><is><t>Ккал</t></is></c>
      <c r="H2" s="1" t="inlineStr"><is><t>Б / 100 г</t></is></c>
      <c r="I2" s="1" t="inlineStr"><is><t>Ж / 100 г</t></is></c>
      <c r="J2" s="1" t="inlineStr"><is><t>У / 100 г</t></is></c>
      <c r="K2" s="1" t="inlineStr"><is><t>Ккал / 100 г</t></is></c>
    </row>
''');

    var rowIdx = 3;
    final firstDataRow = rowIdx;
    double sumP = 0, sumF = 0, sumC = 0, sumKcal = 0;

    for (var i = 0; i < dishes.length; i++) {
      final d = dishes[i];
      final calc = CalculationEngine.calculate(d);
      final title =
          d.title.trim().isEmpty ? 'Блюдо без названия' : _titleText(d.title);
      final noYield = calc.usesLossTable && !calc.hasYield;
      sumP = _round2(sumP + calc.cookedProtein);
      sumF = _round2(sumF + calc.cookedFat);
      sumC = _round2(sumC + calc.cookedCarbs);
      sumKcal = CalculationMath.round1(sumKcal + calc.cookedKcal);

      final yieldCell = noYield
          ? '<c r="C$rowIdx" s="0" t="inlineStr"><is><t>—</t></is></c>'
          : '<c r="C$rowIdx" s="10"><v>${calc.yieldGrams.toStringAsFixed(1)}</v></c>';
      String per100Cell(String col, String style, double val, int digits) =>
          noYield
              ? '<c r="$col$rowIdx" s="$style" t="inlineStr"><is><t>—</t></is></c>'
              : '<c r="$col$rowIdx" s="$style"><v>${val.toStringAsFixed(digits)}</v></c>';

      sb.write('''
    <row r="$rowIdx" ht="18" customHeight="1">
      <c r="A$rowIdx" s="0"><v>${i + 1}</v></c>
      <c r="B$rowIdx" s="5" t="inlineStr"><is><t>${_escape(title)}</t></is></c>
      $yieldCell
      <c r="D$rowIdx" s="3"><v>${calc.cookedProtein.toStringAsFixed(2)}</v></c>
      <c r="E$rowIdx" s="3"><v>${calc.cookedFat.toStringAsFixed(2)}</v></c>
      <c r="F$rowIdx" s="3"><v>${calc.cookedCarbs.toStringAsFixed(2)}</v></c>
      <c r="G$rowIdx" s="10"><v>${calc.cookedKcal.toStringAsFixed(1)}</v></c>
      ${per100Cell('H', '3', calc.per100gProtein, 2)}
      ${per100Cell('I', '3', calc.per100gFat, 2)}
      ${per100Cell('J', '3', calc.per100gCarbs, 2)}
      ${per100Cell('K', '10', calc.per100gKcal, 1)}
    </row>
''');
      rowIdx++;
    }

    final lastDataRow = rowIdx - 1;
    sb.write('''
    <row r="$rowIdx" ht="19" customHeight="1">
      <c r="A$rowIdx" s="6" t="inlineStr"><is><t>ИТОГО по сборнику</t></is></c>
      <c r="B$rowIdx" s="6"/>
      <c r="C$rowIdx" s="1"/>
      <c r="D$rowIdx" s="8"><f>SUM(D$firstDataRow:D$lastDataRow)</f><v>${sumP.toStringAsFixed(2)}</v></c>
      <c r="E$rowIdx" s="8"><f>SUM(E$firstDataRow:E$lastDataRow)</f><v>${sumF.toStringAsFixed(2)}</v></c>
      <c r="F$rowIdx" s="8"><f>SUM(F$firstDataRow:F$lastDataRow)</f><v>${sumC.toStringAsFixed(2)}</v></c>
      <c r="G$rowIdx" s="9"><f>SUM(G$firstDataRow:G$lastDataRow)</f><v>${sumKcal.toStringAsFixed(1)}</v></c>
      <c r="H$rowIdx" s="1"/>
      <c r="I$rowIdx" s="1"/>
      <c r="J$rowIdx" s="1"/>
      <c r="K$rowIdx" s="1"/>
    </row>
  </sheetData>
  <mergeCells count="2">
    <mergeCell ref="A1:K1"/>
    <mergeCell ref="A$rowIdx:B$rowIdx"/>
  </mergeCells>
  <pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>
  <pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="1"/>
</worksheet>''');
    return sb.toString();
  }

  // 5. xl/styles.xml
  static const String _stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="2"><numFmt numFmtId="164" formatCode="[\$-419]0.0"/><numFmt numFmtId="165" formatCode="[\$-419]0.00"/></numFmts>
  <fonts count="3">
    <font><name val="Times New Roman"/><sz val="10"/></font>
    <font><b/><name val="Times New Roman"/><sz val="10"/></font>
    <font><b/><name val="Times New Roman"/><sz val="12"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="3">
    <border><left/><right/><top/><bottom/><diagonal/></border>
    <border>
      <left style="thin"><color auto="1"/></left>
      <right style="thin"><color auto="1"/></right>
      <top style="thin"><color auto="1"/></top>
      <bottom style="thin"><color auto="1"/></bottom>
      <diagonal/>
    </border>
    <border diagonalUp="1" diagonalDown="1">
      <left style="thin"><color auto="1"/></left>
      <right style="thin"><color auto="1"/></right>
      <top style="thin"><color auto="1"/></top>
      <bottom style="thin"><color auto="1"/></bottom>
      <diagonal style="thin"><color auto="1"/></diagonal>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="12">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
    <xf numFmtId="165" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="164" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="164" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

  static String _buildDishSheetXml(Dish dish) {
    final calc = CalculationEngine.calculate(dish);
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    double totalW = 0, totalP = 0, totalF = 0, totalC = 0, totalKcal = 0;

    // 6. xl/worksheets/sheet1.xml
    final sheetSb = StringBuffer();
    final merges = <String>[];

    sheetSb.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetPr>
    <pageSetUpPr fitToPage="1"/>
  </sheetPr>
  <cols>
    <col min="1" max="1" width="5" customWidth="1"/>
    <col min="2" max="2" width="34" customWidth="1"/>
    <col min="3" max="3" width="16" customWidth="1"/>
    <col min="4" max="4" width="11" customWidth="1"/>
    <col min="5" max="5" width="11" customWidth="1"/>
    <col min="6" max="6" width="11" customWidth="1"/>
    <col min="7" max="7" width="11" customWidth="1"/>
    <col min="8" max="8" width="11" customWidth="1"/>
    <col min="9" max="9" width="11" customWidth="1"/>
    <col min="10" max="10" width="18" customWidth="1"/>
  </cols>
  <sheetData>
''');

    int rowIdx = 1;

    // Постоянный заголовок бланка
    sheetSb.write('''
    <row r="$rowIdx" ht="20" customHeight="1">
      <c r="A$rowIdx" s="2" t="inlineStr"><is><t>Расчет энергетической и пищевой ценности блюда</t></is></c>
    </row>
''');
    merges.add('A$rowIdx:J$rowIdx');
    rowIdx++;

    // Подзаголовок с названием блюда (если включено)
    if (dish.showTitleInExport && dish.title.trim().isNotEmpty) {
      sheetSb.write('''
    <row r="$rowIdx" ht="${_titleHeight(dish.title)}" customHeight="1">
      <c r="A$rowIdx" s="2" t="inlineStr"><is><t>${_escape(_titleText(dish.title))}</t></is></c>
    </row>
''');
      merges.add('A$rowIdx:J$rowIdx');
      rowIdx++;
    }

    // Двухуровневая шапка таблицы
    final hRow1 = rowIdx;
    final hRow2 = rowIdx + 1;

    sheetSb.write('''
    <row r="$hRow1" ht="20" customHeight="1">
      <c r="A$hRow1" s="1" t="inlineStr"><is><t>№</t></is></c>
      <c r="B$hRow1" s="1" t="inlineStr"><is><t>Наименование сырья</t></is></c>
      <c r="C$hRow1" s="1" t="inlineStr"><is><t>Количество, г</t></is></c>
      <c r="D$hRow1" s="1" t="inlineStr"><is><t>Белки, г</t></is></c>
      <c r="E$hRow1" s="1"/>
      <c r="F$hRow1" s="1" t="inlineStr"><is><t>Жиры, г</t></is></c>
      <c r="G$hRow1" s="1"/>
      <c r="H$hRow1" s="1" t="inlineStr"><is><t>Углеводы, г</t></is></c>
      <c r="I$hRow1" s="1"/>
      <c r="J$hRow1" s="1" t="inlineStr"><is><t>энергетическая ценность, ккал</t></is></c>
    </row>
    <row r="$hRow2" ht="24" customHeight="1">
      <c r="A$hRow2" s="1"/>
      <c r="B$hRow2" s="1"/>
      <c r="C$hRow2" s="1"/>
      <c r="D$hRow2" s="1" t="inlineStr"><is><t>В 100 г</t></is></c>
      <c r="E$hRow2" s="1" t="inlineStr"><is><t>В блюде</t></is></c>
      <c r="F$hRow2" s="1" t="inlineStr"><is><t>В 100 г</t></is></c>
      <c r="G$hRow2" s="1" t="inlineStr"><is><t>В блюде</t></is></c>
      <c r="H$hRow2" s="1" t="inlineStr"><is><t>В 100 г</t></is></c>
      <c r="I$hRow2" s="1" t="inlineStr"><is><t>В блюде</t></is></c>
      <c r="J$hRow2" s="1"/>
    </row>
''');
    merges.addAll([
      'A$hRow1:A$hRow2',
      'B$hRow1:B$hRow2',
      'C$hRow1:C$hRow2',
      'D$hRow1:E$hRow1',
      'F$hRow1:G$hRow1',
      'H$hRow1:I$hRow1',
      'J$hRow1:J$hRow2',
    ]);
    rowIdx = hRow2 + 1;

    // Строки продуктов (минимум 18 строк; пустые строки НЕ нумеруются)
    const minRows = 18;
    final totalRows =
        dish.ingredients.length < minRows ? minRows : dish.ingredients.length;
    final firstDataRow = rowIdx;

    for (int i = 0; i < totalRows; i++) {
      final r = rowIdx;
      if (i < dish.ingredients.length) {
        final ing = dish.ingredients[i];
        final netW = ing.netGramsRounded;
        final p100 = _round2(ing.product.protein);
        final pDish = ing.proteinInDish;
        final f100 = _round2(ing.product.fat);
        final fDish = ing.fatInDish;
        final c100 = _round2(ing.product.carbs);
        final cDish = ing.carbsInDish;
        final kcalDish = ing.blankKcalInDish;
        // Only calorie sums are accumulated here: totals for W/P/F/C below are
        // taken from the engine result, which rounds cells before summing.
        totalKcal += kcalDish;

        final kcalCell = isCrossMode
            ? '<c r="J$r" s="4"/>'
            : '<c r="J$r" s="10"><f>ROUND(E$r*4+G$r*9+I$r*4,1)</f><v>${kcalDish.toStringAsFixed(1)}</v></c>';

        sheetSb.write('''
    <row r="$r" ht="16" customHeight="1">
      <c r="A$r" s="0"><v>${i + 1}</v></c>
      <c r="B$r" s="5" t="inlineStr"><is><t>${_escape(ing.product.name)}</t></is></c>
      <c r="C$r" s="10"><v>${netW.toStringAsFixed(1)}</v></c>
      <c r="D$r" s="3"><v>${p100.toStringAsFixed(2)}</v></c>
      <c r="E$r" s="3"><f>ROUND(C$r*D$r/100,2)</f><v>${pDish.toStringAsFixed(2)}</v></c>
      <c r="F$r" s="3"><v>${f100.toStringAsFixed(2)}</v></c>
      <c r="G$r" s="3"><f>ROUND(C$r*F$r/100,2)</f><v>${fDish.toStringAsFixed(2)}</v></c>
      <c r="H$r" s="3"><v>${c100.toStringAsFixed(2)}</v></c>
      <c r="I$r" s="3"><f>ROUND(C$r*H$r/100,2)</f><v>${cDish.toStringAsFixed(2)}</v></c>
      $kcalCell
    </row>
''');
      } else {
        sheetSb.write('''
    <row r="$r" ht="16" customHeight="1">
      <c r="A$r" s="0"/>
      <c r="B$r" s="5"/>
      <c r="C$r" s="0"/>
      <c r="D$r" s="3"/>
      <c r="E$r" s="3"/>
      <c r="F$r" s="3"/>
      <c r="G$r" s="3"/>
      <c r="H$r" s="3"/>
      <c r="I$r" s="3"/>
      <c r="J$r" s="${isCrossMode ? 4 : 3}"/>
    </row>
''');
      }
      rowIdx++;
    }

    final lastDataRow = rowIdx - 1;
    totalW = calc.rawTotalWeight;
    totalP = calc.rawTotalProtein;
    totalF = calc.rawTotalFat;
    totalC = calc.rawTotalCarbs;
    // Новый расчёт (не legacy): потери берутся по группе КАЖДОГО продукта.
    // «Сохранность,%» — итоговая доля готовое/сырьё (в среднем, справочно),
    // «После тепловой обработки» — сумма построчных значений.
    final lossTable = calc.usesLossTable;
    // Вес готового блюда не указан: выход и «в 100 г» не определены —
    // печатаем прочерк, а не «0».
    final noYield = lossTable && !calc.hasYield;
    final retP = lossTable ? calc.retentionProtein : dish.retentionProtein;
    final retF = lossTable ? calc.retentionFat : dish.retentionFat;
    final retC = lossTable ? calc.retentionCarbs : dish.retentionCarbs;
    final pPct = _productRounded(retP, 100, 10);
    final pPctText = CalculationEngine.formatPercent(retP);
    final fPct = _productRounded(retF, 100, 10);
    final fPctText = CalculationEngine.formatPercent(retF);
    final cPct = _productRounded(retC, 100, 10);
    final cPctText = CalculationEngine.formatPercent(retC);
    final cookedP = calc.cookedProtein;
    final cookedF = calc.cookedFat;
    final cookedC = calc.cookedCarbs;
    final cookedKcal = calc.cookedKcal;

    // Строка 1: Итого (сумма по столбцам)
    final totalRow = rowIdx;
    final rawKcalCell = (!isCrossMode && calc.rawTotalKcal != null)
        ? '<c r="J$totalRow" s="9"><f>SUM(J$firstDataRow:J$lastDataRow)</f><v>${totalKcal.toStringAsFixed(1)}</v></c>'
        : '<c r="J$totalRow" s="4"/>';

    sheetSb.write('''
    <row r="$totalRow" ht="18" customHeight="1">
      <c r="A$totalRow" s="6" t="inlineStr"><is><r><rPr><b/></rPr><t xml:space="preserve">Итого </t></r><r><rPr><b val="0"/><i/></rPr><t>(сумма по столбцам)</t></r></is></c>
      <c r="B$totalRow" s="6"/>
      <c r="C$totalRow" s="11"><f>SUM(C$firstDataRow:C$lastDataRow)</f><v>${totalW.toStringAsFixed(1)}</v></c>
      <c r="D$totalRow" s="1"/>
      <c r="E$totalRow" s="8"><f>SUM(E$firstDataRow:E$lastDataRow)</f><v>${totalP.toStringAsFixed(2)}</v></c>
      <c r="F$totalRow" s="1"/>
      <c r="G$totalRow" s="8"><f>SUM(G$firstDataRow:G$lastDataRow)</f><v>${totalF.toStringAsFixed(2)}</v></c>
      <c r="H$totalRow" s="1"/>
      <c r="I$totalRow" s="8"><f>SUM(I$firstDataRow:I$lastDataRow)</f><v>${totalC.toStringAsFixed(2)}</v></c>
      $rawKcalCell
    </row>
''');
    merges.add('A$totalRow:B$totalRow');
    rowIdx++;

    // Строка 2: Сохранность,%
    final retRow = rowIdx;

    final retKcalCell = isCrossMode
        ? '<c r="J$retRow" s="4"/>'
        : '<c r="J$retRow" s="1" t="inlineStr"><is><t>—</t></is></c>';

    sheetSb.write('''
    <row r="$retRow" ht="18" customHeight="1">
      <c r="A$retRow" s="6" t="inlineStr"><is><t>Сохранность,%</t></is></c>
      <c r="B$retRow" s="6"/>
      <c r="C$retRow" s="1"/>
      <c r="D$retRow" s="1"><v>$pPct</v></c>
      <c r="E$retRow" s="1"/>
      <c r="F$retRow" s="1"><v>$fPct</v></c>
      <c r="G$retRow" s="1"/>
      <c r="H$retRow" s="1"><v>$cPct</v></c>
      <c r="I$retRow" s="1"/>
      $retKcalCell
    </row>
''');
    merges.addAll([
      'A$retRow:B$retRow',
      'D$retRow:E$retRow',
      'F$retRow:G$retRow',
      'H$retRow:I$retRow',
    ]);
    if (isCrossMode) {
      merges.add('J$firstDataRow:J$retRow');
    }
    rowIdx++;

    // Строка 3: После тепловой обработки
    final cookedRow = rowIdx;
    // legacy: одна тройка на сумму столбца. Новый расчёт: живая формула по
    // строкам продуктов — Σ ROUND(сырьё_i × (100 − потери_i) / 100; 2),
    // потери — из таблицы для группы и способа каждого продукта.
    String cookedFormula(String col, String legacyFormula) {
      if (!lossTable) return '<f>$legacyFormula</f>';
      if (calc.lines.isEmpty) return '';
      final terms = <String>[];
      for (var i = 0; i < calc.lines.length; i++) {
        final loss = calc.lines[i].loss;
        final pct = switch (col) {
          'E' => loss.protein,
          'G' => loss.fat,
          _ => loss.carbs,
        };
        terms.add(
            'ROUND($col${firstDataRow + i}*(100-${_pctLiteral(pct)})/100,2)');
      }
      final formula = 'ROUND(${terms.join('+')},2)';
      // Предел длины формулы Excel — 8192 символа: для очень длинных
      // рецептур остаётся только значение.
      return formula.length <= 8000 ? '<f>$formula</f>' : '';
    }

    final String yieldCell;
    if (noYield) {
      yieldCell =
          '<c r="C$cookedRow" s="11" t="inlineStr"><is><t>—</t></is></c>';
    } else if (lossTable || dish.hasCustomYield) {
      yieldCell =
          '<c r="C$cookedRow" s="11"><v>${calc.yieldGrams.toStringAsFixed(1)}</v></c>';
    } else {
      yieldCell =
          '<c r="C$cookedRow" s="11"><f>SUM(C$firstDataRow:C$lastDataRow)</f><v>${calc.yieldGrams.toStringAsFixed(1)}</v></c>';
    }
    sheetSb.write('''
    <row r="$cookedRow" ht="18" customHeight="1">
      <c r="A$cookedRow" s="6" t="inlineStr"><is><t>После тепловой обработки</t></is></c>
      <c r="B$cookedRow" s="6"/>
      $yieldCell
      <c r="D$cookedRow" s="8">${cookedFormula('E', 'ROUND(E$totalRow*D$retRow/100,2)')}<v>${cookedP.toStringAsFixed(2)}</v></c>
      <c r="E$cookedRow" s="1"/>
      <c r="F$cookedRow" s="8">${cookedFormula('G', 'ROUND(G$totalRow*F$retRow/100,2)')}<v>${cookedF.toStringAsFixed(2)}</v></c>
      <c r="G$cookedRow" s="1"/>
      <c r="H$cookedRow" s="8">${cookedFormula('I', 'ROUND(I$totalRow*H$retRow/100,2)')}<v>${cookedC.toStringAsFixed(2)}</v></c>
      <c r="I$cookedRow" s="1"/>
      <c r="J$cookedRow" s="9"><f>ROUND(D$cookedRow*4+F$cookedRow*9+H$cookedRow*4,1)</f><v>${cookedKcal.toStringAsFixed(1)}</v></c>
    </row>
''');
    merges.addAll([
      'A$cookedRow:B$cookedRow',
      'D$cookedRow:E$cookedRow',
      'F$cookedRow:G$cookedRow',
      'H$cookedRow:I$cookedRow',
    ]);
    rowIdx++;

    // Опциональная строка 4: В 100 г блюда
    if (dish.showPer100gRowInExport) {
      final per100Row = rowIdx;
      // Вес готового блюда не указан — «в 100 г» не определено: прочерк.
      String per100(String col, String style, String formula, String value) =>
          noYield
              ? '<c r="$col$per100Row" s="$style" t="inlineStr"><is><t>—</t></is></c>'
              : '<c r="$col$per100Row" s="$style"><f>$formula</f><v>$value</v></c>';
      sheetSb.write('''
    <row r="$per100Row" ht="18" customHeight="1">
      <c r="A$per100Row" s="6" t="inlineStr"><is><t>В 100 г блюда</t></is></c>
      <c r="B$per100Row" s="6"/>
      <c r="C$per100Row" s="1"><v>100</v></c>
      ${per100('D', '8', 'IF(C$cookedRow&gt;0,ROUND(D$cookedRow*100/C$cookedRow,2),0)', calc.per100gProtein.toStringAsFixed(2))}
      <c r="E$per100Row" s="1"/>
      ${per100('F', '8', 'IF(C$cookedRow&gt;0,ROUND(F$cookedRow*100/C$cookedRow,2),0)', calc.per100gFat.toStringAsFixed(2))}
      <c r="G$per100Row" s="1"/>
      ${per100('H', '8', 'IF(C$cookedRow&gt;0,ROUND(H$cookedRow*100/C$cookedRow,2),0)', calc.per100gCarbs.toStringAsFixed(2))}
      <c r="I$per100Row" s="1"/>
      ${per100('J', '9', 'IF(C$cookedRow&gt;0,ROUND(J$cookedRow*100/C$cookedRow,1),0)', calc.per100gKcal.toStringAsFixed(1))}
    </row>
''');
      merges.addAll([
        'A$per100Row:B$per100Row',
        'D$per100Row:E$per100Row',
        'F$per100Row:G$per100Row',
        'H$per100Row:I$per100Row',
      ]);
      rowIdx++;
    }

    rowIdx++; // Пустая строка перед формулами

    // 6-строчный блок формул под таблицей (чистые символические формулы бланка 1:1)
    // Новый расчёт: одного умножения суммы нет — потери применяются к
    // каждому продукту по его группе; процент — итоговая доля готовое/сырьё.
    String tableLine(String what, String pct, double raw, double cooked) =>
        dish.ingredients.isNotEmpty
            ? '= Σ $what продукта × (100 − потери группы) / 100 = '
                '${CalculationEngine.formatMacro(raw)} → '
                '${CalculationEngine.formatMacro(cooked)} г (в среднем $pct %)'
            : '= Σ $what продукта × (100 − потери группы) / 100';
    final formulaLines = lossTable
        ? [
            'Потери при тепловой обработке — по группам продуктов '
                '(${calc.process.label}):',
            tableLine('белков', pPctText, calc.rawTotalProtein, cookedP),
            tableLine('жиров', fPctText, calc.rawTotalFat, cookedF),
            tableLine('углеводов', cPctText, calc.rawTotalCarbs, cookedC),
            'Энергетическая ценность:',
            'Белки (после т.о) х 4 + Жиры (после т.о) х 9 + Углеводы (после т.о) х 4',
            kNotGostNotice,
          ]
        : [
            'Сохранность после тепловой обработки:',
            '= Сумма белков *$pPctText/100',
            '= Сумма жиров *$fPctText/100',
            '= Сумма углеводов *$cPctText/100',
            'Энергетическая ценность:',
            'Белки (после т.о) х 4 + Жиры (после т.о) х 9 + Углеводы (после т.о) х 4',
          ];

    for (var lineIndex = 0; lineIndex < formulaLines.length; lineIndex++) {
      final line = formulaLines[lineIndex];
      final nutrient = lossTable
          ? null
          : switch (lineIndex) {
        1 => ('белков', 'D'),
        2 => ('жиров', 'F'),
        3 => ('углеводов', 'H'),
        _ => null
      };
      final explanationCell = nutrient == null
          ? '<c r="B$rowIdx" s="7" t="inlineStr"><is><t>${_escape(line)}</t></is></c>'
          : '<c r="B$rowIdx" s="7" t="str"><f>${_escape('"= Сумма ${nutrient.$1} *"&${nutrient.$2}$retRow&"/100"')}</f><v>${_escape(line)}</v></c>';
      sheetSb.write('''
    <row r="$rowIdx" ht="16" customHeight="1">
      $explanationCell
    </row>
''');
      rowIdx++;
    }

    final zeroWasteIngs =
        dish.ingredients.where((i) => i.isGross && i.product.wastePct <= 0).toList();
    if (zeroWasteIngs.isNotEmpty) {
      final zeroWasteWarning =
          '* Предупреждение: для сырья брутто без указания отходов (${zeroWasteIngs.map((i) => '«${i.product.name}»').join(', ')}) принято 0 % отходов.';
      sheetSb.write('''
    <row r="$rowIdx" ht="16" customHeight="1">
      <c r="B$rowIdx" s="7" t="inlineStr"><is><t>${_escape(zeroWasteWarning)}</t></is></c>
    </row>
''');
      rowIdx++;
    }

    sheetSb.write('  </sheetData>\n');

    // Блок объединенных ячеек
    sheetSb.write('  <mergeCells count="${merges.length}">\n');
    for (final ref in merges) {
      sheetSb.write('    <mergeCell ref="$ref"/>\n');
    }
    sheetSb.write('  </mergeCells>\n');

    // Параметры печати (A4 альбомная, вписать на 1 страницу для стандартных бланков)
    final fitHeight = dish.ingredients.length <= 25 ? 1 : 0;
    sheetSb.write(
        '  <pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>\n');
    sheetSb.write(
      '  <pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="$fitHeight"/>\n',
    );
    sheetSb.write('</worksheet>');
    return sheetSb.toString();
  }

  static void _addFile(Archive archive, String filename, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(filename, bytes.length, bytes));
  }

  static String _escape(String text) =>
      OpenXmlText.escape(text, spreadsheet: true);
}
