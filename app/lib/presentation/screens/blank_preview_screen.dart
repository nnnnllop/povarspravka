import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/export/export_service.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import '../widgets/calc_error_banner.dart';

/// Просмотр бланка (аудит P1-8).
///
/// Было: лист в двух вложенных `SingleChildScrollView` без масштабирования
/// (на 320 dp от бланка видно ~40 % ширины, и уменьшить его нельзя) плюс
/// ОДИН И ТОТ ЖЕ набор из четырёх кнопок экспорта в двух местах — в меню
/// AppBar и в нижней панели.
///
/// Стало:
/// • `InteractiveViewer` с пинч-зумом 0.35×–2.5× и перетаскиванием;
/// • один источник экспорта — кнопка «Экспорт», открывающая сгруппированный
///   лист (PDF / Word / Excel + «Печать»), а не дублирующиеся панели;
/// • строка режима и счётчик сгруппированы в одну плашку над листом.
class BlankPreviewScreen extends ConsumerStatefulWidget {
  const BlankPreviewScreen({super.key});

  @override
  ConsumerState<BlankPreviewScreen> createState() => _BlankPreviewScreenState();
}

class _BlankPreviewScreenState extends ConsumerState<BlankPreviewScreen> {
  static const double _minScale = 0.35;
  static const double _maxScale = 2.5;

