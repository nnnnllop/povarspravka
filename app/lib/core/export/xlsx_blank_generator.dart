import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../calculation/calculation_engine.dart';
import '../calculation/calculation_math.dart';
import '../calculation/models/blank_mode.dart';
import '../calculation/models/dish.dart';

class XlsxBlankGenerator {
  static double _round2(double v) => CalculationMath.round2(v);
  static double _productRounded(double a, double b, int digits,
          {bool divideBy100 = false}) =>
      CalculationMath.productRounded(a, b, digits, divideBy100: divideBy100);

  /// Генерация бинарного файла .xlsx с объединением ячеек, диагональным крестом и живыми формулами Excel
  static Uint8List generate(Dish dish) {
    final calc = CalculationEngine.calculate(dish);
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    final archive = Archive();
    double totalW = 0, totalP = 0, totalF = 0, totalC = 0, totalKcal = 0;

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

    // 5. xl/styles.xml
    // cellXfs:
    // 0: обычная ячейка с рамкой по центру
    // 1: жирная ячейка с рамкой по центру и переносом слов
    // 2: заголовок бланка без рамки по центру (жирный 12pt)
    // 3: числовая ячейка с рамкой (0.00)
    // 4: ячейка с диагональным крестом (diagonalUp="1" diagonalDown="1")
    // 5: текстовая ячейка с рамкой по левому краю
    // 6: жирная текстовая ячейка с рамкой по левому краю
    // 7: формула под таблицей без рамки
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
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
</styleSheet>''';
    _addFile(archive, 'xl/styles.xml', stylesXml);

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
    <row r="$rowIdx" ht="18" customHeight="1">
      <c r="A$rowIdx" s="2" t="inlineStr"><is><t>${_escape(dish.title.trim())}</t></is></c>
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
        totalW += netW;
        totalP += pDish;
        totalF += fDish;
        totalC += cDish;
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
    final pPct = _productRounded(dish.retentionProtein, 100, 10);
    final pPctText = CalculationEngine.formatPercent(dish.retentionProtein);
    final fPct = _productRounded(dish.retentionFat, 100, 10);
    final fPctText = CalculationEngine.formatPercent(dish.retentionFat);
    final cPct = _productRounded(dish.retentionCarbs, 100, 10);
    final cPctText = CalculationEngine.formatPercent(dish.retentionCarbs);
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
      <c r="A$totalRow" s="6" t="inlineStr"><is><t>Итого (сумма по столбцам)</t></is></c>
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
    sheetSb.write('''
    <row r="$cookedRow" ht="18" customHeight="1">
      <c r="A$cookedRow" s="6" t="inlineStr"><is><t>После тепловой обработки</t></is></c>
      <c r="B$cookedRow" s="6"/>
      <c r="C$cookedRow" s="11">${dish.customYieldGrams == null ? '<f>SUM(C$firstDataRow:C$lastDataRow)</f>' : ''}<v>${calc.yieldGrams.toStringAsFixed(1)}</v></c>
      <c r="D$cookedRow" s="8"><f>ROUND(E$totalRow*D$retRow/100,2)</f><v>${cookedP.toStringAsFixed(2)}</v></c>
      <c r="E$cookedRow" s="1"/>
      <c r="F$cookedRow" s="8"><f>ROUND(G$totalRow*F$retRow/100,2)</f><v>${cookedF.toStringAsFixed(2)}</v></c>
      <c r="G$cookedRow" s="1"/>
      <c r="H$cookedRow" s="8"><f>ROUND(I$totalRow*H$retRow/100,2)</f><v>${cookedC.toStringAsFixed(2)}</v></c>
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
      sheetSb.write('''
    <row r="$per100Row" ht="18" customHeight="1">
      <c r="A$per100Row" s="6" t="inlineStr"><is><t>В 100 г блюда</t></is></c>
      <c r="B$per100Row" s="6"/>
      <c r="C$per100Row" s="1"><v>100</v></c>
      <c r="D$per100Row" s="8"><f>IF(C$cookedRow&gt;0,ROUND(D$cookedRow*100/C$cookedRow,2),0)</f><v>${calc.per100gProtein.toStringAsFixed(2)}</v></c>
      <c r="E$per100Row" s="1"/>
      <c r="F$per100Row" s="8"><f>IF(C$cookedRow&gt;0,ROUND(F$cookedRow*100/C$cookedRow,2),0)</f><v>${calc.per100gFat.toStringAsFixed(2)}</v></c>
      <c r="G$per100Row" s="1"/>
      <c r="H$per100Row" s="8"><f>IF(C$cookedRow&gt;0,ROUND(H$cookedRow*100/C$cookedRow,2),0)</f><v>${calc.per100gCarbs.toStringAsFixed(2)}</v></c>
      <c r="I$per100Row" s="1"/>
      <c r="J$per100Row" s="9"><f>IF(C$cookedRow&gt;0,ROUND(J$cookedRow*100/C$cookedRow,1),0)</f><v>${calc.per100gKcal.toStringAsFixed(1)}</v></c>
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
    final formulaLines = [
      'Сохранность после тепловой обработки:',
      '= Сумма белков *$pPctText /100',
      '= Сумма жиров *$fPctText/100',
      '= Сумма углеводов *$cPctText/100',
      'Энергетическая ценность:',
      'Белки (после т.о) х 4 + Жиры (после т.о) х 9 + Углеводы (после т.о) х 4',
    ];

    for (final line in formulaLines) {
      sheetSb.write('''
    <row r="$rowIdx" ht="16" customHeight="1">
      <c r="B$rowIdx" s="7" t="inlineStr"><is><t>${_escape(line)}</t></is></c>
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

    _addFile(archive, 'xl/worksheets/sheet1.xml', sheetSb.toString());

    final zipEncoder = ZipEncoder();
    final bytes = zipEncoder.encode(archive);
    return Uint8List.fromList(bytes ?? []);
  }

  static void _addFile(Archive archive, String filename, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(filename, bytes.length, bytes));
  }

  static String _escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
