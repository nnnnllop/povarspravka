import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/export/export_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';

class BlankPreviewScreen extends ConsumerWidget {
  const BlankPreviewScreen({super.key});

  // Фиксированные ширины колонок для 1:1 совпадения объединенных ячеек
  static const double _w0 = 32.0; // №
  static const double _w1 = 230.0; // Наименование сырья
  static const double _w2 = 72.0; // Количество, г
  static const double _w3 = 62.0; // Белки В 100 г
  static const double _w4 = 62.0; // Белки В блюде
  static const double _w5 = 62.0; // Жиры В 100 г
  static const double _w6 = 62.0; // Жиры В блюде
  static const double _w7 = 62.0; // Углеводы В 100 г
  static const double _w8 = 62.0; // Углеводы В блюде
  static const double _w9 = 114.0; // Энергетическая ценность, ккал

  static const double _w01 = _w0 + _w1;
  static const double _w34 = _w3 + _w4;
  static const double _w56 = _w5 + _w6;
  static const double _w78 = _w7 + _w8;
  static const double _wLeft9 =
      _w0 + _w1 + _w2 + _w3 + _w4 + _w5 + _w6 + _w7 + _w8;
  static const double _totalWidth = _wLeft9 + _w9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Бланк расчета КБЖУ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Печать бланка',
            onPressed: () async {
              try {
                await ExportService.printPdf(dish);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка при печати: $e')),
                  );
                }
              }
            },
          ),
          PopupMenuButton<ExportType>(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Поделиться файлом',
            onSelected: (type) async {
              try {
                await ExportService.shareFile(dish, type);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка при экспорте: $e')),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ExportType.pdf,
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded,
                        color: AppColors.kcal, size: 20),
                    SizedBox(width: 10),
                    Text('Экспорт в PDF'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: ExportType.docx,
                child: Row(
                  children: [
                    Icon(Icons.description_rounded,
                        color: AppColors.carbs, size: 20),
                    SizedBox(width: 10),
                    Text('Экспорт в Word (.docx)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: ExportType.xlsx,
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded,
                        color: AppColors.protein, size: 20),
                    SizedBox(width: 10),
                    Text('Экспорт в Excel (.xlsx)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Информационная плашка режима бланка
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
            child: Row(
              children: [
                Icon(
                  dish.blankMode == BlankMode.photoCross
                      ? Icons.grid_on_rounded
                      : Icons.view_list_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Режим: ${dish.blankMode.displayName}',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dish.ingredients.length} инг.',
                  style: AppTypography.numericSmall,
                ),
              ],
            ),
          ),

          // Интерактивный лист бланка с горизонтальным и вертикальным скроллом
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black26, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Постоянный заголовок бланка
                      SizedBox(
                        width: _totalWidth,
                        child: Column(
                          children: [
                            const Text(
                              'Расчет энергетической и пищевой ценности блюда',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (dish.showTitleInExport &&
                                dish.title.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                dish.title.trim(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Таблица бланка 1:1
                      _buildPreviewTable(dish, calc),

                      const SizedBox(height: 12),

                      // Подвал с 6 строками формулы 1:1 как на фото
                      _buildFormulaBlock(dish, calc),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Нижняя панель действий экспорта
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color:
                        isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF'),
                      onPressed: () =>
                          ExportService.shareFile(dish, ExportType.pdf),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_rounded, size: 18),
                      label: const Text('Word'),
                      onPressed: () =>
                          ExportService.shareFile(dish, ExportType.docx),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text('Excel'),
                      onPressed: () =>
                          ExportService.shareFile(dish, ExportType.xlsx),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Печать',
                    onPressed: () => ExportService.printPdf(dish),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTable(Dish dish, CalculationResult calc) {
    const minRows = 18;
    final totalRows =
        dish.ingredients.length < minRows ? minRows : dish.ingredients.length;
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    const double rowH = 22.0;

    final pPct = CalculationEngine.formatPercent(calc.retentionProtein);
    final fPct = CalculationEngine.formatPercent(calc.retentionFat);
    final cPct = CalculationEngine.formatPercent(calc.retentionCarbs);

    final leftNineRows = <Widget>[];
    for (int i = 0; i < totalRows; i++) {
      if (i < dish.ingredients.length) {
        final ing = dish.ingredients[i];
        leftNineRows.add(
          Row(
            children: [
              _cell('${i + 1}', _w0, rowH),
              _cell(ing.product.name, _w1, rowH, align: Alignment.centerLeft),
              _cell(CalculationEngine.formatGrams(ing.netGramsRounded), _w2,
                  rowH),
              _cell(CalculationEngine.formatMacro(ing.product.protein), _w3,
                  rowH),
              _cell(
                  CalculationEngine.formatMacro(ing.proteinInDish), _w4, rowH),
              _cell(CalculationEngine.formatMacro(ing.product.fat), _w5, rowH),
              _cell(CalculationEngine.formatMacro(ing.fatInDish), _w6, rowH),
              _cell(
                  CalculationEngine.formatMacro(ing.product.carbs), _w7, rowH),
              _cell(CalculationEngine.formatMacro(ing.carbsInDish), _w8, rowH),
            ],
          ),
        );
      } else {
        // Пустые строки НЕ нумеруются
        leftNineRows.add(
          Row(
            children: [
              _cell('', _w0, rowH),
              _cell('', _w1, rowH),
              _cell('', _w2, rowH),
              _cell('', _w3, rowH),
              _cell('', _w4, rowH),
              _cell('', _w5, rowH),
              _cell('', _w6, rowH),
              _cell('', _w7, rowH),
              _cell('', _w8, rowH),
            ],
          ),
        );
      }
    }

    // Строка 1: Итого (сумма по столбцам)
    leftNineRows.add(
      Row(
        children: [
          _mergedTotalLabelCell(_w01, rowH),
          _cell(CalculationEngine.formatGrams(calc.rawTotalWeight), _w2, rowH,
              bold: true),
          _cell('', _w3, rowH),
          _cell(CalculationEngine.formatMacro(calc.rawTotalProtein), _w4, rowH,
              bold: true),
          _cell('', _w5, rowH),
          _cell(CalculationEngine.formatMacro(calc.rawTotalFat), _w6, rowH,
              bold: true),
          _cell('', _w7, rowH),
          _cell(CalculationEngine.formatMacro(calc.rawTotalCarbs), _w8, rowH,
              bold: true),
        ],
      ),
    );

    // Строка 2: Сохранность,%
    leftNineRows.add(
      Row(
        children: [
          _cell('Сохранность,%', _w01, rowH,
              bold: true, align: Alignment.centerLeft),
          _cell('', _w2, rowH),
          _cell('$pPct', _w34, rowH, bold: true),
          _cell('$fPct', _w56, rowH, bold: true),
          _cell('$cPct', _w78, rowH, bold: true),
        ],
      ),
    );

    // Колонка 10 для области сырья + Итого + Сохранность,%
    Widget col10Middle;
    if (isCrossMode) {
      final crossHeight = (totalRows + 2) * rowH;
      col10Middle = Container(
        width: _w9,
        height: crossHeight,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 0.6),
        ),
        child: CustomPaint(
          size: Size(_w9, crossHeight),
          painter: _FullBoxCrossPainter(),
        ),
      );
    } else {
      final col10Cells = <Widget>[];
      for (int i = 0; i < totalRows; i++) {
        if (i < dish.ingredients.length) {
          final ing = dish.ingredients[i];
          col10Cells.add(
            _cell(
              CalculationEngine.formatKcal(ing.blankKcalInDish),
              _w9,
              rowH,
            ),
          );
        } else {
          col10Cells.add(_cell('', _w9, rowH));
        }
      }
      col10Cells.add(
        _cell(
          calc.rawTotalKcal != null
              ? CalculationEngine.formatKcal(calc.rawTotalKcal!)
              : '',
          _w9,
          rowH,
          bold: true,
        ),
      );
      col10Cells.add(_cell('—', _w9, rowH));
      col10Middle = Column(children: col10Cells);
    }

    return Container(
      width: _totalWidth,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTwoLevelHeader(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _wLeft9,
                child: Column(children: leftNineRows),
              ),
              col10Middle,
            ],
          ),
          // Строка 3: После тепловой обработки
          Row(
            children: [
              _cell('После тепловой обработки', _w01, rowH + 2,
                  bold: true, align: Alignment.centerLeft),
              _cell(CalculationEngine.formatGrams(calc.yieldGrams), _w2,
                  rowH + 2),
              _cell(CalculationEngine.formatMacro(calc.cookedProtein), _w34,
                  rowH + 2,
                  bold: true),
              _cell(
                  CalculationEngine.formatMacro(calc.cookedFat), _w56, rowH + 2,
                  bold: true),
              _cell(CalculationEngine.formatMacro(calc.cookedCarbs), _w78,
                  rowH + 2,
                  bold: true),
              _cell(
                  CalculationEngine.formatKcal(calc.cookedKcal), _w9, rowH + 2,
                  bold: true),
            ],
          ),
          // Опциональная строка 4: В 100 г блюда
          if (dish.showPer100gRowInExport)
            Row(
              children: [
                _cell('В 100 г блюда', _w01, rowH,
                    bold: true, align: Alignment.centerLeft),
                _cell('100', _w2, rowH, bold: true),
                _cell(CalculationEngine.formatMacro(calc.per100gProtein), _w34,
                    rowH,
                    bold: true),
                _cell(
                    CalculationEngine.formatMacro(calc.per100gFat), _w56, rowH,
                    bold: true),
                _cell(CalculationEngine.formatMacro(calc.per100gCarbs), _w78,
                    rowH,
                    bold: true),
                _cell(CalculationEngine.formatKcal(calc.per100gKcal), _w9, rowH,
                    bold: true),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTwoLevelHeader() {
    const double h1 = 24.0;
    const double h2 = 30.0;
    const double hTotal = h1 + h2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerCell('№', _w0, hTotal),
        _headerCell('Наименование\nсырья', _w1, hTotal),
        _headerCell('Количество,\nг', _w2, hTotal),
        Column(
          children: [
            _headerCell('Белки, г', _w34, h1),
            Row(
              children: [
                _headerCell('В 100\nг', _w3, h2, fontSize: 8.5),
                _headerCell('В\nблюде', _w4, h2, fontSize: 8.5),
              ],
            ),
          ],
        ),
        Column(
          children: [
            _headerCell('Жиры, г', _w56, h1),
            Row(
              children: [
                _headerCell('В 100\nг', _w5, h2, fontSize: 8.5),
                _headerCell('В\nблюде', _w6, h2, fontSize: 8.5),
              ],
            ),
          ],
        ),
        Column(
          children: [
            _headerCell('Углеводы, г', _w78, h1),
            Row(
              children: [
                _headerCell('В 100\nг', _w7, h2, fontSize: 8.5),
                _headerCell('В\nблюде', _w8, h2, fontSize: 8.5),
              ],
            ),
          ],
        ),
        _headerCell('энергетическая\nценность,\nккал', _w9, hTotal),
      ],
    );
  }

  Widget _headerCell(
    String text,
    double width,
    double height, {
    double fontSize = 9.5,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: Colors.black, width: 0.6),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _mergedTotalLabelCell(double width, double height) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.6),
      ),
      child: RichText(
        text: const TextSpan(
          children: [
            TextSpan(
              text: 'Итого ',
              style: TextStyle(
                color: Colors.black,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: '(сумма по столбцам)',
              style: TextStyle(
                color: Colors.black,
                fontSize: 9.0,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String text,
    double width,
    double height, {
    bool bold = false,
    Alignment align = Alignment.center,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.black,
          fontSize: 9.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildFormulaBlock(Dish dish, CalculationResult calc) {
    final pPct = CalculationEngine.formatPercent(calc.retentionProtein);
    final fPct = CalculationEngine.formatPercent(calc.retentionFat);
    final cPct = CalculationEngine.formatPercent(calc.retentionCarbs);
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

    return Container(
      width: _totalWidth,
      padding: const EdgeInsets.only(left: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Сохранность после тепловой обработки:',
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            pLine,
            style: const TextStyle(color: Colors.black, fontSize: 10.5),
          ),
          const SizedBox(height: 2),
          Text(
            fLine,
            style: const TextStyle(color: Colors.black, fontSize: 10.5),
          ),
          const SizedBox(height: 2),
          Text(
            cLine,
            style: const TextStyle(color: Colors.black, fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          const Text(
            'Энергетическая ценность:',
            style: TextStyle(
              color: Colors.black,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            kcalLine,
            style: const TextStyle(color: Colors.black, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _FullBoxCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 0.85;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
