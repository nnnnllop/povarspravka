import 'openxml_text.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../calculation/calculation_engine.dart';
import '../calculation/models/blank_mode.dart';
import '../calculation/models/dish.dart';

class DocxBlankGenerator {
  /// Генерация бинарного файла .docx 1:1 с бумажным бланком
  static Uint8List generate(Dish dish) {
    final calc = CalculationEngine.calculate(dish);
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml =
        '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
    _addFile(archive, '[Content_Types].xml', contentTypesXml);

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', relsXml);

    // 3. word/document.xml
    final docSb = StringBuffer();
    docSb.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"
            xmlns:v="urn:schemas-microsoft-com:vml"
            xmlns:o="urn:schemas-microsoft-com:office:office"
            mc:Ignorable="wps">
  <w:body>
''');

    // Постоянный заголовок бланка
    docSb.write('''
    <w:p>
      <w:pPr><w:spacing w:before="0" w:after="60"/><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="22"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
        <w:t>Расчет энергетической и пищевой ценности блюда</w:t>
      </w:r>
    </w:p>
''');

    // Название блюда (подзаголовок, если включено)
    if (dish.showTitleInExport && dish.title.trim().isNotEmpty) {
      docSb.write('''
    <w:p>
      <w:pPr><w:spacing w:before="0" w:after="60"/><w:jc w:val="center"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="20"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
        <w:t>${_escape(dish.title.trim())}</w:t>
      </w:r>
    </w:p>
''');
    }

    // Таблица бланка
    docSb.write('''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="12450" w:type="dxa"/>
        <w:tblLayout w:type="fixed"/>
        <w:jc w:val="center"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="450"/>
        <w:gridCol w:w="3350"/>
        <w:gridCol w:w="1350"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="950"/>
        <w:gridCol w:w="1600"/>
      </w:tblGrid>
''');

    // Шапка уровень 1 (двухуровневая с объединением ячеек)
    docSb.write('''
      <w:tr>
        <w:trPr><w:tblHeader/><w:trHeight w:val="300" w:hRule="exact"/></w:trPr>
        ${_cellXml('№', bold: true, vMerge: 'restart')}
        ${_cellXml('Наименование сырья', bold: true, vMerge: 'restart')}
        ${_cellXml('Количество, г', bold: true, vMerge: 'restart')}
        ${_cellXml('Белки, г', bold: true, gridSpan: 2)}
        ${_cellXml('Жиры, г', bold: true, gridSpan: 2)}
        ${_cellXml('Углеводы, г', bold: true, gridSpan: 2)}
        ${_cellXml('энергетическая ценность, ккал', bold: true, vMerge: 'restart')}
      </w:tr>
''');

    // Шапка уровень 2
    docSb.write('''
      <w:tr>
        <w:trPr><w:tblHeader/><w:trHeight w:val="240" w:hRule="exact"/></w:trPr>
        ${_cellXml('', bold: true, vMerge: 'continue')}
        ${_cellXml('', bold: true, vMerge: 'continue')}
        ${_cellXml('', bold: true, vMerge: 'continue')}
        ${_cellXml('В 100 г', bold: true)}
        ${_cellXml('В блюде', bold: true)}
        ${_cellXml('В 100 г', bold: true)}
        ${_cellXml('В блюде', bold: true)}
        ${_cellXml('В 100 г', bold: true)}
        ${_cellXml('В блюде', bold: true)}
        ${_cellXml('', bold: true, vMerge: 'continue')}
      </w:tr>
''');

    // Строки сырья (минимум 18 строк; пустые строки НЕ нумеруются)
    const minRows = 18;
    final totalRows =
        dish.ingredients.length < minRows ? minRows : dish.ingredients.length;

    for (int i = 0; i < totalRows; i++) {
      final crossVMerge =
          isCrossMode ? (i == 0 ? 'restart' : 'continue') : null;
      final crossShape =
          (isCrossMode && i == 0) ? _crossShapeXml(totalRows) : null;
      if (i < dish.ingredients.length) {
        final ing = dish.ingredients[i];
        final kcalText = isCrossMode
            ? ''
            : CalculationEngine.formatKcal(ing.blankKcalInDish);

        docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_cellXml('${i + 1}', align: 'center')}
        ${_cellXml(ing.product.name, align: 'left')}
        ${_cellXml(CalculationEngine.formatGrams(ing.netGramsRounded), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.product.protein), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.proteinInDish), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.product.fat), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.fatInDish), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.product.carbs), align: 'center')}
        ${_cellXml(CalculationEngine.formatMacro(ing.carbsInDish), align: 'center')}
        ${_cellXml(kcalText, align: 'center', vMerge: crossVMerge, diagonalCross: isCrossMode, crossShapeXml: crossShape)}
      </w:tr>
''');
      } else {
        docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('')}
        ${_cellXml('', vMerge: crossVMerge, diagonalCross: isCrossMode, crossShapeXml: crossShape)}
      </w:tr>
