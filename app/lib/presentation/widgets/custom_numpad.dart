import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/calculation_math.dart';
import '../../core/calculation/calculation_validation.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/source_label.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'adaptive_host.dart';
import 'app_buttons.dart';
import 'instrument_widgets.dart';
import 'source_badge.dart';

/// Ввод массы продукта (аудит P0-1, P0-2).
///
/// Ключевые решения:
/// * «Брутто | Нетто» — это **единица измерения числа**, а не тумблер
///   функции: `SegmentedButton` 48 dp над полем.
/// * При смене единицы число конвертируется, рядом на 2 с появляется
///   дельта-подпись — видно, что и почему изменилось.
/// * Инлайн-переключение процента отходов прямо в том же нумпаде (без диалогов)
///   и инлайн-счётчик бытовых мер («− 1 +») без сброса режима Брутто.
/// * Явная кнопка сброса `C`, плюс удержание `⌫` тоже сбрасывает.
/// * Все клавиши срабатывают по `onTapDown` с тактильным сжатием `TactilePress`.
///
/// Сохранены публичные контракты (`CustomNumpadSheet`, `AnimatedSwitcher`
/// дисплея, ключи `key-0..9`, `key-,`, `key-⌫`, долгое нажатие на `⌫`,
/// `SegmentedButton<bool>`, тексты «Добавить в блюдо» / «Сохранить изменения»).
class CustomNumpadSheet extends StatefulWidget {
  final Product product;
  final double initialGrams;
  final bool initialIsGross;
  final bool isEditing;
  final Function(double grams, bool isGross) onConfirm;
  final void Function(Product product)? onProductUpdated;

  /// Колбэк удаления ингредиента из блюда (доступен в режиме редактирования).
  final VoidCallback? onDelete;

  /// Колбэк замены продукта в строке рецепта без потери веса (в режиме правки).
  final VoidCallback? onReplaceProduct;

  /// Колбэк настройки группы потерь и способа обработки (доступен в режиме правки).
  final VoidCallback? onEditLoss;

  /// Добавление новой независимой строки тем же продуктом (в режиме правки).
  final void Function(double grams, bool isGross)? onAddAsNewRow;

  const CustomNumpadSheet({
    super.key,
    required this.product,
    required this.initialGrams,
    this.initialIsGross = false,
    this.isEditing = false,
    required this.onConfirm,
    this.onProductUpdated,
    this.onDelete,
    this.onReplaceProduct,
    this.onEditLoss,
    this.onAddAsNewRow,
  });

  @override
  State<CustomNumpadSheet> createState() => _CustomNumpadSheetState();
}

class _CustomNumpadSheetState extends State<CustomNumpadSheet> {
  late String _currentInput;
  late bool _isGross;
  late double _wastePct;
  bool _isFreshInput = true;

  bool _isEditingWaste = false;
  String _wasteInput = '0';
  bool _isFreshWasteInput = true;
  String? _wasteError;

  ProductMeasure? _selectedMeasure;
  int _measureCount = 1;
  bool _showExtrasExpanded = false;

  /// Дельта-подпись, показываемая 2 с после смены единицы или параметра.
  String? _deltaNote;
  Timer? _deltaTimer;

  @override
  void initState() {
    super.initState();
    _currentInput = widget.initialGrams > 0
        ? widget.initialGrams.toString().replaceAll('.', ',')
        : '100';
    _isGross = widget.initialIsGross;
    _wastePct = widget.product.wastePct;
    _isFreshInput = true;
  }

  @override
  void dispose() {
    _deltaTimer?.cancel();
    super.dispose();
  }

