import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/blank_mode.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/export/export_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/dish_provider.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_sheet.dart';
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
  static const double _minScale = 0.2;
  static const double _maxScale = 2.5;
  static const double _baseDocWidth = 758.0;

  final _transform = TransformationController();
  double _scale = 1;
  double _fitScale = 1;
  bool _initialFitApplied = false;
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

  void _applyScale(double scale, {double? viewportWidth, double? viewportHeight}) {
    final next = scale.clamp(_minScale, _maxScale);
    final oldScale = _scale > 0 ? _scale : 1.0;
    final matrix = _transform.value;
    if (viewportWidth != null &&
        viewportHeight != null &&
        viewportWidth > 0 &&
        viewportHeight > 0) {
      final cx = viewportWidth / 2;
      final cy = viewportHeight / 2;
      final tx = matrix.storage[12];
      final ty = matrix.storage[13];
      final ratio = next / oldScale;
      final nextTx = cx - (cx - tx) * ratio;
      final nextTy = cy - (cy - ty) * ratio;
      final updated = Matrix4.identity()
        ..translate(nextTx, nextTy)
        ..scale(next, next, 1.0);
      setState(() {
        _scale = next;
        _transform.value = updated;
      });
      return;
    }
    setState(() {
      _scale = next;
      _transform.value = Matrix4.diagonal3Values(next, next, 1.0);
    });
  }

  double? _viewerWidth;
  double? _viewerHeight;

  void _zoomBy(double factor) => _applyScale(
        _scale * factor,
        viewportWidth: _viewerWidth,
        viewportHeight: _viewerHeight,
      );

  void _resetZoom() => _applyScale(_fitScale);

  Future<void> _run(Future<void> Function() action,
      {String failure = 'Не удалось экспортировать'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      AppHaptics.commit();
    } catch (e) {
      AppHaptics.error();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e, prefix: failure))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dish = ref.watch(dishProvider);
    final calc = ref.watch(calculationResultProvider);
    final canExport = calc != null;
    final p = Palette.of(context);

    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        title: const Text(
          'Бланк',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip:
                canExport ? 'Экспорт' : 'Сначала исправьте ошибку расчёта',
            onPressed:
                (_busy || !canExport) ? null : () => _showExportSheet(dish),
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: canExport
                ? 'Печать бланка'
                : 'Сначала исправьте ошибку расчёта',
            onPressed: (_busy || !canExport)
                ? null
                : () => _run(() => ExportService.printPdf(dish),
                    failure: 'Не удалось напечатать'),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final media = MediaQuery.sizeOf(context);
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final compactBanner = AppLayout.isCompactBlankBar(media.width);
          final stackModeBanner =
              textScale > 1.35 || compactBanner;
          final modeIcon = Icon(
            dish.blankMode == BlankMode.photoCross
                ? Icons.grid_on_rounded
                : Icons.view_list_rounded,
            size: IconSizes.xs,
            color: p.inkSecondary,
          );

          final docScale = MediaQuery.textScalerOf(context).scale(9.5) / 9.5;
          final docOuterWidth =
              _baseDocWidth * docScale + 40.0 + Space.x4 * 2;

          final modeBannerContent = Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.x4, vertical: Space.x2),
            child: stackModeBanner
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: Space.x1),
                        child: modeIcon,
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Режим: ${dish.blankMode.displayName}',
                              style: AppTypography.bodySm
                                  .copyWith(color: p.inkSecondary),
                            ),
                            Text(
                              pluralIngredients(dish.ingredients.length),
                              style: AppTypography.numSm
                                  .copyWith(color: p.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: Space.x2),
                        child: Icon(Icons.tune_rounded,
                            size: IconSizes.btn, color: p.accent),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      modeIcon,
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Text(
                          'Режим: ${dish.blankMode.displayName}',
                          style: AppTypography.bodySm
                              .copyWith(color: p.inkSecondary),
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      Flexible(
                        child: Text(
                          pluralIngredients(dish.ingredients.length),
                          style: AppTypography.numSm
                              .copyWith(color: p.inkSecondary),
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      Icon(Icons.tune_rounded,
                          size: IconSizes.btn, color: p.accent),
                    ],
                  ),
          );

          final modeBanner = DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(bottom: BorderSide(color: p.divider)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('blank-mode-banner'),
                onTap: () => _showBlankOptionsSheet(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kMinTapTarget,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: modeBannerContent,
                  ),
                ),
              ),
            ),
          );

          return Column(
            children: [
              modeBanner,

              // Лист бланка: при ошибке расчёта показываем баннер вне InteractiveViewer.
              Expanded(
                child: calc == null
                    ? Container(
                        color: p.canvas,
                        alignment: Alignment.topCenter,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Space.x4),
                          child: AppContentFrame(
                            child: CalcErrorBanner(
                              detail: ref.watch(calculationErrorProvider),
                            ),
                          ),
                        ),
                      )
                    : ColoredBox(
                        color: p.mountingTable,
                        child: CustomPaint(
                          painter:
                              _MountingDotGridPainter(dotColor: p.tableDot),
                          child: LayoutBuilder(
                            builder: (context, viewerConstraints) {
                              final viewportW = viewerConstraints.maxWidth;
                              final viewportH = viewerConstraints.maxHeight;
                              _viewerWidth =
                                  viewportW.isFinite ? viewportW : null;
                              _viewerHeight =
                                  viewportH.isFinite ? viewportH : null;
                              final nextFit =
                                  (viewportW.isFinite && viewportW > 0)
                                      ? (viewportW / docOuterWidth)
                                          .clamp(_minScale, 1.0)
                                      : 1.0;
                              _fitScale = nextFit;
                              if (!_initialFitApplied &&
                                  viewportW.isFinite &&
                                  viewportW > 0) {
                                _initialFitApplied = true;
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _applyScale(_fitScale);
                                });
                              }
                              return InteractiveViewer(
                                transformationController: _transform,
                                minScale: _minScale,
                                maxScale: _maxScale,
                                constrained: false,
                                boundaryMargin: const EdgeInsets.all(80),
                                child: Container(
                                  padding: const EdgeInsets.all(Space.x4),
                                  child: _BlankPreviewDocument(
                                    dish: dish,
                                    calc: calc,
                                    scale: docScale,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
              ),

              // Панель масштаба: плоский нижний док с 1 px верхним разделителем.
              AppBottomBar(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.x2, vertical: Space.x1),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
                    final twoRows =
                        AppLayout.isCompactBlankBar(constraints.maxWidth) ||
                            (textScale > 1.2 && constraints.maxWidth < 520);

                    final zoomOutBtn = IconButton(
                      tooltip: 'Уменьшить',
                      icon: const Icon(Icons.zoom_out_rounded),
                      onPressed: (calc == null || _scale <= _minScale + 0.01)
                          ? null
                          : () => _zoomBy(1 / 1.25),
                    );
                    final zoomInBtn = IconButton(
                      tooltip: 'Увеличить',
                      icon: const Icon(Icons.zoom_in_rounded),
                      onPressed: (calc == null || _scale >= _maxScale - 0.01)
                          ? null
                          : () => _zoomBy(1.25),
                    );
                    final scaleLabel = Text(
                      'Масштаб ${(_scale * 100).round()}\u202F%',
                      key: const ValueKey('blank-zoom'),
                      textAlign: TextAlign.center,
                      style: AppTypography.numSm.copyWith(color: p.inkSecondary),
                    );
                    final resetBtn = TextButton.icon(
                      onPressed: calc == null ? null : _resetZoom,
                      icon: const Icon(Icons.fit_screen_rounded,
                          size: IconSizes.btn),
                      label: const Text('По размеру'),
                    );

                    if (twoRows) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                zoomOutBtn,
                                const SizedBox(width: Space.x1),
                                Flexible(child: Center(child: scaleLabel)),
                                const SizedBox(width: Space.x1),
                                zoomInBtn,
                              ],
                            ),
                          ),
                          resetBtn,
                        ],
                      );
                    }

                    return IntrinsicHeight(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          zoomOutBtn,
                          const SizedBox(width: Space.x1),
                          Flexible(child: Center(child: scaleLabel)),
                          const SizedBox(width: Space.x1),
                          zoomInBtn,
                          const SizedBox(width: Space.x2),
                          resetBtn,
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Один сгруппированный лист экспорта вместо двух наборов кнопок.
  Future<void> _showExportSheet(Dish dish) async {
    final p = Palette.of(context);
    final calc = ref.read(calculationResultProvider);
    if (calc == null) return;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppSheetScaffold(
        title: 'Экспорт и вид бланка',
        subtitle: 'Файл откроется в меню «Поделиться»: сохраните его в «Файлы» или отправьте.',
        showHandle: true,
        showClose: true,
        bodyPadding:
            const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ExportTile(
              palette: p,
              icon: Icons.picture_as_pdf_rounded,
              title: 'PDF',
              subtitle: 'Векторный, идентичен типовому бланку',
              onTap: () => Navigator.pop(ctx, ExportType.pdf),
            ),
            Divider(color: p.divider, height: 1),
            _ExportTile(
              palette: p,
              icon: Icons.description_rounded,
              title: 'Word (.docx)',
              subtitle: 'Редактируемый документ',
              onTap: () => Navigator.pop(ctx, ExportType.docx),
            ),
            Divider(color: p.divider, height: 1),
            _ExportTile(
              palette: p,
              icon: Icons.table_chart_rounded,
              title: 'Excel (.xlsx)',
              subtitle: 'С живыми формулами',
              onTap: () => Navigator.pop(ctx, ExportType.xlsx),
            ),
            Divider(color: p.divider, height: 1),
            _ExportTile(
              palette: p,
              icon: Icons.content_copy_rounded,
              title: 'Скопировать КБЖУ текстом',
              subtitle: 'Краткая сводка состава и цифр для мессенджеров',
              onTap: () => Navigator.pop(ctx, 'copy-text'),
            ),
            Divider(color: p.divider, height: 1),
            _ExportTile(
              palette: p,
              icon: Icons.tune_rounded,
              title: 'Настроить вид бланка',
              subtitle: 'Режим с крестом, строка «В 100 г», заголовок',
              onTap: () => Navigator.pop(ctx, 'blank-options'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is ExportType) {
      await _run(() => ExportService.shareFile(dish, choice));
    } else if (choice == 'copy-text') {
      await Clipboard.setData(
        ClipboardData(text: ExportService.formatPlainTextSummary(dish, calc)),
      );
      if (!mounted) return;
      AppHaptics.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сводка КБЖУ скопирована')),
      );
    } else if (choice == 'blank-options') {
      _showBlankOptionsSheet();
    }
  }

  void _showBlankOptionsSheet() {
    final p = Palette.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, ref, _) {
          final dish = ref.watch(dishProvider);
          final notifier = ref.read(dishProvider.notifier);
          return AppSheetScaffold(
            title: 'Настройки бланка',
            showHandle: true,
            showClose: true,
            bodyPadding: const EdgeInsets.fromLTRB(
                Space.x4, Space.x3, Space.x4, Space.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<BlankMode>(
                  showSelectedIcon: false,
                  style: AppSegmentedStyle.of(p, compact: true),
                  segments: [
                    for (final mode in BlankMode.values)
                      ButtonSegment<BlankMode>(
                        value: mode,
                        label: Text(
                          mode.shortName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected: {dish.blankMode},
                  onSelectionChanged: (sel) {
                    AppHaptics.toggle();
                    notifier.setBlankMode(sel.single);
                  },
                ),
                const SizedBox(height: Space.x2),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  title: Text(
                    'Печатать название в заголовке бланка',
                    style: AppTypography.bodySm.copyWith(color: p.ink),
                  ),
                  value: dish.showTitleInExport,
                  onChanged: (v) {
                    AppHaptics.toggle();
                    notifier.toggleShowTitle(v);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  title: Text(
                    'Строка «В 100 г блюда» в бланке',
                    style: AppTypography.bodySm.copyWith(color: p.ink),
                  ),
                  value: dish.showPer100gRowInExport,
                  onChanged: (v) {
                    AppHaptics.toggle();
                    notifier.toggleShowPer100gRow(v);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
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
    return TactilePress(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.fieldAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.x1, vertical: Space.x3),
              child: Row(
                children: [
                  Icon(icon, size: IconSizes.lg, color: p.inkSecondary),
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
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.14),
            blurRadius: 20,
            offset: Offset(0, 6),
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
        color: AppColors.paperHeader,
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

class _MountingDotGridPainter extends CustomPainter {
  final Color dotColor;

  const _MountingDotGridPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;
    const step = 16.0;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MountingDotGridPainter oldDelegate) =>
      oldDelegate.dotColor != dotColor;
}