''');
      }
    }

    // Итого (сумма по столбцам)
    final rawKcalStr = (!isCrossMode && calc.rawTotalKcal != null)
        ? CalculationEngine.formatKcal(calc.rawTotalKcal!)
        : '';
    docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_totalLabelCellXml()}
        ${_cellXml(CalculationEngine.formatGrams(calc.rawTotalWeight), bold: true)}
        ${_cellXml('')}
        ${_cellXml(CalculationEngine.formatMacro(calc.rawTotalProtein), bold: true)}
        ${_cellXml('')}
        ${_cellXml(CalculationEngine.formatMacro(calc.rawTotalFat), bold: true)}
        ${_cellXml('')}
        ${_cellXml(CalculationEngine.formatMacro(calc.rawTotalCarbs), bold: true)}
        ${_cellXml(rawKcalStr, bold: true, vMerge: isCrossMode ? 'continue' : null, diagonalCross: isCrossMode)}
      </w:tr>
''');

    // Сохранность,%
    final pPct = CalculationEngine.formatPercent(calc.retentionProtein);
    final fPct = CalculationEngine.formatPercent(calc.retentionFat);
    final cPct = CalculationEngine.formatPercent(calc.retentionCarbs);

    docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_cellXml('Сохранность,%', bold: true, align: 'left', gridSpan: 2)}
        ${_cellXml('')}
        ${_cellXml('$pPct', bold: true, gridSpan: 2)}
        ${_cellXml('$fPct', bold: true, gridSpan: 2)}
        ${_cellXml('$cPct', bold: true, gridSpan: 2)}
        ${_cellXml(isCrossMode ? '' : '—', bold: true, vMerge: isCrossMode ? 'continue' : null, diagonalCross: isCrossMode)}
      </w:tr>
