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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64 * MediaQuery.textScalerOf(context).scale(14) / 14,
        title: const Text('Бланк расчета КБЖУ',
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.visible,
            style: TextStyle(fontSize: 18, height: 1.1)),
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
                child: _BlankPreviewDocument(
                    dish: dish,
                    calc: calc,
                    scale: MediaQuery.textScalerOf(context).scale(9.5) / 9.5),
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
                      onPressed: () async {
                        try {
                          await ExportService.shareFile(dish, ExportType.pdf);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка при экспорте: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.description_rounded, size: 18),
                      label: const Text('Word'),
                      onPressed: () async {
                        try {
                          await ExportService.shareFile(dish, ExportType.docx);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка при экспорте: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text('Excel'),
                      onPressed: () async {
                        try {
                          await ExportService.shareFile(dish, ExportType.xlsx);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка при экспорте: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Печать',
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlankPreviewDocument extends StatelessWidget {
  const _BlankPreviewDocument(
      {required this.dish, required this.calc, required this.scale});
  final Dish dish;
  final CalculationResult calc;
  final double scale;
  // Фиксированные ширины колонок для 1:1 совпадения объединенных ячеек
  double get _w0 => 32.0 * scale; // №
  double get _w1 => 230.0 * scale; // Наименование сырья
  double get _w2 => 72.0 * scale; // Количество, г
  double get _w3 => 62.0 * scale; // Белки В 100 г
  double get _w4 => 62.0 * scale; // Белки В блюде
  double get _w5 => 62.0 * scale; // Жиры В 100 г
  double get _w6 => 62.0 * scale; // Жиры В блюде
  double get _w7 => 62.0 * scale; // Углеводы В 100 г
  double get _w8 => 62.0 * scale; // Углеводы В блюде
  double get _w9 => 114.0 * scale; // Энергетическая ценность, ккал

  double get _w01 => _w0 + _w1;
  double get _w34 => _w3 + _w4;
  double get _w56 => _w5 + _w6;
  double get _w78 => _w7 + _w8;
  double get _wLeft9 => _w0 + _w1 + _w2 + _w3 + _w4 + _w5 + _w6 + _w7 + _w8;
  double get _totalWidth => _wLeft9 + _w9;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                if (dish.showTitleInExport && dish.title.trim().isNotEmpty) ...[
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
    );
  }

  double _contentHeight(String text, double width) {
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style:
              const TextStyle(fontFamily: 'Arial', fontSize: 9.5, height: 1.2)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout(maxWidth: width - 10);
    final height = painter.height + 4;
    painter.dispose();
    return height;
  }

  Widget _buildPreviewTable(Dish dish, CalculationResult calc) {
    const minRows = 18;
    final totalRows =
        dish.ingredients.length < minRows ? minRows : dish.ingredients.length;
    final isCrossMode = dish.blankMode == BlankMode.photoCross;
    final double rowH = 22.0 * scale;
    final rawHeights = List<double>.generate(totalRows, (i) {
      if (i >= dish.ingredients.length) return rowH;
      final ing = dish.ingredients[i];
      final labels = [
        '${i + 1}',
        ing.product.name,
        CalculationEngine.formatGrams(ing.netGramsRounded),
        CalculationEngine.formatMacro(ing.product.protein),
        CalculationEngine.formatMacro(ing.proteinInDish),
        CalculationEngine.formatMacro(ing.product.fat),
        CalculationEngine.formatMacro(ing.fatInDish),
        CalculationEngine.formatMacro(ing.product.carbs),
        CalculationEngine.formatMacro(ing.carbsInDish),
        CalculationEngine.formatKcal(ing.blankKcalInDish)
      ];
      final widths = [_w0, _w1, _w2, _w3, _w4, _w5, _w6, _w7, _w8, _w9];
      var height = rowH;
      for (var j = 0; j < labels.length; j++) {
        final needed = _contentHeight(labels[j], widths[j]);
        if (needed > height) height = needed;
      }
      return height;
    });

    final pPct = CalculationEngine.formatPercent(calc.retentionProtein);
    final fPct = CalculationEngine.formatPercent(calc.retentionFat);
    final cPct = CalculationEngine.formatPercent(calc.retentionCarbs);

    final leftNineRows = <Widget>[];
    for (int i = 0; i < totalRows; i++) {
      if (i < dish.ingredients.length) {
        final ing = dish.ingredients[i];
        final ingredientHeight = rawHeights[i];
        leftNineRows.add(
          Row(
            children: [
              _cell('${i + 1}', _w0, ingredientHeight),
              _cell(ing.product.name, _w1, ingredientHeight,
                  align: Alignment.centerLeft),
              _cell(CalculationEngine.formatGrams(ing.netGramsRounded), _w2,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.product.protein), _w3,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.proteinInDish), _w4,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.product.fat), _w5,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.fatInDish), _w6,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.product.carbs), _w7,
                  ingredientHeight),
              _cell(CalculationEngine.formatMacro(ing.carbsInDish), _w8,
                  ingredientHeight),
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
      final crossHeight =
          rawHeights.fold<double>(0, (sum, h) => sum + h) + 2 * rowH;
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
              rawHeights[i],
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
      foregroundDecoration: BoxDecoration(
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
    final double h1 = 24.0 * scale;
    final double h2 = 30.0 * scale;
    final double hTotal = h1 + h2;

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
        textScaler: TextScaler.linear(scale),
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
        style: TextStyle(
          color: Colors.black,
          fontSize: 9.5,
          fontFamily: 'Arial',
          height: 1.2,
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
