import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/calculation/models/source_label.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'adaptive_host.dart';
import 'app_buttons.dart';
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

  const CustomNumpadSheet({
    super.key,
    required this.product,
    required this.initialGrams,
    this.initialIsGross = false,
    this.isEditing = false,
    required this.onConfirm,
    this.onProductUpdated,
    this.onDelete,
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
        _wasteError = null;
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
        _wasteError = null;
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
    final newVal = (val + delta).clamp(1.0, 99999.0);
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
        _wasteError = 'Введите число от 0 до 99';
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

  List<(String, double, bool)> _getSeasonalPresets() {
    final name = widget.product.name.toLowerCase();
    if (name.contains('картофел')) {
      return const [
        ('До 1 янв', 25.0, false),
        ('С 1 янв', 30.0, false),
        ('С 1 мар', 35.0, false),
        ('С 25 апр', 40.0, false),
        ('Молодой', 20.0, true),
      ];
    } else if (name.contains('морков') ||
        name.contains('свекл') ||
        name.contains('капуст')) {
      return const [
        ('До 1 янв', 20.0, false),
        ('С 1 янв', 25.0, false),
      ];
    } else if (name.contains('лук') && !name.contains('зелен')) {
      return const [
        ('ГОСТ', 16.0, false),
      ];
    }
    return const [];
  }

  void _deleteFromDish() {
    AppHaptics.error();
    widget.onDelete?.call();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
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
    final sideBySide = media.width >= 520 && media.height < 460;

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (sideBySide && constraints.maxWidth >= 520) {
              final rightWidth =
                  (constraints.maxWidth * 0.52).clamp(260.0, 340.0).toDouble();
              final intro = _buildIntro(
                p,
                seasonalPresets,
                netGrams,
                hasWaste,
                compactPane: true,
              );
              final keypad = _buildKeypadBlock(
                p,
                canConfirm,
                parsedGrams,
                compactLandscape: true,
              );
              if (constraints.hasBoundedHeight) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: intro),
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
                  Expanded(child: intro),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p),
          const SizedBox(height: Space.x3),
          _buildModeSelector(p, compact: compactPane),
          if (_deltaNote != null && !_isEditingWaste) ...[
            const SizedBox(height: Space.x2),
            _buildDeltaNote(p),
          ],
          const SizedBox(height: Space.x3),
          _buildReadout(p, net, hasWaste),
          const SizedBox(height: Space.x3),
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
      ),
    );
  }

  /// Нижний блок: ряд прибавок + кейпад с клавишами сброса и подтверждения.
  /// Прижат к нижней кромке — под большой палец.
  Widget _buildKeypadBlock(
    Palette p,
    bool canConfirm,
    double parsedGrams, {
    bool compactLandscape = false,
  }) {
    final quickItems = _isEditingWaste
        ? <(String, VoidCallback)>[
            ('0%', () => _applyWastePreset('0')),
            ('15%', () => _applyWastePreset('15')),
            ('25%', () => _applyWastePreset('25')),
            ('35%', () => _applyWastePreset('35')),
          ]
        : <(String, VoidCallback)>[
            ('+10 г', () => _onAdd(10)),
            ('+50 г', () => _onAdd(50)),
            ('+100 г', () => _onAdd(100)),
            ('+250 г', () => _onAdd(250)),
          ];
    final confirmLabel = _isEditingWaste
        ? 'Готово'
        : (widget.isEditing ? 'Сохранить изменения' : 'Добавить в блюдо');

    return _NumpadKeypadBlock(
      quickItems: quickItems,
      confirmLabel: confirmLabel,
      canConfirm: canConfirm,
      confirmMaterialKey:
          _isEditingWaste ? const ValueKey('waste-edit-done') : null,
      compactLandscape: compactLandscape,
      onKey: _onKey,
      onBackspace: _onBackspace,
      onClear: _onClear,
      onConfirm: () =>
          _isEditingWaste ? _confirmWasteEdit() : _confirm(parsedGrams),
    );
  }

  Widget _buildHeader(Palette p) {
    final canPop = Navigator.canPop(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.name,
                style: AppTypography.title.copyWith(color: p.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${CalculationEngine.formatKcal(widget.product.kcal)} ккал / 100 г · ${SourceLabel.of(widget.product.source, fallback: widget.product.source)}',
                style: AppTypography.caption.copyWith(color: p.inkMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (widget.isEditing && widget.onDelete != null) ...[
          const SizedBox(width: Space.x1),
          IconButton(
            key: const ValueKey('numpad-delete'),
            onPressed: _deleteFromDish,
            tooltip: 'Удалить из блюда',
            constraints: const BoxConstraints(
              minWidth: kMinTapTarget,
              minHeight: kMinTapTarget,
            ),
            icon: Icon(Icons.delete_outline_rounded, size: 22, color: p.danger),
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
            icon: Icon(Icons.close_rounded, size: 22, color: p.inkSecondary),
          ),
        ] else if (!(widget.isEditing && widget.onDelete != null)) ...[
          const SizedBox(width: Space.x2),
          SourceBadge(source: widget.product.source, compact: true),
        ],
      ],
    );
  }

  Widget _buildModeSelector(Palette p, {bool compact = false}) {
    const semanticsHint = 'Ввод чистой массы нетто · переключение Брутто/Нетто';
    final isCompact = compact || MediaQuery.sizeOf(context).width < 380;
    return Semantics(
      label: semanticsHint,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: AppSegmentedStyle.of(p, compact: isCompact),
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Брутто', textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: false,
              label: Text('Нетто', textAlign: TextAlign.center),
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
          Icon(Icons.swap_horiz_rounded, size: 16, color: p.accent),
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

  Widget _buildReadout(Palette p, double net, bool hasWaste) {
    final displayText = _isEditingWaste ? _wasteInput : _currentInput;
    final isFresh = _isEditingWaste ? _isFreshWasteInput : _isFreshInput;
    final unit = _isEditingWaste ? '%' : 'г';
    final safeNet = (net.isFinite && net > 0) ? net : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x4,
        vertical: Space.x3,
      ),
      decoration: BoxDecoration(
        color: p.sunken,
        borderRadius: Radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isEditingWaste)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: Text(
                'Процент отходов при обработке (0–99%)',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: p.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.ease,
                  padding: EdgeInsets.symmetric(
                    horizontal: isFresh ? Space.x2 : 0,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isFresh ? p.accentSoft : Colors.transparent,
                    borderRadius: Radii.chipAll,
                  ),
                  child: AnimatedSwitcher(
                    duration: Duration.zero,
                    child: Text(
                      displayText,
                      key: ValueKey<String>(displayText),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.numLg.copyWith(
                        color: isFresh ? p.accent : p.ink,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.x1),
              Text(
                unit,
                style: AppTypography.title.copyWith(color: p.inkSecondary),
              ),
            ],
          ),
          if (isFresh && !_isEditingWaste) ...[
            const SizedBox(height: 2),
            Text(
              'цифра заменит значение · +г прибавит',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: p.inkMuted),
            ),
          ],
          const SizedBox(height: Space.x1),
          if (_isEditingWaste)
            _buildWasteEditCaption(p)
          else ...[
            _buildLiveCaption(p, net, hasWaste),
            const SizedBox(height: Space.x2),
            _buildLiveMacrosRow(p, safeNet),
          ],
        ],
      ),
    );
  }

  Widget _buildWasteEditCaption(Palette p) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.x2,
      runSpacing: Space.x1,
      children: [
        Text(
          _wasteError ?? 'масса: $_currentInput г · нажмите «Готово»',
          textAlign: TextAlign.center,
          style: AppTypography.numSm.copyWith(
            color: _wasteError != null ? p.danger : p.inkSecondary,
          ),
        ),
        TextButton(
          key: const ValueKey('waste-edit-cancel'),
          onPressed: _toggleWasteEdit,
          style: TextButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          ),
          child: const Text('Отмена'),
        ),
      ],
    );
  }

  Widget _buildLiveCaption(Palette p, double net, bool hasWaste) {
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
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.x1,
      runSpacing: Space.x1,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.numSm.copyWith(
            color: ok ? p.inkSecondary : p.warning,
          ),
        ),
        if (hasWaste || _isGross)
          TextButton(
            key: const ValueKey('waste-edit-toggle'),
            onPressed: _toggleWasteEdit,
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            ),
            child: Text(
              'отходы ${CalculationEngine.formatWastePercent(_wastePct)} % · изменить',
            ),
          ),
      ],
    );
  }

  Widget _buildLiveMacrosRow(Palette p, double safeNet) {
    final kcal = widget.product.kcal * safeNet / 100.0;
    final protein = widget.product.protein * safeNet / 100.0;
    final fat = widget.product.fat * safeNet / 100.0;
    final carbs = widget.product.carbs * safeNet / 100.0;
    final cells = <Widget>[
      InlineMacroCell(
        type: NutrientType.protein,
        value: CalculationEngine.formatMacro(protein),
        compact: true,
      ),
      InlineMacroCell(
        type: NutrientType.fat,
        value: CalculationEngine.formatMacro(fat),
        compact: true,
      ),
      InlineMacroCell(
        type: NutrientType.carbs,
        value: CalculationEngine.formatMacro(carbs),
        compact: true,
      ),
      InlineMacroCell(
        type: NutrientType.kcal,
        value: CalculationEngine.formatKcal(kcal),
        compact: true,
      ),
    ];
    return Wrap(
      key: const ValueKey('numpad-live-macros'),
      alignment: WrapAlignment.center,
      spacing: Space.x3,
      runSpacing: Space.x1,
      children: [
        for (final cell in cells)
          FittedBox(fit: BoxFit.scaleDown, child: cell),
      ],
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
        return _TapChip(
          key: ValueKey('waste-${preset.$1}'),
          selected: isSelected,
          accent: p.accent,
          label: preset.$1,
          trailing: '${CalculationEngine.formatWastePercent(preset.$2)} %',
          season: preset.$3,
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
                      icon: const Icon(Icons.remove_rounded, size: 20),
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
                      icon: const Icon(Icons.add_rounded, size: 20),
                    ),
                    IconButton(
                      key: const ValueKey('measure-clear'),
                      onPressed: _clearMeasureSelection,
                      tooltip: 'Сбросить выбор меры',
                      constraints: const BoxConstraints(
                        minWidth: kMinTapTarget,
                        minHeight: kMinTapTarget,
                      ),
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: p.inkMuted),
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

class _NumpadKeypadBlock extends StatelessWidget {
  final List<(String, VoidCallback)> quickItems;
  final String confirmLabel;
  final bool canConfirm;
  final Key? confirmMaterialKey;
  final bool compactLandscape;
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
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQuickRow(p),
        SizedBox(height: compactLandscape ? Space.x1 : Space.x2),
        _buildKeypad(context, p),
      ],
    );
  }

  Widget _buildQuickRow(Palette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      child: Row(
        children: [
          for (final item in quickItems)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TactilePress(
                  child: Material(
                    color: p.sunken,
                    borderRadius: Radii.chipAll,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTapDown: (_) => item.$2(),
                      borderRadius: Radii.chipAll,
                      child: Container(
                        height: kMinTapTarget,
                        alignment: Alignment.center,
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.x1),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.$1,
                            maxLines: 1,
                            style: AppTypography.numSm.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildKeypad(BuildContext context, Palette p) {
    const rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['⌫', '0', ','],
    ];
    final scaler = MediaQuery.textScalerOf(context).scale(1);
    final shortHeight =
        compactLandscape || MediaQuery.sizeOf(context).height < 520;
    final keyGap = compactLandscape ? 2.0 : Space.x1;
    final double keyHeight = shortHeight
        ? kMinTapTarget
        : (52.0 * (scaler > 1.3 ? 1.15 : 1.0))
            .clamp(kMinTapTarget, 62.0)
            .toDouble();
    final gridHeight = keyHeight * 4 + keyGap * 4;
    final confirmHeight = keyHeight * 3 + keyGap * 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compactLandscape ? Space.x2 : Space.x3,
        0,
        compactLandscape ? Space.x2 : Space.x3,
        compactLandscape ? Space.x1 : Space.x2,
      ),
      child: SizedBox(
        height: gridHeight,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  for (final row in rows)
                    Padding(
                      padding: EdgeInsets.only(bottom: keyGap),
                      child: Row(
                        children: [
                          for (final k in row)
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: _buildKey(p, k, keyHeight),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.x1),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: keyGap),
                    child: _buildClearKey(p, keyHeight),
                  ),
                  _buildConfirmKey(p, confirmHeight),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(Palette p, String k, double height) {
    final isBackspace = k == '⌫';
    return SizedBox(
      key: ValueKey('key-$k'),
      height: height,
      child: TactilePress(
        child: Semantics(
          button: true,
          label: isBackspace
              ? 'Удалить символ. Долгое нажатие — сброс'
              : (k == ',' ? 'запятая' : k),
          child: Material(
            color: p.sunken,
            borderRadius: Radii.fieldAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTapDown: (_) => isBackspace ? onBackspace() : onKey(k),
              onLongPress: isBackspace ? onClear : null,
              borderRadius: Radii.fieldAll,
              child: Center(
                child: isBackspace
                    ? Icon(Icons.backspace_outlined, size: 22, color: p.ink)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
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
    );
  }

  Widget _buildClearKey(Palette p, double height) {
    return SizedBox(
      key: const ValueKey('key-C'),
      height: height,
      child: TactilePress(
        child: Semantics(
          button: true,
          label: 'Сбросить значение',
          child: Material(
            color: p.sunken,
            borderRadius: Radii.fieldAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTapDown: (_) => onClear(),
              borderRadius: Radii.fieldAll,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'C',
                    maxLines: 1,
                    style: AppTypography.title.copyWith(color: p.danger),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmKey(Palette p, double height) {
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
            child: Container(
              height: height,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              child: Text(
                confirmLabel,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(
                  color: canConfirm ? p.onAccent : p.inkMuted,
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
    final next = (val + delta).clamp(widget.minGrams, 99999.0);
    setState(() {
      _input = CalculationEngine.formatGrams(next);
      _isFresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final parsed = CalculationEngine.parseInputDouble(_input);
    final canConfirm = parsed != null &&
        parsed.isFinite &&
        parsed >= widget.minGrams &&
        parsed <= widget.maxGrams;

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.sheetTop,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Space.x4, Space.x1, Space.x1, Space.x2),
                child: Row(
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
                            Text(
                              widget.subtitle!,
                              style: AppTypography.caption
                                  .copyWith(color: p.inkMuted),
                            ),
                        ],
                      ),
                    ),
                    if (widget.onClearValue != null &&
                        widget.initialGrams != null)
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x4,
                    vertical: Space.x3,
                  ),
                  decoration: BoxDecoration(
                    color: p.sunken,
                    borderRadius: Radii.cardAll,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          _input,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.numLg.copyWith(
                            color: _isFresh ? p.accent : p.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.x1),
                      Text(
                        'г',
                        style: AppTypography.title.copyWith(
                          color: p.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.x3),
              _NumpadKeypadBlock(
                quickItems: [
                  ('+10 г', () => _onAdd(10)),
                  ('+50 г', () => _onAdd(50)),
                  ('+100 г', () => _onAdd(100)),
                  ('+250 г', () => _onAdd(250)),
                ],
                confirmLabel: 'Применить',
                canConfirm: canConfirm,
                compactLandscape: MediaQuery.sizeOf(context).height < 460,
                onKey: _onKey,
                onBackspace: _onBackspace,
                onClear: _onClear,
                onConfirm: () {
                  if (!canConfirm) return;
                  AppHaptics.commit();
                  widget.onConfirm(parsed);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
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
  final VoidCallback onTap;

  const _TapChip({
    super.key,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.season = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TactilePress(
      child: Material(
        color: selected ? p.accentSoft : p.sunken,
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
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: AppTypography.label.copyWith(
                          color: selected ? accent : p.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      trailing!,
                      style: AppTypography.caption.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: selected ? accent : p.inkSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