''');

    // После тепловой обработки
    docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_cellXml('После тепловой обработки', bold: true, align: 'left', gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatGrams(calc.yieldGrams), bold: true)}
        ${_cellXml(CalculationEngine.formatMacro(calc.cookedProtein), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatMacro(calc.cookedFat), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatMacro(calc.cookedCarbs), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatKcal(calc.cookedKcal), bold: true)}
      </w:tr>
''');

    // Опциональная строка 4: В 100 г блюда
    if (dish.showPer100gRowInExport) {
      docSb.write('''
      <w:tr>
        <w:trPr><w:trHeight w:val="260" w:hRule="exact"/></w:trPr>
        ${_cellXml('В 100 г блюда', bold: true, align: 'left', gridSpan: 2)}
        ${_cellXml('100', bold: true)}
        ${_cellXml(CalculationEngine.formatMacro(calc.per100gProtein), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatMacro(calc.per100gFat), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatMacro(calc.per100gCarbs), bold: true, gridSpan: 2)}
        ${_cellXml(CalculationEngine.formatKcal(calc.per100gKcal), bold: true)}
      </w:tr>
''');
    }

    docSb.write('    </w:tbl>\n');

    // Блок формул под таблицей (6 строк точь-в-точь как на фото)
    final hasItems = dish.ingredients.isNotEmpty;
    final pLine = hasItems
        ? '= Сумма белков *$pPct /100 = ${CalculationEngine.formatMacro(calc.rawTotalProtein)} * $pPct / 100 = ${CalculationEngine.formatMacro(calc.cookedProtein)} г'
        : '= Сумма белков *$pPct /100';
    final fLine = hasItems
        ? '= Сумма жиров *$fPct/100 = ${CalculationEngine.formatMacro(calc.rawTotalFat)} * $fPct / 100 = ${CalculationEngine.formatMacro(calc.cookedFat)} г'
        : '= Сумма жиров *$fPct/100';
    final cLine = hasItems
        ? '= Сумма углеводов *$cPct/100 = ${CalculationEngine.formatMacro(calc.rawTotalCarbs)} * $cPct / 100 = ${CalculationEngine.formatMacro(calc.cookedCarbs)} г'
        : '= Сумма углеводов *$cPct/100';
    final kcalLine = hasItems
        ? 'Белки (после т.о) х 4 + Жиры (после т.о) х 9 + Углеводы (после т.о) х 4 = ${CalculationEngine.formatMacro(calc.cookedProtein)} х 4 + ${CalculationEngine.formatMacro(calc.cookedFat)} х 9 + ${CalculationEngine.formatMacro(calc.cookedCarbs)} х 4 = ${CalculationEngine.formatKcal(calc.cookedKcal)} ккал'
        : 'Белки (после т.о) х 4 + Жиры (после т.о) х 9 + Углеводы (после т.о) х 4';

    final zeroWasteIngs =
        dish.ingredients.where((i) => i.isGross && i.product.wastePct <= 0).toList();
    final zeroWasteWarning = zeroWasteIngs.isNotEmpty
        ? '* Предупреждение: для сырья брутто без указания отходов (${zeroWasteIngs.map((i) => '«${i.product.name}»').join(', ')}) принято 0 % отходов.'
        : null;

    docSb.write('''
    ${_formulaParagraph('Сохранность после тепловой обработки:', bold: true, spaceBefore: 40)}
    ${_formulaParagraph(pLine)}
    ${_formulaParagraph(fLine)}
    ${_formulaParagraph(cLine)}
    ${_formulaParagraph('Энергетическая ценность:', bold: true, spaceBefore: 30)}
    ${_formulaParagraph(kcalLine)}
    ${zeroWasteWarning != null ? _formulaParagraph(zeroWasteWarning, spaceBefore: 20) : ''}
    <w:sectPr>
      <w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>
      <w:pgMar w:top="567" w:right="567" w:bottom="567" w:left="567"/>
    </w:sectPr>
  </w:body>
</w:document>
''');

    _addFile(archive, 'word/document.xml', docSb.toString());

    final zipEncoder = ZipEncoder();
    final bytes = zipEncoder.encode(archive);
    return Uint8List.fromList(bytes ?? []);
  }

  static String _totalLabelCellXml() {
    return '''
      <w:tc>
        <w:tcPr><w:gridSpan w:val="2"/><w:vAlign w:val="center"/></w:tcPr>
        <w:p>
          <w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="left"/></w:pPr>
          <w:r>
            <w:rPr><w:b/><w:sz w:val="18"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
            <w:t xml:space="preserve">Итого </w:t>
          </w:r>
          <w:r>
            <w:rPr><w:i/><w:sz w:val="18"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
            <w:t>(сумма по столбцам)</w:t>
          </w:r>
        </w:p>
      </w:tc>''';
  }

  static String _crossShapeXml(int totalRows) {
    // Высота охватывает totalRows строк сырья + строку "Итого" + строку "Сохранность,%"
    final mergedRows = totalRows + 2;
    const rowHeightPt = 13.0;
    final heightPt = mergedRows * rowHeightPt;
    final heightEmu = (heightPt * 12700).round();
    const widthPt = 80.0;
    final widthEmu = (widthPt * 12700).round();

    return '''
        <w:p>
          <w:pPr>
            <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
            <w:jc w:val="center"/>
          </w:pPr>
          <w:r>
            <mc:AlternateContent>
              <mc:Choice Requires="wps">
                <w:drawing>
                  <wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251659264" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">
                    <wp:simplePos x="0" y="0"/>
                    <wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset></wp:positionH>
                    <wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV>
                    <wp:extent cx="$widthEmu" cy="$heightEmu"/>
                    <wp:effectExtent l="0" t="0" r="0" b="0"/>
                    <wp:wrapNone/>
                    <wp:docPr id="1" name="PhotoCross"/>
                    <wp:cNvGraphicFramePr/>
                    <a:graphic>
                      <a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">
                        <wps:wsp>
                          <wps:cNvCnPr/>
                          <wps:spPr>
                            <a:xfrm><a:off x="0" y="0"/><a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>
                            <a:custGeom>
                              <a:avLst/>
                              <a:gdLst/>
                              <a:ahLst/>
                              <a:cxnLst/>
                              <a:pathLst>
                                <a:path w="1000" h="1000">
                                  <a:moveTo><a:pt x="0" y="0"/></a:moveTo>
                                  <a:lnTo><a:pt x="1000" y="1000"/></a:lnTo>
                                  <a:moveTo><a:pt x="1000" y="0"/></a:moveTo>
                                  <a:lnTo><a:pt x="0" y="1000"/></a:lnTo>
                                </a:path>
                              </a:pathLst>
                            </a:custGeom>
                            <a:ln w="9525"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>
                          </wps:spPr>
                          <wps:bodyPr/>
                        </wps:wsp>
                      </a:graphicData>
                    </a:graphic>
                  </wp:anchor>
                </w:drawing>
              </mc:Choice>
              <mc:Fallback>
                <w:pict>
                  <v:shape style="position:absolute;left:0;top:0;width:${widthPt}pt;height:${heightPt}pt"
                           coordsize="1000,1000"
                           path="m 0,0 l 1000,1000 m 1000,0 l 0,1000 e"
                           strokecolor="#000000" strokeweight="0.75pt" filled="f"/>
                </w:pict>
              </mc:Fallback>
            </mc:AlternateContent>
          </w:r>
        </w:p>''';
  }

  static String _cellXml(
    String text, {
    bool bold = false,
    String align = 'center',
    int gridSpan = 1,
    String? vMerge,
    bool diagonalCross = false,
    String? crossShapeXml,
  }) {
    final bTag = bold ? '<w:b/>' : '';
    final jcTag = '<w:jc w:val="$align"/>';

    final tcPrSb = StringBuffer();
    if (gridSpan > 1 || vMerge != null || diagonalCross) {
      tcPrSb.write('<w:tcPr>');
      if (gridSpan > 1) {
        tcPrSb.write('<w:gridSpan w:val="$gridSpan"/>');
      }
      if (vMerge != null) {
        if (vMerge == 'restart') {
          tcPrSb.write('<w:vMerge w:val="restart"/>');
        } else {
          tcPrSb.write('<w:vMerge/>');
        }
      }
      if (diagonalCross) {
        tcPrSb.write(
          '<w:tcBorders>'
          '<w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
          '<w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
          '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
          '<w:right w:val="single" w:sz="4" w:space="0" w:color="000000"/>'
          '<w:tl2br w:val="none"/>'
          '<w:tr2bl w:val="none"/>'
          '</w:tcBorders>'
          '<w:tcMar>'
          '<w:top w:w="0" w:type="dxa"/>'
          '<w:left w:w="0" w:type="dxa"/>'
          '<w:bottom w:w="0" w:type="dxa"/>'
          '<w:right w:w="0" w:type="dxa"/>'
          '</w:tcMar>',
        );
      }
      if (crossShapeXml != null) {
        tcPrSb.write('<w:vAlign w:val="top"/>');
      } else {
        tcPrSb.write('<w:vAlign w:val="center"/>');
      }
      tcPrSb.write('</w:tcPr>');
    }

    final pXml = crossShapeXml ??
        '''
        <w:p>
          <w:pPr>
            <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
            $jcTag
          </w:pPr>
          <w:r>
            <w:rPr>$bTag<w:sz w:val="18"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
            <w:t xml:space="preserve">${_escape(text)}</w:t>
          </w:r>
        </w:p>''';

    return '''
      <w:tc>
        ${tcPrSb.toString()}
        $pXml
      </w:tc>''';
  }

  static String _formulaParagraph(String text,
      {bool bold = false, int spaceBefore = 0}) {
    final bTag = bold ? '<w:b/>' : '';
    return '''
    <w:p>
      <w:pPr><w:spacing w:before="$spaceBefore" w:after="0"/><w:ind w:left="1440"/></w:pPr>
      <w:r>
        <w:rPr>$bTag<w:sz w:val="18"/><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/></w:rPr>
        <w:t xml:space="preserve">${_escape(text)}</w:t>
      </w:r>
    </w:p>''';
  }

  static void _addFile(Archive archive, String filename, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(filename, bytes.length, bytes));
  }

  static String _escape(String text) => OpenXmlText.escape(text);
}