  final _transform = TransformationController();
  double _scale = 1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final next = _transform.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() > 0.01 && mounted) {
      setState(() => _scale = next);
    }
  }

  void _zoomBy(double factor) {
    final next = (_scale * factor).clamp(_minScale, _maxScale);
    setState(() {
      _scale = next;
      _transform.value = Matrix4.identity()..scale(next);
    });
  }

  void _resetZoom() {
    setState(() {
      _scale = 1;
      _transform.value = Matrix4.identity();
    });
  }

  Future<void> _run(Future<void> Function() action,
      {String failure = 'Ошибка при экспорте'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      AppHaptics.commit();
    } catch (e) {
      AppHaptics.error();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$failure: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final p = Palette.of(context);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        // AppBar сам корректно масштабируется вместе с текстом. Прежняя
        // формула `64 * scale(14)/14` = `64·s` давала двойное масштабирование
        // и при s=2.0 толкала панель до 128 dp (аудит P2-8).
        toolbarHeight: kToolbarHeight,
        title: const Text('Бланк расчёта КБЖУ',
            softWrap: true,
            maxLines: 3,
            overflow: TextOverflow.visible),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Экспорт',
            onPressed: _busy ? null : () => _showExportSheet(dish),
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Печать бланка',
            onPressed:
                _busy ? null : () => _run(() => ExportService.printPdf(dish),
                    failure: 'Ошибка при печати'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Плашка режима: имя режима и счётчик в одной строке.
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.x4, vertical: Space.x2),
            color: p.sunken,
            child: Row(
              children: [
                Icon(
                  dish.blankMode == BlankMode.photoCross
                      ? Icons.grid_on_rounded
                      : Icons.view_list_rounded,
                  size: 16,
                  color: p.inkSecondary,
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    'Режим: ${dish.blankMode.displayName}',
                    style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Text(
                  '${dish.ingredients.length} инг.',
                  style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                ),
              ],
            ),
          ),

          // Лист бланка: пинч-зум и перетаскивание.
          Expanded(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: _minScale,
              maxScale: _maxScale,
              // Лист больше экрана — панорамируем свободно по обеим осям.
              constrained: false,
              boundaryMargin: const EdgeInsets.all(80),
              child: Container(
                padding: const EdgeInsets.all(Space.x4),
                child: calc == null
                    // STATE-01: невычислимое блюдо не роняет бланк.
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CalcErrorBanner(
                              detail: ref.watch(calculationErrorProvider)),
                        ],
                      )
                    : _BlankPreviewDocument(
                        dish: dish,
                        calc: calc,
                        scale:
                            MediaQuery.textScalerOf(context).scale(9.5) / 9.5,
                      ),
              ),
            ),
          ),

          // Панель масштаба: единственные элементы управления листом.
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.x2, vertical: Space.x2),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.divider)),
              ),
              // Wrap, а не Row: при масштабе текста 2.0× подпись «По размеру»
              // не помещается рядом с кнопками зума и должна перейти на новую
              // строку, а не обрезаться (проверено design_audit_test).
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Уменьшить',
                    icon: const Icon(Icons.zoom_out_rounded),
                    onPressed: () => _zoomBy(1 / 1.25),
                  ),
                  Text(
                    'Масштаб ${(_scale * 100).round()} %',
                    key: const ValueKey('blank-zoom'),
                    textAlign: TextAlign.center,
                    style:
                        AppTypography.numSm.copyWith(color: p.inkSecondary),
                  ),
                  IconButton(
                    tooltip: 'Увеличить',
                    icon: const Icon(Icons.zoom_in_rounded),
                    onPressed: () => _zoomBy(1.25),
                  ),
                  TextButton.icon(
                    onPressed: _resetZoom,
                    icon: const Icon(Icons.fit_screen_rounded, size: 18),
                    label: const Text('По размеру'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Один сгруппированный лист экспорта вместо двух наборов кнопок.
  Future<void> _showExportSheet(Dish dish) async {
    final p = Palette.of(context);
    final choice = await showModalBottomSheet<ExportType>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Сохранить бланк',
                style: AppTypography.title.copyWith(color: p.ink)),
            const SizedBox(height: Space.x1),
            Text(
              'Файл сохраняется на телефоне, дальше — «Поделиться» или печать.',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
            const SizedBox(height: Space.x3),
            _ExportTile(
              palette: p,
              icon: Icons.picture_as_pdf_rounded,
              title: 'PDF',
              subtitle: 'Векторный, идентичен типовому бланку',
              onTap: () => Navigator.pop(ctx, ExportType.pdf),
            ),
            _ExportTile(
              palette: p,
              icon: Icons.description_rounded,
              title: 'Word (.docx)',
              subtitle: 'Редактируемый документ',
              onTap: () => Navigator.pop(ctx, ExportType.docx),
            ),
            _ExportTile(
              palette: p,
              icon: Icons.table_chart_rounded,
              title: 'Excel (.xlsx)',
              subtitle: 'С живыми формулами',
              onTap: () => Navigator.pop(ctx, ExportType.xlsx),
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await _run(() => ExportService.shareFile(dish, choice));
    }
  }
}

class _ExportTile extends StatelessWidget {
  final Palette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExportTile({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.x2),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.x3),
            child: Row(
              children: [
                Icon(icon, size: 22, color: p.inkSecondary),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTypography.body.copyWith(
                              color: p.ink, fontWeight: FontWeight.w700)),
                      Text(subtitle,
                          style: AppTypography.caption
                              .copyWith(color: p.inkSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.inkMuted),
              ],
            ),
          ),
        ),
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
    // Новый расчёт без веса готового блюда: выход и «в 100 г» не
    // определены — печатаем прочерк, а не «0».
    final noYield = calc.usesLossTable && !calc.hasYield;

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
              _cell(
                  noYield
                      ? '—'
                      : CalculationEngine.formatGrams(calc.yieldGrams),
                  _w2,
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
                _cell(
                    noYield
                        ? '—'
                        : CalculationEngine.formatMacro(calc.per100gProtein),
                    _w34,
                    rowH,
                    bold: true),
                _cell(
                    noYield
                        ? '—'
                        : CalculationEngine.formatMacro(calc.per100gFat),
                    _w56,
                    rowH,
                    bold: true),
                _cell(
                    noYield
                        ? '—'
                        : CalculationEngine.formatMacro(calc.per100gCarbs),
                    _w78,
                    rowH,
                    bold: true),
                _cell(
                    noYield
                        ? '—'
                        : CalculationEngine.formatKcal(calc.per100gKcal),
                    _w9,
                    rowH,
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
                _headerCell('В 100\nг', _w3, h2, fontSize: 9.5),
                _headerCell('В\nблюде', _w4, h2, fontSize: 9.5),
              ],
            ),
          ],
        ),
        Column(
          children: [
            _headerCell('Жиры, г', _w56, h1),
            Row(
              children: [
                _headerCell('В 100\nг', _w5, h2, fontSize: 9.5),
                _headerCell('В\nблюде', _w6, h2, fontSize: 9.5),
              ],
            ),
          ],
        ),
        Column(
          children: [
            _headerCell('Углеводы, г', _w78, h1),
            Row(
              children: [
                _headerCell('В 100\nг', _w7, h2, fontSize: 9.5),
                _headerCell('В\nблюде', _w8, h2, fontSize: 9.5),
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
                fontSize: 9.5,
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
    // Новый расчёт: потери применяются к КАЖДОМУ продукту по его группе,
    // одного умножения суммы нет; процент — итоговая доля готовое/сырьё.
    final table = calc.usesLossTable;
    String tableLine(String what, String pct, double raw, double cooked) =>
        hasItems
            ? '= Σ $what продукта × (100 − потери группы) / 100 = '
                '${CalculationEngine.formatMacro(raw)} → '
                '${CalculationEngine.formatMacro(cooked)} г (в среднем $pct %)'
            : '= Σ $what продукта × (100 − потери группы) / 100';

    final pLine = table
        ? tableLine('белков', pPct, calc.rawTotalProtein, calc.cookedProtein)
        : hasItems
        ? '= Сумма белков *$pPct /100 = ${CalculationEngine.formatMacro(calc.rawTotalProtein)} * $pPct / 100 = ${CalculationEngine.formatMacro(calc.cookedProtein)} г'
        : '= Сумма белков *$pPct /100';
    final fLine = table
        ? tableLine('жиров', fPct, calc.rawTotalFat, calc.cookedFat)
        : hasItems
        ? '= Сумма жиров *$fPct/100 = ${CalculationEngine.formatMacro(calc.rawTotalFat)} * $fPct / 100 = ${CalculationEngine.formatMacro(calc.cookedFat)} г'
        : '= Сумма жиров *$fPct/100';
    final cLine = table
        ? tableLine('углеводов', cPct, calc.rawTotalCarbs, calc.cookedCarbs)
        : hasItems
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
          Text(
            table
                ? 'Потери при тепловой обработке — по группам продуктов '
                    '(${calc.process.label}):'
                : 'Сохранность после тепловой обработки:',
            style: const TextStyle(
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
          if (table) ...[
            const SizedBox(height: 6),
            const Text(
              kNotGostNotice,
              key: ValueKey('blank-not-gost'),
              style: TextStyle(color: Colors.black, fontSize: 10.5),
            ),
          ],
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



