import 'package:flutter/services.dart';
import 'unicode_pdf_font.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../calculation/calculation_engine.dart';
import '../calculation/models/blank_mode.dart';
import '../calculation/models/calculation_result.dart';
import '../calculation/models/dish.dart';

class PdfBlankGenerator {
  // Фиксированные ширины 10 столбцов для точного выравнивания объединенных ячеек (сумма = 780 pt)
  static const double _w0 = 26.0; // №
  static const double _w1 = 234.0; // Наименование сырья
  static const double _w2 = 64.0; // Количество, г
  static const double _w3 = 58.0; // Белки В 100 г
  static const double _w4 = 58.0; // Белки В блюде
  static const double _w5 = 58.0; // Жиры В 100 г
  static const double _w6 = 58.0; // Жиры В блюде
  static const double _w7 = 58.0; // Углеводы В 100 г
  static const double _w8 = 58.0; // Углеводы В блюде
  static const double _w9 = 108.0; // Энергетическая ценность, ккал

  static const double _w01 = _w0 + _w1;
  static const double _w34 = _w3 + _w4;
  static const double _w56 = _w5 + _w6;
  static const double _w78 = _w7 + _w8;
  static const double _wLeft9 =
      _w0 + _w1 + _w2 + _w3 + _w4 + _w5 + _w6 + _w7 + _w8;
  static const double _totalWidth = _wLeft9 + _w9;