  void _showDelta(String message) {
    _deltaTimer?.cancel();
    setState(() => _deltaNote = message);
    _deltaTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _deltaNote = null);
    });
  }

  String? _validateWasteInput(String raw) {
    final parsed = CalculationEngine.parseInputDouble(raw);
    if (parsed == null || !parsed.isFinite) return null;
    if (parsed < 0 || parsed >= 100) {
      return 'Отходы должны быть от 0 до 99,9\u202F%';
    }
    return null;
  }

  void _onKey(String k) {
    AppHaptics.key();
    setState(() {
      if (_isEditingWaste) {
        final (next, fresh) = _appendNumpadKeyValue(
          _wasteInput,
          _isFreshWasteInput,
          k,
          maxLength: 4,
        );
        _wasteInput = next;
        _isFreshWasteInput = fresh;
        _wasteError = _validateWasteInput(next);
        return;
      }
      final (next, fresh) = _appendNumpadKeyValue(
        _currentInput,
        _isFreshInput,
        k,
        maxLength: 7,
      );
      _currentInput = next;
      _isFreshInput = fresh;
      _selectedMeasure = null;
      _measureCount = 1;
    });
  }

  void _onBackspace() {
    AppHaptics.key();
    setState(() {
      if (_isEditingWaste) {
        final (next, fresh) = _backspaceNumpadString(_wasteInput);
        _wasteInput = next;
        _isFreshWasteInput = fresh;
        _wasteError = _validateWasteInput(next);
        return;
      }
      final (next, fresh) = _backspaceNumpadString(_currentInput);
      _currentInput = next;
      _isFreshInput = fresh;
      _selectedMeasure = null;
      _measureCount = 1;
    });
  }

  void _onClear() {
    AppHaptics.error();
    setState(() {
      if (_isEditingWaste) {
        _wasteInput = '0';
        _isFreshWasteInput = true;
        _wasteError = null;
        return;
      }
      _currentInput = '0';
      _isFreshInput = true;
      _deltaNote = null;
      _selectedMeasure = null;
      _measureCount = 1;
    });
  }

  void _onAdd(double delta) {
    AppHaptics.key();
    final val = CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final newVal =
        (val + delta).clamp(1.0, CalculationValidation.maxCustomYieldGrams);
    setState(() {
      _currentInput = CalculationEngine.formatGrams(newVal);
      _isFreshInput = false;
      _selectedMeasure = null;
      _measureCount = 1;
    });
  }

  void _setMode(bool gross) {
    if (gross == _isGross && !_isEditingWaste) return;
    AppHaptics.toggle();
    final mass = CalculationEngine.parseInputDouble(_currentInput);
    if (mass == null) {
      setState(() {
        _isGross = gross;
        _isEditingWaste = false;
        _wasteError = null;
      });
      return;
    }
    if (gross == _isGross) {
      setState(() {
        _isEditingWaste = false;
        _wasteError = null;
      });
      return;
    }
    final converted = gross
        ? Ingredient.grossFromNet(mass, _wastePct)
        : Ingredient.netFromGross(mass, _wastePct);
    if (converted == null || !converted.isFinite || converted > 9999999) {
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'При 100% отходов положительное нетто невозможно перевести в брутто.')));
      return;
    }
    final convertedStr = CalculationEngine.formatGrams(converted);
    setState(() {
      _isGross = gross;
      _isEditingWaste = false;
      _wasteError = null;
      _currentInput = convertedStr;
      _isFreshInput = true;
    });
    // Дельта-подпись: пользователь видит, ЧТО и ПОЧЕМУ поменялось.
    final beforeStr = CalculationEngine.formatGrams(mass);
    final wasteNote = _wastePct > 0
        ? ' (отходы ${CalculationEngine.formatWastePercent(_wastePct)} %)'
        : '';
    if (gross) {
      _showDelta('← $beforeStr г нетто · $convertedStr г брутто$wasteNote');
    } else {
      _showDelta('← $beforeStr г брутто · $convertedStr г нетто$wasteNote');
    }
  }

  void _setWastePct(double newPct) {
    AppHaptics.toggle();
    setState(() {
      _wastePct = newPct;
      _isEditingWaste = false;
      _wasteError = null;
    });
    if (_selectedMeasure != null && _isGross) {
      _applySelectedMeasure(showToast: false);
    }
  }

  void _toggleWasteEdit() {
    AppHaptics.key();
    setState(() {
      if (_isEditingWaste) {
        _isEditingWaste = false;
        _wasteError = null;
      } else {
        _isEditingWaste = true;
        _wasteInput =
            _wastePct > 0 ? CalculationEngine.formatWastePercent(_wastePct) : '0';
        _isFreshWasteInput = true;
        _wasteError = null;
      }
    });
  }

  void _applyWastePreset(String value) {
    AppHaptics.key();
    setState(() {
      _wasteInput = value;
      _isFreshWasteInput = false;
      _wasteError = null;
    });
  }

  void _confirmWasteEdit() {
    final parsed = CalculationEngine.parseInputDouble(_wasteInput);
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed >= 100) {
      AppHaptics.warn();
      setState(() {
        _wasteError = 'Отходы должны быть от 0 до 99,9\u202F%';
      });
      return;
    }
    AppHaptics.toggle();
    setState(() {
      _wastePct = parsed;
      _isEditingWaste = false;
      _wasteError = null;
    });
    if (_selectedMeasure != null && _isGross) {
      _applySelectedMeasure(showToast: false);
    }
    _showDelta(
        '✓ Отходы: ${CalculationEngine.formatWastePercent(parsed)} %');
  }

  void _selectMeasure(ProductMeasure measure) {
    AppHaptics.key();
    setState(() {
      _isEditingWaste = false;
      _wasteError = null;
      if (_selectedMeasure?.name == measure.name) {
        _measureCount = (_measureCount + 1).clamp(1, 99);
      } else {
        _selectedMeasure = measure;
        _measureCount = 1;
      }
    });
    _applySelectedMeasure();
  }

  void _stepMeasureCount(int delta) {
    if (_selectedMeasure == null) return;
    final next = (_measureCount + delta).clamp(1, 99);
    if (next == _measureCount) return;
    AppHaptics.key();
    setState(() => _measureCount = next);
    _applySelectedMeasure();
  }

  void _clearMeasureSelection() {
    AppHaptics.key();
    setState(() {
      _selectedMeasure = null;
      _measureCount = 1;
    });
  }

  void _applySelectedMeasure({bool showToast = true}) {
    final measure = _selectedMeasure;
    if (measure == null) return;
    final netTotal = measure.grams * _measureCount;
    final targetGrams =
        _isGross ? Ingredient.grossFromNet(netTotal, _wastePct) : netTotal;
    if (targetGrams == null ||
        !targetGrams.isFinite ||
        targetGrams < .1 ||
        targetGrams > 9999999) {
      AppHaptics.warn();
      return;
    }
    final formattedTarget = CalculationEngine.formatGrams(targetGrams);
    setState(() {
      _currentInput = formattedTarget;
      _isFreshInput = true;
    });
    if (!showToast) return;
    final netStr = CalculationEngine.formatGrams(netTotal);
    if (_isGross) {
      _showDelta(
          '← ${measure.name} × $_measureCount ($netStr г нетто → $formattedTarget г брутто)');
    } else {
      _showDelta('✓ ${measure.name} × $_measureCount · $netStr г нетто');
    }
  }

  static final RegExp _potatoPattern =
      RegExp(r'(?:^|[\s,(])картофел[ьяюе]?(?:$|[\s,)])');
  static final RegExp _vegPattern = RegExp(
    r'(?:^|[\s,(])(?:морков[ьию]?|свекл[аыуеой]?|капуст[аыуеой]?)(?:$|[\s,)])',
  );
  static final RegExp _onionPattern =
      RegExp(r'(?:^|[\s,(])лук(?:а|у|ом|е)?(?:$|[\s,)])');

  List<(String, double, bool)> _getSeasonalPresets() {
    if (widget.product.isDishOnly) return const [];
    final name = widget.product.name.toLowerCase().replaceAll('ё', 'е');
    if (_potatoPattern.hasMatch(name)) {
      return const [
        ('До 1 янв', 25.0, false),
        ('С 1 янв', 30.0, false),
        ('С 1 мар', 35.0, false),
        ('С 25 апр', 40.0, false),
        ('Молодой', 20.0, true),
      ];
    } else if (_vegPattern.hasMatch(name)) {
      return const [
        ('До 1 янв', 20.0, false),
        ('С 1 янв', 25.0, false),
      ];
    } else if (_onionPattern.hasMatch(name) &&
        !name.contains('зелен') &&
        !name.contains('порей') &&
        !name.contains('шалот')) {
      return const [
        ('ГОСТ', 16.0, false),
      ];
    }
    return const [];
  }

  void _commitPendingChangesBeforeAction() {
    if (!widget.isEditing) return;
    final parsedGrams = CalculationEngine.parseInputDouble(_currentInput);
    final canCommitGrams = parsedGrams != null &&
        parsedGrams.isFinite &&
        parsedGrams >= .1 &&
        parsedGrams <= CalculationValidation.maxCustomYieldGrams;
    final effectiveWasteChanged = _wastePct != widget.product.wastePct;
    if (effectiveWasteChanged) {
      widget.onProductUpdated
          ?.call(widget.product.copyWith(wastePct: _wastePct));
    }
    final weightOrModeChanged = !_isFreshInput ||
        _isGross != widget.initialIsGross ||
        (canCommitGrams &&
            (parsedGrams - widget.initialGrams).abs() >= 0.001);
    if (canCommitGrams && (weightOrModeChanged || effectiveWasteChanged)) {
      widget.onConfirm(parsedGrams, _isGross);
    }
  }

  void _deleteFromDish() {
    AppHaptics.error();
    widget.onDelete?.call();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _replaceProduct() {
    AppHaptics.key();
    _commitPendingChangesBeforeAction();
    final cb = widget.onReplaceProduct;
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    cb?.call();
  }

  void _confirm(double parsedGrams) {
    AppHaptics.commit();
    final effectiveProduct = _wastePct != widget.product.wastePct
        ? widget.product.copyWith(wastePct: _wastePct)
        : widget.product;
    if (_wastePct != widget.product.wastePct) {
      widget.onProductUpdated?.call(effectiveProduct);
    }
    widget.onConfirm(parsedGrams, _isGross);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final parsedGrams =
        CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final parsedWaste =
        _isEditingWaste ? CalculationEngine.parseInputDouble(_wasteInput) : null;
    final hasWaste = _wastePct > 0;

    double netGrams = parsedGrams;
    if (_isGross) {
      netGrams = Ingredient.netFromGross(parsedGrams, _wastePct);
    }

    final seasonalPresets = _getSeasonalPresets();
    final canConfirm = _isEditingWaste
        ? (parsedWaste != null &&
            parsedWaste.isFinite &&
            parsedWaste >= 0 &&
            parsedWaste < 100)
        : (parsedGrams >= .1 && parsedGrams <= 9999999);
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final sideBySide = AppLayout.canSideBySideNumpad(
      media.width,
      media.height,
      textScale,
    );

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (sideBySide && constraints.maxWidth >= 540) {
              final rightWidth =
                  (constraints.maxWidth * 0.52).clamp(260.0, 340.0).toDouble();
              final quickItems = _quickItemsForCurrentMode();
              final intro = _buildIntro(
                p,
                seasonalPresets,
                netGrams,
                hasWaste,
                compactPane: true,
              );
              final leftPane = constraints.hasBoundedHeight
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: intro),
                        const SizedBox(height: Space.x1),
                        _NumpadQuickRow(quickItems: quickItems, compact: true),
                        const SizedBox(height: Space.x1),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        const SizedBox(height: Space.x1),
                        _NumpadQuickRow(quickItems: quickItems, compact: true),
                        const SizedBox(height: Space.x1),
                      ],
                    );
              final keypad = _buildKeypadBlock(
                p,
                canConfirm,
                parsedGrams,
                compactLandscape: true,
                showQuickRow: false,
              );
              if (constraints.hasBoundedHeight) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: leftPane),
                    Container(width: 1, color: p.divider),
                    SizedBox(
                      width: rightWidth,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: keypad,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftPane),
                  Container(width: 1, color: p.divider),
                  SizedBox(width: rightWidth, child: keypad),
                ],
              );
            }
            return AdaptiveHost(
              body: _buildIntro(p, seasonalPresets, netGrams, hasWaste),
              stickyFooter: _buildKeypadBlock(p, canConfirm, parsedGrams),
            );
          },
        ),
      ),
    );
  }

  /// Верхняя (справочная) часть: заголовок, единица, число, нормы отходов.
  /// Всегда в скролле — поэтому не может переполнить экран.
  Widget _buildIntro(
    Palette p,
    List<(String, double, bool)> seasonalPresets,
    double net,
    bool hasWaste, {
    bool compactPane = false,
  }) {
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final tightPortrait = !compactPane &&
        (media.height < 640 || AppLayout.isLargeText(textScale));
    final tightContent = compactPane || tightPortrait;
    final hasExtras = seasonalPresets.isNotEmpty ||
        widget.product.calculationMeasures.isNotEmpty;
    final showExtras = hasExtras && _showExtrasExpanded;
    final gap = tightPortrait ? Space.x1 : Space.x3;
    final horizontalPad = tightPortrait ? Space.x3 : Space.x4;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPad,
        tightPortrait ? 0 : Space.x1,
        horizontalPad,
        tightPortrait ? Space.x1 : Space.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p, compact: tightContent),
          SizedBox(height: tightPortrait ? Space.x1 : gap),
          _buildModeSelector(p, compact: tightContent),
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.ease,
            alignment: Alignment.topCenter,
            child: (_deltaNote != null && !_isEditingWaste)
                ? Padding(
                    padding: EdgeInsets.only(
                      top: tightPortrait ? Space.x1 : Space.x2,
                    ),
                    child: _buildDeltaNote(p),
                  )
                : const SizedBox.shrink(),
          ),
          SizedBox(height: tightPortrait ? Space.x1 : gap),
          _buildReadout(p, net, hasWaste, tight: tightContent),
          if (hasExtras) ...[
            const SizedBox(height: Space.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('numpad-extras-toggle'),
                onPressed: () {
                  AppHaptics.toggle();
                  setState(() => _showExtrasExpanded = !_showExtrasExpanded);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                ),
                icon: Icon(
                  _showExtrasExpanded
                      ? Icons.expand_less_rounded
                      : Icons.tune_rounded,
                  size: IconSizes.xs,
                ),
                label: Text(
                  _showExtrasExpanded ? 'Скрыть меры и сезон' : 'Меры и сезон',
                ),
              ),
            ),
          ],
          if (showExtras) ...[
            SizedBox(height: Space.x2),
            if (seasonalPresets.isNotEmpty) ...[
              _buildSectionLabel(p, 'Отходы по сезону'),
              const SizedBox(height: Space.x2),
              _buildWasteChips(p, seasonalPresets),
              const SizedBox(height: Space.x3),
            ],
            if (widget.product.calculationMeasures.isNotEmpty) ...[
              _buildSectionLabel(p, 'Бытовые меры'),
              const SizedBox(height: Space.x2),
              _buildMeasures(p),
            ],
          ],
        ],
      ),
    );
  }

  List<_QuickItem> _quickItemsForCurrentMode() {
    return _isEditingWaste
        ? <_QuickItem>[
            (
              label: '0%',
              semanticsLabel: 'Установить отходы 0%',
              onTap: () => _applyWastePreset('0'),
            ),
            (
              label: '15%',
              semanticsLabel: 'Установить отходы 15%',
              onTap: () => _applyWastePreset('15'),
            ),
            (
              label: '25%',
              semanticsLabel: 'Установить отходы 25%',
              onTap: () => _applyWastePreset('25'),
            ),
            (
              label: '35%',
              semanticsLabel: 'Установить отходы 35%',
              onTap: () => _applyWastePreset('35'),
            ),
          ]
        : <_QuickItem>[
            (
              label: '+10 г',
              semanticsLabel: 'Прибавить 10 г',
              onTap: () => _onAdd(10),
            ),
            (
              label: '+50 г',
              semanticsLabel: 'Прибавить 50 г',
              onTap: () => _onAdd(50),
            ),
            (
              label: '+100 г',
              semanticsLabel: 'Прибавить 100 г',
              onTap: () => _onAdd(100),
            ),
            (
              label: '+250 г',
              semanticsLabel: 'Прибавить 250 г',
              onTap: () => _onAdd(250),
            ),
          ];
  }

  /// Нижний блок: ряд прибавок + кейпад с клавишами сброса и подтверждения.
  /// Прижат к нижней кромке — под большой палец.
  Widget _buildKeypadBlock(
    Palette p,
    bool canConfirm,
    double parsedGrams, {
    bool compactLandscape = false,
    bool showQuickRow = true,
  }) {
    final quickItems = _quickItemsForCurrentMode();
    final confirmLabel = _isEditingWaste
        ? 'Готово'
        : (widget.isEditing ? 'Сохранить' : 'Добавить');

    return _NumpadKeypadBlock(
      quickItems: quickItems,
      confirmLabel: confirmLabel,
      canConfirm: canConfirm,
      confirmMaterialKey: _isEditingWaste
          ? const ValueKey('waste-edit-done')
          : const ValueKey('numpad-confirm'),
      compactLandscape: compactLandscape,
      showQuickRow: showQuickRow,
      onKey: _onKey,
      onBackspace: _onBackspace,
      onClear: _onClear,
      onConfirm: () =>
          _isEditingWaste ? _confirmWasteEdit() : _confirm(parsedGrams),
    );
  }

  Widget _buildHeader(Palette p, {bool compact = false}) {
    final canPop = Navigator.canPop(context);
    final hasEditActions = widget.isEditing &&
        (widget.onEditLoss != null ||
            widget.onReplaceProduct != null ||
            widget.onAddAsNewRow != null ||
            widget.onDelete != null);
    final calcKcal = UiFormat.productKcal(widget.product);
    final sourceNote = UiFormat.sourceKcalFootnote(widget.product);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.name,
                style: (compact ? AppTypography.headline : AppTypography.title)
                    .copyWith(color: p.ink),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!compact) ...[
                const SizedBox(height: Space.x1),
                Text(
                  '${CalculationEngine.formatKcal(calcKcal)} ккал / 100 г · ${SourceLabel.of(widget.product.source, fallback: widget.product.source)}',
                  style: AppTypography.caption.copyWith(color: p.inkMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (sourceNote != null)
                  Text(
                    sourceNote,
                    style: AppTypography.caption.copyWith(color: p.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ],
          ),
        ),
        if (hasEditActions) ...[
          const SizedBox(width: Space.x1),
          PopupMenuButton<String>(
            key: const ValueKey('numpad-more-btn'),
            tooltip: 'Действия с ингредиентом',
            icon: Icon(Icons.more_vert_rounded, color: p.inkSecondary),
            onSelected: (value) {
              if (value == 'loss') {
                AppHaptics.toggle();
                _commitPendingChangesBeforeAction();
                widget.onEditLoss?.call();
              } else if (value == 'replace') {
                _replaceProduct();
              } else if (value == 'add_new') {
                final parsed =
                    CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
                if (parsed >= .1 &&
                    parsed <= CalculationValidation.maxCustomYieldGrams) {
                  AppHaptics.commit();
                  if (_wastePct != widget.product.wastePct) {
                    widget.onProductUpdated
                        ?.call(widget.product.copyWith(wastePct: _wastePct));
                  }
                  widget.onAddAsNewRow?.call(parsed, _isGross);
                  if (mounted && Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                }
              } else if (value == 'delete') {
                _deleteFromDish();
              }
            },
            itemBuilder: (_) => [
              if (widget.onEditLoss != null)
                const PopupMenuItem<String>(
                  key: ValueKey('numpad-edit-loss'),
                  value: 'loss',
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: IconSizes.btn),
                      SizedBox(width: Space.x2),
                      Expanded(child: Text('Группа и обработка')),
                    ],
                  ),
                ),
              if (widget.onReplaceProduct != null)
                const PopupMenuItem<String>(
                  key: ValueKey('numpad-replace-product'),
                  value: 'replace',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: IconSizes.btn),
                      SizedBox(width: Space.x2),
                      Expanded(child: Text('Заменить продукт')),
                    ],
                  ),
                ),
              if (widget.onAddAsNewRow != null)
                const PopupMenuItem<String>(
                  key: ValueKey('numpad-add-new-row'),
                  value: 'add_new',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_rounded, size: IconSizes.btn),
                      SizedBox(width: Space.x2),
                      Expanded(child: Text('Добавить ещё строкой')),
                    ],
                  ),
                ),
              if (widget.onDelete != null)
                PopupMenuItem<String>(
                  key: const ValueKey('numpad-delete'),
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: IconSizes.btn,
                        color: p.danger,
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Text(
                          'Удалить из блюда',
                          style: TextStyle(color: p.danger),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (canPop) ...[
          const SizedBox(width: Space.x1),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Закрыть',
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            icon: Icon(
              Icons.close_rounded,
              size: IconSizes.md,
              color: p.inkSecondary,
            ),
          ),
        ] else if (!hasEditActions && !compact) ...[
          const SizedBox(width: Space.x2),
          SourceBadge(source: widget.product.source, compact: true),
        ],
      ],
    );
  }

  Widget _buildModeSelector(Palette p, {bool compact = false}) {
    final semanticsHint = _isGross
        ? 'Ввод массы брутто · переключение Брутто/Нетто'
        : 'Ввод чистой массы нетто · переключение Брутто/Нетто';
    final isCompact =
        compact || AppLayout.isCompact(MediaQuery.sizeOf(context).width);
    final baseStyle = AppSegmentedStyle.of(p, compact: isCompact);
    final resolvedStyle = compact
        ? baseStyle.copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x1),
            ),
          )
        : baseStyle;
    return Semantics(
      label: semanticsHint,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: resolvedStyle,
          segments: const [
            ButtonSegment(
              value: true,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Брутто',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ButtonSegment(
              value: false,
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Нетто',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          selected: {_isGross},
          onSelectionChanged: (value) => _setMode(value.single),
        ),
      ),
    );
  }

  Widget _buildDeltaNote(Palette p) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: Radii.fieldAll,
      ),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, size: IconSizes.xs, color: p.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(
              _deltaNote ?? '',
              style: AppTypography.numSm.copyWith(
                color: p.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadout(
    Palette p,
    double net,
    bool hasWaste, {
    bool tight = false,
  }) {
    final displayText = _isEditingWaste ? _wasteInput : _currentInput;
    final isFresh = _isEditingWaste ? _isFreshWasteInput : _isFreshInput;
    final unit = _isEditingWaste ? '%' : 'г';
    final safeNet = (net.isFinite && net > 0) ? net : 0.0;

    return WeightReadout(
      valueText: displayText,
      unit: unit,
      isFresh: isFresh,
      tight: tight,
      onClear: _onClear,
      headerNote: _isEditingWaste
          ? 'Процент отходов при обработке (0–99,9\u202F%)'
          : null,
      freshHint: (isFresh && !_isEditingWaste && !tight)
          ? 'цифра заменит значение · +г прибавит'
          : null,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEditingWaste)
            _buildWasteEditCaption(p)
          else ...[
            _buildLiveCaption(p, net, hasWaste, tight: tight),
            SizedBox(height: tight ? Space.x1 : Space.x2),
            _buildLiveMacrosRow(p, safeNet),
          ],
        ],
      ),
    );
  }

  Widget _buildWasteEditCaption(Palette p) {
    return Semantics(
      liveRegion: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.x2,
        runSpacing: Space.x1,
        children: [
          Text(
            _wasteError ?? 'масса: $_currentInput г · нажмите «Готово»',
            textAlign: TextAlign.center,
            style: AppTypography.numSm.copyWith(
              color: _wasteError != null ? p.slabDanger : p.slabSecondary,
            ),
          ),
          TextButton(
            key: const ValueKey('waste-edit-cancel'),
            onPressed: _toggleWasteEdit,
            style: TextButton.styleFrom(
              foregroundColor: p.slabAccent,
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            ),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCaption(
    Palette p,
    double net,
    bool hasWaste, {
    bool tight = false,
  }) {
    final String text;
    final bool ok;
    if (_isGross && hasWaste) {
      text = '✓ съедобная часть ${CalculationEngine.formatGrams(net)} г';
      ok = true;
    } else if (_isGross) {
      text = 'отходы не заданы — брутто равно нетто';
      ok = false;
    } else {
      text = '✓ чистая масса нетто';
      ok = true;
    }
    return Semantics(
      liveRegion: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.x1,
        runSpacing: Space.x1,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: (tight ? AppTypography.caption : AppTypography.numSm)
                .copyWith(
              color: ok ? p.slabSecondary : p.slabWarning,
            ),
          ),
          if (hasWaste || _isGross)
            TextButton(
              key: const ValueKey('waste-edit-toggle'),
              onPressed: _toggleWasteEdit,
              style: TextButton.styleFrom(
                foregroundColor: p.slabAccent,
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                padding: EdgeInsets.symmetric(
                  horizontal: tight ? Space.x1 : Space.x2,
                ),
                textStyle: tight ? AppTypography.caption : null,
              ),
              child: Text(
                'отходы ${CalculationEngine.formatWastePercent(_wastePct)} % · изменить',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveMacrosRow(Palette p, double safeNet) {
    final roundedNet = safeNet > 0 ? CalculationMath.round1(safeNet) : 0.0;
    final protein = CalculationMath.productRounded(
      widget.product.protein,
      roundedNet,
      2,
      divideBy100: true,
    );
    final fat = CalculationMath.productRounded(
      widget.product.fat,
      roundedNet,
      2,
      divideBy100: true,
    );
    final carbs = CalculationMath.productRounded(
      widget.product.carbs,
      roundedNet,
      2,
      divideBy100: true,
    );
    final kcal = CalculationMath.energy(protein, fat, carbs);
    final cells = <Widget>[
      InlineMacroCell(
        type: NutrientType.protein,
        value: CalculationEngine.formatMacro(protein),
        compact: true,
        onDarkSlab: true,
      ),
      InlineMacroCell(
        type: NutrientType.fat,
        value: CalculationEngine.formatMacro(fat),
        compact: true,
        onDarkSlab: true,
      ),
      InlineMacroCell(
        type: NutrientType.carbs,
        value: CalculationEngine.formatMacro(carbs),
        compact: true,
        onDarkSlab: true,
      ),
      InlineMacroCell(
        type: NutrientType.kcal,
        value: CalculationEngine.formatKcal(kcal),
        compact: true,
        onDarkSlab: true,
      ),
    ];
    return Wrap(
      key: const ValueKey('numpad-live-macros'),
      alignment: WrapAlignment.center,
      spacing: Space.x3,
      runSpacing: Space.x1,
      children: cells,
    );
  }

  Widget _buildSectionLabel(Palette p, String text) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: p.inkMuted,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildWasteChips(Palette p, List<(String, double, bool)> presets) {
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: presets.map((preset) {
        final isSelected = (_wastePct - preset.$2).abs() < 0.01;
        final pctLabel =
            '${CalculationEngine.formatWastePercent(preset.$2)} %';
        return _TapChip(
          key: ValueKey('waste-${preset.$1}'),
          selected: isSelected,
          accent: p.accent,
          label: preset.$1,
          trailing: pctLabel,
          season: preset.$3,
          semanticsLabel: 'Установить отходы ${preset.$1} $pctLabel',
          onTap: () => _setWastePct(preset.$2),
        );
      }).toList(),
    );
  }

  Widget _buildMeasures(Palette p) {
    final selected = _selectedMeasure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Space.x2,
          runSpacing: Space.x2,
          children: widget.product.calculationMeasures.map((m) {
            return _TapChip(
              key: ValueKey('measure-${m.name}'),
              label: m.name,
              trailing: '${CalculationEngine.formatGrams(m.grams)} г',
              accent: p.accent,
              selected: selected?.name == m.name,
              onTap: () => _selectMeasure(m),
            );
          }).toList(),
        ),
        if (selected != null) ...[
          const SizedBox(height: Space.x2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.x3,
              vertical: Space.x1,
            ),
            decoration: BoxDecoration(
              color: p.sunken,
              borderRadius: Radii.chipAll,
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                Text(
                  '${selected.name} · ${CalculationEngine.formatGrams(selected.grams)} г нетто',
                  style: AppTypography.caption.copyWith(color: p.inkSecondary),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('measure-dec'),
                      onPressed:
                          _measureCount > 1 ? () => _stepMeasureCount(-1) : null,
                      tooltip: 'Уменьшить количество мер',
                      constraints: const BoxConstraints(
                        minWidth: kMinTapTarget,
                        minHeight: kMinTapTarget,
                      ),
                      icon: const Icon(Icons.remove_rounded, size: IconSizes.md),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                      child: Text(
                        '$_measureCount',
                        key: const ValueKey('measure-count-label'),
                        style: AppTypography.num.copyWith(color: p.ink),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('measure-inc'),
                      onPressed:
                          _measureCount < 99 ? () => _stepMeasureCount(1) : null,
                      tooltip: 'Увеличить количество мер',
                      constraints: const BoxConstraints(
                        minWidth: kMinTapTarget,
                        minHeight: kMinTapTarget,
                      ),
                      icon: const Icon(Icons.add_rounded, size: IconSizes.md),
                    ),
                    IconButton(
                      key: const ValueKey('measure-clear'),
                      onPressed: _clearMeasureSelection,
                      tooltip: 'Сбросить выбор меры',
                      constraints: const BoxConstraints(
                        minWidth: kMinTapTarget,
                        minHeight: kMinTapTarget,
                      ),
                      icon: Icon(
                        Icons.close_rounded,
                        size: IconSizes.btn,
                        color: p.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

}

(String next, bool nextFresh) _appendNumpadKeyValue(
  String current,
  bool isFresh,
  String key, {
  required int maxLength,
}) {
  if (key == ',') {
    if (isFresh) return ('0,', false);
    if (!current.contains(',') && !current.contains('.')) {
      return ('$current,', false);
    }
    return (current, false);
  }
  if (isFresh || current == '0') {
    return (key, false);
  }
  if (current.length < maxLength) {
    return ('$current$key', false);
  }
  return (current, false);
}

(String next, bool nextFresh) _backspaceNumpadString(String current) {
  if (current.length > 1) {
    return (current.substring(0, current.length - 1), false);
  }
  return ('0', true);
}

/// Единое приборное табло ввода массы для [CustomNumpadSheet] и
/// [SimpleGramsNumpadSheet] с кнопкой сброса `C` прямо в табло.
class WeightReadout extends StatelessWidget {
  final String valueText;
  final String unit;
  final bool isFresh;
  final bool tight;
  final VoidCallback onClear;
  final String? headerNote;
  final String? freshHint;
  final Widget? footer;

  const WeightReadout({
    super.key,
    required this.valueText,
    required this.unit,
    required this.isFresh,
    required this.onClear,
    this.tight = false,
    this.headerNote,
    this.freshHint,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InstrumentSlab(
      borderRadius: Radii.cardAll,
      padding: EdgeInsets.symmetric(
        horizontal: tight ? Space.x3 : Space.x4,
        vertical: tight ? Space.x1 : Space.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: Text(
                headerNote!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: p.slabAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: kMinTapTarget),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: () {
                    final valuePill = AnimatedContainer(
                      duration: Motion.fast,
                      curve: Motion.ease,
                      padding: EdgeInsets.symmetric(
                        horizontal: isFresh ? Space.x2 : 0,
                        vertical: tight ? 0 : Space.x1,
                      ),
                      decoration: BoxDecoration(
                        color: isFresh ? p.slabSurface : Colors.transparent,
                        borderRadius: Radii.chipAll,
                      ),
                      child: AnimatedSwitcher(
                        duration: Duration.zero,
                        child: Text(
                          valueText,
                          key: ValueKey<String>(valueText),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: tight
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: AppTypography.numLg.copyWith(
                            color: isFresh ? p.slabAccent : p.slabInk,
                          ),
                        ),
                      ),
                    );
                    final unitText = Text(
                      unit,
                      style: AppTypography.title.copyWith(color: p.slabSecondary),
                    );
                    if (tight) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 44),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              valuePill,
                              const SizedBox(width: Space.x1),
                              unitText,
                            ],
                          ),
                        ),
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(child: valuePill),
                        const SizedBox(width: Space.x1),
                        unitText,
                      ],
                    );
                  }(),
                ),
              ),
              SizedBox(
                key: const ValueKey('key-C'),
                width: kMinTapTarget,
                height: kMinTapTarget,
                child: TactilePress(
                  child: MergeSemantics(
                    child: Semantics(
                      button: true,
                      label: 'Сбросить значение',
                      child: Material(
                        color: p.slabSurface,
                        borderRadius: Radii.fieldAll,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onClear,
                          borderRadius: Radii.fieldAll,
                          child: ExcludeSemantics(
                            child: Center(
                              child: Text(
                                'C',
                                maxLines: 1,
                                style: AppTypography.headline.copyWith(
                                  color: p.slabDanger,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (freshHint != null) ...[
            const SizedBox(height: Space.x1),
            Text(
              freshHint!,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: p.slabSecondary),
            ),
          ],
          if (footer != null) ...[
            const SizedBox(height: Space.x1),
            footer!,
          ],
        ],
      ),
    );
  }
}

typedef _QuickItem = ({
  String label,
  String semanticsLabel,
  VoidCallback onTap,
});

class _NumpadQuickRow extends StatelessWidget {
  final List<_QuickItem> quickItems;
  final bool compact;

  const _NumpadQuickRow({
    required this.quickItems,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.sizeOf(context);
    final scaler = MediaQuery.textScalerOf(context).scale(1);
    final compactQuick =
        AppLayout.isNarrow(media.width) && AppLayout.isLargeText(scaler);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact || compactQuick ? Space.x2 : Space.x4,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < quickItems.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.x1),
              Expanded(
                child: TactilePress(
                  child: Material(
                    color: p.accentSoft,
                    borderRadius: Radii.fieldAll,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: quickItems[i].onTap,
                      borderRadius: Radii.fieldAll,
                      child: Semantics(
                        button: true,
                        label: quickItems[i].semanticsLabel,
                        child: ExcludeSemantics(
                          child: Container(
                            constraints: const BoxConstraints(
                              minHeight: kMinTapTarget,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.x1,
                              vertical: Space.x1,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                quickItems[i].label,
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: AppTypography.numSm.copyWith(
                                  color: p.accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NumpadKeypadBlock extends StatelessWidget {
  final List<_QuickItem> quickItems;
  final String confirmLabel;
  final bool canConfirm;
  final Key? confirmMaterialKey;
  final bool compactLandscape;
  final bool showQuickRow;
  final void Function(String key) onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onConfirm;

  const _NumpadKeypadBlock({
    required this.quickItems,
    required this.confirmLabel,
    required this.canConfirm,
    this.confirmMaterialKey,
    this.compactLandscape = false,
    this.showQuickRow = true,
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.sizeOf(context);
    final scaler = MediaQuery.textScalerOf(context).scale(1);
    final shortHeight = compactLandscape ||
        media.height < 580 ||
        (media.height < 680 && AppLayout.isLargeText(scaler));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showQuickRow) ...[
          _NumpadQuickRow(quickItems: quickItems, compact: compactLandscape),
          SizedBox(height: shortHeight ? Space.x1 : Space.x2),
        ],
        _buildKeypad(context, p, shortHeight: shortHeight),
      ],
    );
  }

  Widget _buildKeypad(
    BuildContext context,
    Palette p, {
    required bool shortHeight,
  }) {
    const rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['⌫', '0', ','],
    ];
    final scaler = MediaQuery.textScalerOf(context).scale(1);
    final keyGap = (compactLandscape || shortHeight) ? Space.x1 : Space.x2;
    final double keyHeight = shortHeight
        ? kMinTapTarget
        : (48.0 * (scaler > 1.3 ? 1.12 : 1.0))
            .clamp(kMinTapTarget, 52.0)
            .toDouble();
    final confirmHeight = shortHeight ? kMinTapTarget : 56.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compactLandscape ? Space.x2 : Space.x4,
        0,
        compactLandscape ? Space.x2 : Space.x4,
        shortHeight ? Space.x1 : Space.x2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: EdgeInsets.only(bottom: keyGap),
              child: Row(
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) SizedBox(width: keyGap),
                    Expanded(
                      child: _buildKey(p, row[i], keyHeight),
                    ),
                  ],
                ],
              ),
            ),
          _buildConfirmKey(p, confirmHeight, compact: shortHeight),
        ],
      ),
    );
  }

  Widget _buildKey(Palette p, String k, double height) {
    final isBackspace = k == '⌫';
    return SizedBox(
      key: ValueKey('key-$k'),
      height: height,
      child: TactilePress(
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: isBackspace
                ? 'Удалить символ. Долгое нажатие — сброс'
                : (k == ',' ? 'запятая' : k),
            child: Material(
              color: p.isDark ? p.raised : p.sunken,
              borderRadius: Radii.fieldAll,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isBackspace ? onBackspace : () => onKey(k),
                onLongPress: isBackspace ? onClear : null,
                borderRadius: Radii.fieldAll,
                child: ExcludeSemantics(
                  child: Center(
                    child: isBackspace
                        ? Icon(
                            Icons.backspace_outlined,
                            size: IconSizes.md,
                            color: p.ink,
                          )
                        : Text(
                            k,
                            maxLines: 1,
                            style: AppTypography.title.copyWith(color: p.ink),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmKey(
    Palette p,
    double height, {
    bool compact = false,
  }) {
    return Semantics(
      button: true,
      enabled: canConfirm,
      label: confirmLabel,
      child: TactilePress(
        enabled: canConfirm,
        child: Material(
          key: confirmMaterialKey,
          color: canConfirm ? p.accent : p.borderStatic,
          borderRadius: Radii.fieldAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canConfirm ? onConfirm : null,
            child: ExcludeSemantics(
              child: Container(
                constraints: BoxConstraints(minHeight: height),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(
                  horizontal: Space.x4,
                  vertical: compact ? Space.x1 : Space.x2,
                ),
                child: Text(
                  confirmLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppTypography.label.copyWith(
                    color: canConfirm ? p.onAccent : p.inkMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Упрощённый цифровой нумпад для быстрого ввода веса готового блюда одной рукой.
class SimpleGramsNumpadSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double? initialGrams;
  final double minGrams;
  final double maxGrams;
  final void Function(double grams) onConfirm;
  final VoidCallback? onClearValue;

  const SimpleGramsNumpadSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.initialGrams,
    this.minGrams = 1.0,
    this.maxGrams = 9999999.0,
    required this.onConfirm,
    this.onClearValue,
  });

  @override
  State<SimpleGramsNumpadSheet> createState() => _SimpleGramsNumpadSheetState();
}

class _SimpleGramsNumpadSheetState extends State<SimpleGramsNumpadSheet> {
  late String _input;
  bool _isFresh = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialGrams;
    _input = (initial != null && initial > 0)
        ? CalculationEngine.formatGrams(initial)
        : '0';
  }

  void _onKey(String k) {
    AppHaptics.key();
    setState(() {
      final (next, fresh) =
          _appendNumpadKeyValue(_input, _isFresh, k, maxLength: 7);
      _input = next;
      _isFresh = fresh;
    });
  }

  void _onBackspace() {
    AppHaptics.key();
    setState(() {
      final (next, fresh) = _backspaceNumpadString(_input);
      _input = next;
      _isFresh = fresh;
    });
  }

  void _onClear() {
    AppHaptics.error();
    setState(() {
      _input = '0';
      _isFresh = true;
    });
  }

  void _onAdd(double delta) {
    AppHaptics.key();
    final val = CalculationEngine.parseInputDouble(_input) ?? 0.0;
    final next = (val + delta).clamp(widget.minGrams, widget.maxGrams);
    setState(() {
      _input = CalculationEngine.formatGrams(next);
      _isFresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final sideBySide = AppLayout.canSideBySideNumpad(
      media.width,
      media.height,
      textScale,
    );
    final tightPortrait = !sideBySide &&
        (media.height < 640 || AppLayout.isLargeText(textScale));
    final parsed = CalculationEngine.parseInputDouble(_input);
    final canConfirm = parsed != null &&
        parsed.isFinite &&
        parsed >= widget.minGrams &&
        parsed <= widget.maxGrams;

    final bodyPane = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.x4,
        Space.x1,
        Space.x4,
        Space.x3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: AppTypography.title.copyWith(color: p.ink),
                    ),
                    if (widget.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.x1),
                        child: Text(
                          widget.subtitle!,
                          style: AppTypography.caption
                              .copyWith(color: p.inkMuted),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onClearValue != null && widget.initialGrams != null)
                TextButton(
                  onPressed: () {
                    AppHaptics.toggle();
                    widget.onClearValue!();
                    Navigator.pop(context);
                  },
                  child: const Text('Сбросить'),
                ),
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                tooltip: 'Закрыть',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          WeightReadout(
            valueText: _input,
            unit: 'г',
            isFresh: _isFresh,
            tight: tightPortrait,
            onClear: _onClear,
            footer: !canConfirm
                ? Text(
                    'Введите от ${CalculationEngine.formatGrams(widget.minGrams)} '
                    'до ${CalculationEngine.formatGrams(widget.maxGrams)} г',
                    textAlign: TextAlign.center,
                    style: AppTypography.numSm.copyWith(
                      color: p.slabDanger,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );

    final quickItems = <_QuickItem>[
      (
        label: '+10 г',
        semanticsLabel: 'Прибавить 10 г',
        onTap: () => _onAdd(10),
      ),
      (
        label: '+50 г',
        semanticsLabel: 'Прибавить 50 г',
        onTap: () => _onAdd(50),
      ),
      (
        label: '+100 г',
        semanticsLabel: 'Прибавить 100 г',
        onTap: () => _onAdd(100),
      ),
      (
        label: '+250 г',
        semanticsLabel: 'Прибавить 250 г',
        onTap: () => _onAdd(250),
      ),
    ];

    final keypadPane = _NumpadKeypadBlock(
      quickItems: quickItems,
      confirmLabel: 'Применить',
      canConfirm: canConfirm,
      compactLandscape: sideBySide,
      showQuickRow: !sideBySide,
      onKey: _onKey,
      onBackspace: _onBackspace,
      onClear: _onClear,
      onConfirm: () {
        if (!canConfirm) return;
        AppHaptics.commit();
        widget.onConfirm(parsed);
        Navigator.pop(context);
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (sideBySide && constraints.maxWidth >= 540) {
              final rightWidth =
                  (constraints.maxWidth * 0.52).clamp(260.0, 340.0).toDouble();
              final leftPane = constraints.hasBoundedHeight
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: bodyPane),
                        const SizedBox(height: Space.x1),
                        _NumpadQuickRow(quickItems: quickItems, compact: true),
                        const SizedBox(height: Space.x1),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        bodyPane,
                        const SizedBox(height: Space.x1),
                        _NumpadQuickRow(quickItems: quickItems, compact: true),
                        const SizedBox(height: Space.x1),
                      ],
                    );
              return Row(
                crossAxisAlignment: constraints.hasBoundedHeight
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.end,
                children: [
                  Expanded(child: leftPane),
                  Container(width: 1, color: p.divider),
                  SizedBox(
                    width: rightWidth,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: keypadPane,
                    ),
                  ),
                ],
              );
            }
            return AdaptiveHost(
              body: bodyPane,
              stickyFooter: keypadPane,
            );
          },
        ),
      ),
    );
  }
}

/// Чип с высотой 48 dp и одним чётким выделением активного состояния.
class _TapChip extends StatelessWidget {
  final String label;
  final String? trailing;
  final bool selected;
  final bool season;
  final Color accent;
  final String? semanticsLabel;
  final VoidCallback onTap;

  const _TapChip({
    super.key,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.season = false,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      selected: selected,
      label: semanticsLabel,
      child: TactilePress(
        child: Material(
          color: selected ? p.accent : p.sunken,
          borderRadius: Radii.chipAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x3,
                vertical: Space.x1,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (season) ...[
                        Container(
                          width: Space.x1,
                          height: Space.x1,
                          decoration: BoxDecoration(
                            color: selected ? p.onAccent : accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Space.x1),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          style: AppTypography.label.copyWith(
                            color: selected ? p.onAccent : p.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x1),
                      child: Text(
                        trailing!,
                        style: AppTypography.caption.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: selected ? p.onAccent : p.inkSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