  /// Генерация бинарного содержимого PDF бланка 1:1 с бумажным оригиналом
  static Future<Uint8List> generate(Dish dish) async {
    final pdf = pw.Document();

    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final fontData = await rootBundle.load('assets/fonts/arial.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/arialbd.ttf');
      fontRegular = pw.Font.ttf(fontData);
      fontBold = pw.Font.ttf(fontBoldData);
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final emojiFont = UnicodePdfFont(
        await rootBundle.load('assets/fonts/NotoEmoji-Regular.ttf'));
    final calcResult = CalculationEngine.calculate(dish);

    const rowsPerPage = 18;
    final pageCount = dish.ingredients.isEmpty
        ? 1
        : (dish.ingredients.length + rowsPerPage - 1) ~/ rowsPerPage;
    for (var page = 0; page < pageCount; page++) {
      final start = page * rowsPerPage;
      final end = (start + rowsPerPage < dish.ingredients.length)
          ? start + rowsPerPage
          : dish.ingredients.length;
      final isFinal = page == pageCount - 1;
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        theme: pw.ThemeData.withFont(
            base: fontRegular, bold: fontBold, fontFallback: [emojiFont]),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildTitleBlock(dish, fontRegular, fontBold),
            pw.SizedBox(height: 6),
            _buildBlankTable(dish, calcResult, fontRegular, fontBold,
                start: start,
                end: end,
                isFinal: isFinal,
                padTo18: pageCount == 1),
            pw.SizedBox(height: 10),
            if (isFinal)
              _buildFormulaBlock(dish, calcResult, fontRegular, fontBold)
            else
              pw.Text('Продолжение на следующей странице...',
                  style: pw.TextStyle(font: fontRegular, fontSize: 9)),
          ],
        ),
      ));
    }

    return pdf.save();
  }

  static String _formatPercent(double retention) =>
      CalculationEngine.formatPercent(retention);

  static pw.Widget _buildTitleBlock(
    Dish dish,
    pw.Font fontRegular,
    pw.Font fontBold,
  ) {
    return pw.Container(
      width: _totalWidth,
      alignment: pw.Alignment.center,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'Расчет энергетической и пищевой ценности блюда',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (dish.showTitleInExport && dish.title.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            // User newlines must not consume the fixed table's page budget.
            // Wrap the complete title and scale it down within a bounded area.
            pw.Container(
              constraints: const pw.BoxConstraints(maxHeight: 48),
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.SizedBox(
                  width: _totalWidth,
                  child: pw.Text(
                    dish.title.trim().replaceAll(RegExp(r'\s+'), ' '),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildBlankTable(
    Dish dish,
    CalculationResult calc,
    pw.Font fontRegular,
    pw.Font fontBold, {
    required int start,
    required int end,
    required bool isFinal,
    required bool padTo18,
  }) {
    final totalRows = padTo18 ? 18 : end - start;
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    const double rowH = 15.5;

    final pPct = _formatPercent(calc.retentionProtein);
    final fPct = _formatPercent(calc.retentionFat);
    final cPct = _formatPercent(calc.retentionCarbs);

    // Построение строк 1..9 для области сырья + Итого + Сохранность,%
    final leftNineRows = <pw.Widget>[];

    for (int i = 0; i < totalRows; i++) {
      if (start + i < end) {
        final ing = dish.ingredients[start + i];
        leftNineRows.add(
          pw.Row(
            children: [
              _cell('${start + i + 1}', _w0, rowH, fontRegular,
                  align: pw.Alignment.center),
              _cell(ing.product.name, _w1, rowH, fontRegular,
                  align: pw.Alignment.centerLeft),
              _cell(CalculationEngine.formatGrams(ing.netGramsRounded), _w2,
                  rowH, fontRegular),
              _cell(CalculationEngine.formatMacro(ing.product.protein), _w3,
                  rowH, fontRegular),
              _cell(CalculationEngine.formatMacro(ing.proteinInDish), _w4, rowH,
                  fontRegular),
              _cell(CalculationEngine.formatMacro(ing.product.fat), _w5, rowH,
                  fontRegular),
              _cell(CalculationEngine.formatMacro(ing.fatInDish), _w6, rowH,
                  fontRegular),
              _cell(CalculationEngine.formatMacro(ing.product.carbs), _w7, rowH,
                  fontRegular),
              _cell(CalculationEngine.formatMacro(ing.carbsInDish), _w8, rowH,
                  fontRegular),
            ],
          ),
        );
      } else {
        // Пустые строки бланка НЕ нумеруются
        leftNineRows.add(
          pw.Row(
            children: [
              _cell('', _w0, rowH, fontRegular),
              _cell('', _w1, rowH, fontRegular),
              _cell('', _w2, rowH, fontRegular),
              _cell('', _w3, rowH, fontRegular),
              _cell('', _w4, rowH, fontRegular),
              _cell('', _w5, rowH, fontRegular),
              _cell('', _w6, rowH, fontRegular),
              _cell('', _w7, rowH, fontRegular),
              _cell('', _w8, rowH, fontRegular),
            ],
          ),
        );
      }
    }

    if (isFinal) {
      // Итого (сумма по столбцам) — колонки 1..9
      leftNineRows.add(
        pw.Row(
          children: [
            _mergedTotalLabelCell(_w01, rowH, fontRegular, fontBold),
            _cell(CalculationEngine.formatGrams(calc.rawTotalWeight), _w2, rowH,
                fontBold,
                bold: true),
            _cell('', _w3, rowH, fontRegular),
            _cell(CalculationEngine.formatMacro(calc.rawTotalProtein), _w4,
                rowH, fontBold,
                bold: true),
            _cell('', _w5, rowH, fontRegular),
            _cell(CalculationEngine.formatMacro(calc.rawTotalFat), _w6, rowH,
                fontBold,
                bold: true),
            _cell('', _w7, rowH, fontRegular),
            _cell(CalculationEngine.formatMacro(calc.rawTotalCarbs), _w8, rowH,
                fontBold,
                bold: true),
          ],
        ),
      );

      // Сохранность,% — колонки 1..9
      leftNineRows.add(
        pw.Row(
          children: [
            _cell('Сохранность,%', _w01, rowH, fontBold,
                bold: true, align: pw.Alignment.centerLeft),
            _cell('', _w2, rowH, fontRegular),
            _cell('$pPct', _w34, rowH, fontBold, bold: true),
            _cell('$fPct', _w56, rowH, fontBold, bold: true),
            _cell('$cPct', _w78, rowH, fontBold, bold: true),
          ],
        ),
      );
    }

    // Правая колонка 10 для области сырья + Итого + Сохранность,%
    pw.Widget col10MiddleWidget;
    if (isCrossMode) {
      final crossHeight = (totalRows + (isFinal ? 2 : 0)) * rowH;
      col10MiddleWidget = pw.Container(
        width: _w9,
        height: crossHeight,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.5),
        ),
        child: pw.CustomPaint(
          size: PdfPoint(_w9, crossHeight),
          painter: (PdfGraphics canvas, PdfPoint size) {
            canvas.setColor(PdfColors.black);
            canvas.setLineWidth(0.6);
            // Две пересекающиеся диагонали X из угла в угол
            canvas.drawLine(0, 0, size.x, size.y);
            canvas.drawLine(0, size.y, size.x, 0);
            canvas.strokePath();
          },
        ),
      );
    } else {
      final col10Cells = <pw.Widget>[];
      for (int i = 0; i < totalRows; i++) {
        if (start + i < end) {
          final ing = dish.ingredients[start + i];
          col10Cells.add(
            _cell(CalculationEngine.formatKcal(ing.blankKcalInDish), _w9, rowH,
                fontRegular),
          );
        } else {
          col10Cells.add(_cell('', _w9, rowH, fontRegular));
        }
      }
      if (isFinal) {
        // Итого ккал
        col10Cells.add(
          _cell(
            calc.rawTotalKcal != null
                ? CalculationEngine.formatKcal(calc.rawTotalKcal!)
                : '',
            _w9,
            rowH,
            fontBold,
            bold: true,
          ),
        );
        // Сохранность,% ккал
        col10Cells.add(_cell('—', _w9, rowH, fontRegular));
      }
      col10MiddleWidget = pw.Column(children: col10Cells);
    }

    return pw.Container(
      width: _totalWidth,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Двухуровневая шапка таблицы
          _buildTwoLevelHeader(fontBold),

          // Средняя часть: строки сырья + Итого + Сохранность,%
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: _wLeft9,
                child: pw.Column(children: leftNineRows),
              ),
              col10MiddleWidget,
            ],
          ),

          // Строка 3: После тепловой обработки
          if (isFinal)
            pw.Row(
              children: [
                _cell('После тепловой обработки', _w01, rowH + 2, fontBold,
                    bold: true, align: pw.Alignment.centerLeft),
                _cell(CalculationEngine.formatGrams(calc.yieldGrams), _w2,
                    rowH + 2, fontRegular),
                _cell(CalculationEngine.formatMacro(calc.cookedProtein), _w34,
                    rowH + 2, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatMacro(calc.cookedFat), _w56,
                    rowH + 2, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatMacro(calc.cookedCarbs), _w78,
                    rowH + 2, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatKcal(calc.cookedKcal), _w9,
                    rowH + 2, fontBold,
                    bold: true),
              ],
            ),

          // Опциональная строка 4: В 100 г блюда
          if (isFinal && dish.showPer100gRowInExport)
            pw.Row(
              children: [
                _cell('В 100 г блюда', _w01, rowH, fontBold,
                    bold: true, align: pw.Alignment.centerLeft),
                _cell('100', _w2, rowH, fontBold, bold: true),
                _cell(CalculationEngine.formatMacro(calc.per100gProtein), _w34,
                    rowH, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatMacro(calc.per100gFat), _w56,
                    rowH, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatMacro(calc.per100gCarbs), _w78,
                    rowH, fontBold,
                    bold: true),
                _cell(CalculationEngine.formatKcal(calc.per100gKcal), _w9, rowH,
                    fontBold,
                    bold: true),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildTwoLevelHeader(pw.Font fontBold) {
    const double h1 = 18.0;
    const double h2 = 22.0;
    const double hTotal = h1 + h2;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _headerBox('№', _w0, hTotal, fontBold),
        _headerBox('Наименование\nсырья', _w1, hTotal, fontBold),
        _headerBox('Количество,\nг', _w2, hTotal, fontBold),
        // Белки, г
        pw.Column(
          children: [
            _headerBox('Белки, г', _w34, h1, fontBold),
            pw.Row(
              children: [
                _headerBox('В 100\nг', _w3, h2, fontBold, fontSize: 7.5),
                _headerBox('В\nблюде', _w4, h2, fontBold, fontSize: 7.5),
              ],
            ),
          ],
        ),
        // Жиры, г
        pw.Column(
          children: [
            _headerBox('Жиры, г', _w56, h1, fontBold),
            pw.Row(
              children: [
                _headerBox('В 100\nг', _w5, h2, fontBold, fontSize: 7.5),
                _headerBox('В\nблюде', _w6, h2, fontBold, fontSize: 7.5),
              ],
            ),
          ],
        ),
        // Углеводы, г
        pw.Column(
          children: [
            _headerBox('Углеводы, г', _w78, h1, fontBold),
            pw.Row(
              children: [
                _headerBox('В 100\nг', _w7, h2, fontBold, fontSize: 7.5),
                _headerBox('В\nблюде', _w8, h2, fontBold, fontSize: 7.5),
              ],
            ),
          ],
        ),
        // энергетическая ценность, ккал
        _headerBox('энергетическая\nценность,\nккал', _w9, hTotal, fontBold),
      ],
    );
  }

  static pw.Widget _headerBox(
    String text,
    double width,
    double height,
    pw.Font fontBold, {
    double fontSize = 8.0,
  }) {
    return pw.Container(
      width: width,
      height: height,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _mergedTotalLabelCell(
    double width,
    double height,
    pw.Font fontRegular,
    pw.Font fontBold,
  ) {
    return pw.Container(
      width: width,
      height: height,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: 'Итого ',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 8.0,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: '(сумма по столбцам)',
              style: pw.TextStyle(
                font: fontRegular,
                fontSize: 7.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cell(
    String text,
    double width,
    double height,
    pw.Font font, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
  }) {
    return pw.Container(
      width: width,
      height: height,
      alignment: align,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Text(
        text,
        maxLines: 1,
        style: pw.TextStyle(
          font: font,
          fontSize: 7.8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildFormulaBlock(
    Dish dish,
    CalculationResult calc,
    pw.Font fontRegular,
    pw.Font fontBold,
  ) {
    final pPct = _formatPercent(calc.retentionProtein);
    final fPct = _formatPercent(calc.retentionFat);
    final cPct = _formatPercent(calc.retentionCarbs);
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

    return pw.Container(
      width: _totalWidth,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.only(left: 80),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Сохранность после тепловой обработки:',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 9.0,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(pLine, style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
          pw.SizedBox(height: 1.5),
          pw.Text(fLine, style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
          pw.SizedBox(height: 1.5),
          pw.Text(cLine, style: pw.TextStyle(font: fontRegular, fontSize: 8.5)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Энергетическая ценность:',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 9.0,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            kcalLine,
            style: pw.TextStyle(font: fontRegular, fontSize: 8.5),
          ),
          if (zeroWasteWarning != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              zeroWasteWarning,
              style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: PdfColors.orange900),
            ),
          ],
        ],
      ),
    );
  }
}
