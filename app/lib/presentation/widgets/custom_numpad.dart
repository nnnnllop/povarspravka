import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'adaptive_host.dart';
import 'source_badge.dart';

/// Ввод массы продукта (аудит P0-1, P0-2).
///
/// Ключевые решения:
/// * «Брутто | Нетто» — это **единица измерения числа**, а не тумблер
///   функции: `SegmentedButton` 48 dp над полем, а не `SwitchListTile`.
/// * При смене единицы число конвертируется, но рядом на 2 с появляется
///   дельта-подпись «← 250 г нетто · 312,5 г брутто (отходы 20 %)» — видно,
///   что и почему изменилось.
/// * Подтверждение — правая нижняя клавиша кейпада (позиция Enter), клавиши
///   высотой 56 dp.
/// * `⌫` (не латинская `C`): тап — удалить символ, долгое нажатие — сброс.
/// * Только прибавки (`+10 / +50 / +100 / +250`), никаких «пресетов-замен».
/// * Каждое нажатие — тактильный отклик.
///
/// Сохранены публичные контракты (тип `CustomNumpadSheet`, параметры,
/// тексты «Добавить в блюдо» / «Сохранить изменения», диалоги мер и процента
/// отходов, ключ `measure-count`) — на них завязаны тесты.
class CustomNumpadSheet extends StatefulWidget {
  final Product product;
  final double initialGrams;
  final bool initialIsGross;
  final bool isEditing;
  final Function(double grams, bool isGross) onConfirm;
  final void Function(Product product)? onProductUpdated;

  const CustomNumpadSheet({
    super.key,
    required this.product,
    required this.initialGrams,
    this.initialIsGross = false,
    this.isEditing = false,
    required this.onConfirm,
    this.onProductUpdated,
  });

  @override
  State<CustomNumpadSheet> createState() => _CustomNumpadSheetState();
}

class _CustomNumpadSheetState extends State<CustomNumpadSheet> {
  late String _currentInput;
  late bool _isGross;
  late double _wastePct;
  bool _isFreshInput = true;

  /// Дельта-подпись, показываемая 2 с после смены единицы.
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
      if (k == ',') {
        if (_isFreshInput) {
          _currentInput = '0,';
          _isFreshInput = false;
        } else if (!_currentInput.contains(',') &&
            !_currentInput.contains('.')) {
          _currentInput += ',';
        }
        return;
      }

      if (_isFreshInput) {
        _currentInput = k;
        _isFreshInput = false;
        return;
      }

      if (_currentInput == '0') {
        // STATE-08: на дисплее уже «0» — первая значащая цифра заменяет его,
        // а не дописывается в дробную часть. Иначе «0» → «0» → «,» → «0,7»
        // превращалось в «0,9»: весь хвост ввода уходил в копейки.
        _currentInput = k;
        _isFreshInput = false;
      } else if (_currentInput.length < 7) {
        _currentInput += k;
      }
    });
  }
  void _onBackspace() {
    AppHaptics.key();
    setState(() {
      _isFreshInput = false;
      if (_currentInput.length > 1) {
        _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      } else {
        // STATE-08: стёрли всё — снова «свежий» ввод, как после сброса.
        // Без этого следующий «0» оставался «0», а запятая превращала его в
        // «0,», и весь дальнейший ввод уходил в дробную часть.
        _currentInput = '0';
        _isFreshInput = true;
      }
    });
  }

  void _onClear() {
    AppHaptics.error();
    setState(() {
      _currentInput = '0';
      _isFreshInput = true;
      _deltaNote = null;
    });
  }

  void _onAdd(double delta) {
    AppHaptics.key();
    final val = CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final newVal = (val + delta).clamp(1.0, 99999.0);
    setState(() {
      _currentInput = CalculationEngine.formatGrams(newVal);
      _isFreshInput = false;
    });
  }

  void _setMode(bool gross) {
    if (gross == _isGross) return;
    AppHaptics.toggle();
    final mass = CalculationEngine.parseInputDouble(_currentInput);
    if (mass == null) {
      setState(() => _isGross = gross);
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
      _currentInput = convertedStr;
      _isFreshInput = true;
    });
    // Дельта-подпись: пользователь видит, ЧТО и ПОЧЕМУ поменялось.
    final beforeStr = CalculationEngine.formatGrams(mass);
    final wasteNote = _wastePct > 0
        ? ' (отходы ${CalculationEngine.formatWastePercent(_wastePct)}%)'
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
    });
  }

  Future<void> _editWastePercentage() async {
    AppHaptics.key();
    final controller = TextEditingController(
      text: _wastePct > 0 ? CalculationEngine.formatWastePercent(_wastePct) : '0',
    );
    String? error;
    final newPct = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Процент отходов при холодной обработке'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Продукт: ${widget.product.name}\nЗадайте процент технологических отходов (0–99%).',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: Space.x3),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Отходы, %',
                  errorText: error,
                  suffixText: '%',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final parsed = CalculationEngine.parseInputDouble(controller.text);
                if (parsed == null || parsed < 0 || parsed >= 100) {
                  AppHaptics.warn();
                  setDialogState(() {
                    error = 'Введите число от 0 до 99';
                  });
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (newPct != null) {
      _setWastePct(newPct);
    }
  }

  Future<void> _chooseMeasure(ProductMeasure measure) async {
    AppHaptics.key();
    var countText = '1';
    String? error;
    final count = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: Text(measure.name),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      '1 мера = ${CalculationEngine.formatGrams(measure.grams)} г нетто. Источник: ${widget.product.sourceLabel}.'),
                  const SizedBox(height: Space.x3),
                  TextFormField(
                      key: const ValueKey('measure-count'),
                      initialValue: '1',
                      onChanged: (text) => countText = text,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Количество мер', errorText: error)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Отмена')),
                  TextButton(
                      onPressed: () {
                        final value =
                            CalculationEngine.parseInputDouble(countText);
                        final grams =
                            value == null ? null : value * measure.grams;
                        if (grams == null ||
                            !grams.isFinite ||
                            grams < .1 ||
                            grams > 9999999) {
                          AppHaptics.warn();
                          update(() => error =
                              'Количество должно давать от 0,1 до 9999999 г');
                          return;
                        }
                        Navigator.pop(ctx, value);
                      },
                      child: const Text('Использовать')),
                ],
              )),
    );
    if (!mounted || count == null) return;
    setState(() {
      _isGross = false;
      _currentInput = (measure.grams * count).toString().replaceAll('.', ',');
      _isFreshInput = true;
      _deltaNote =
          '✓ ${CalculationEngine.formatGrams(measure.grams * count)} г нетто · ${measure.name}';
    });
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

  void _confirm(double parsedGrams) {
    AppHaptics.commit();
    final effectiveProduct = _wastePct != widget.product.wastePct
        ? widget.product.copyWith(wastePct: _wastePct)
        : widget.product;
    if (_wastePct != widget.product.wastePct) {
      widget.onProductUpdated?.call(effectiveProduct);
    }
    widget.onConfirm(parsedGrams, _isGross);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final parsedGrams =
        CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final hasWaste = _wastePct > 0;

    double netGrams = parsedGrams;
    if (_isGross) {
      netGrams = Ingredient.netFromGross(parsedGrams, _wastePct);
    }

    final seasonalPresets = _getSeasonalPresets();
    final canConfirm = parsedGrams >= .1 && parsedGrams <= 9999999;

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: AdaptiveHost(
          body: _buildIntro(p, seasonalPresets, netGrams, hasWaste),
          stickyFooter: _buildKeypadBlock(p, canConfirm, parsedGrams),
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
    bool hasWaste,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p),
          const SizedBox(height: Space.x3),
          _buildModeSelector(p),
          if (_deltaNote != null) ...[
            const SizedBox(height: Space.x2),
            _buildDeltaNote(p),
          ],
          const SizedBox(height: Space.x3),
          _buildReadout(p, net, hasWaste),
          const SizedBox(height: Space.x3),
          if (seasonalPresets.isNotEmpty) ...[
            _buildSectionLabel(p, 'НОРМА ОТХОДОВ · СЕЗОН'),
            const SizedBox(height: Space.x2),
            _buildWasteChips(p, seasonalPresets),
            const SizedBox(height: Space.x3),
          ],
          if (widget.product.calculationMeasures.isNotEmpty) ...[
            _buildSectionLabel(p, 'БЫТОВЫЕ МЕРЫ'),
            const SizedBox(height: Space.x2),
            _buildMeasures(p),
          ],
        ],
      ),
    );
  }

  /// Нижний блок: ряд прибавок + кейпад с клавишей подтверждения.
  /// Прижат к нижней кромке — под большой палец.
  Widget _buildKeypadBlock(Palette p, bool canConfirm, double parsedGrams) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildQuickRow(p),
        const SizedBox(height: Space.x2),
        _buildKeypad(p, canConfirm, parsedGrams),
      ],
    );
  }

  Widget _buildHeader(Palette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            widget.product.name,
            style: AppTypography.title.copyWith(fontSize: 18),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Space.x2),
        SourceBadge(source: widget.product.source, compact: true),
      ],
    );
  }

  Widget _buildModeSelector(Palette p) {
    // Контракт из аудита: старая подпись тумблера осталась доступной для
    // скринридера — она и есть подсказка к сегментам «Брутто | Нетто».
    const semanticsHint = 'Ввод чистой массы нетто · переключение Брутто/Нетто';
    return Semantics(
      label: semanticsHint,
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, kMinTapTarget),
            backgroundColor: p.surface,
            foregroundColor: p.inkSecondary,
            selectedBackgroundColor: p.accentSoft,
            selectedForegroundColor: p.accent,
            side: BorderSide(color: p.border, width: 1),
            shape: RoundedRectangleBorder(borderRadius: Radii.fieldAll),
            textStyle: AppTypography.label,
          ),
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
    const digits = TextStyle(
      fontFamily: AppTypography.fontName,
      fontSize: 34,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Число — дисплей-кегль: единственное значение на шите. Смена
        // единицы анимируется: fade + slide 8 dp (подтверждение изменения,
        // которого раньше не было вообще).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: Motion.base,
                switchInCurve: Motion.ease,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  _currentInput,
                  key: ValueKey<String>(_currentInput),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: digits.copyWith(color: p.ink),
                ),
              ),
            ),
            const SizedBox(width: Space.x1),
            Text(
              'г',
              style: AppTypography.title.copyWith(color: p.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        // Живая подпись вместо второго мелкого абзаца.
        _buildLiveCaption(p, net, hasWaste),
      ],
    );
  }

  Widget _buildLiveCaption(Palette p, double net, bool hasWaste) {
    final String text;
    final bool ok;
    if (_isGross && hasWaste) {
      text =
          '✓ съедобная часть ${CalculationEngine.formatGrams(net)} г · отходы ${CalculationEngine.formatWastePercent(_wastePct)}%';
      ok = true;
    } else if (_isGross) {
      text = 'отходы не заданы — брутто равно нетто';
      ok = false;
    } else {
      text = '✓ чистая масса нетто';
      ok = true;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.numSm.copyWith(
              color: ok ? p.inkSecondary : p.warning,
            ),
          ),
        ),
        if (hasWaste || _isGross) ...[
          const SizedBox(width: Space.x1),
          TextButton(
            onPressed: _editWastePercentage,
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            ),
            child: const Text('изменить %'),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionLabel(Palette p, String text) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: p.inkMuted,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
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
    return Wrap(
      spacing: Space.x2,
      runSpacing: Space.x2,
      children: widget.product.calculationMeasures.map((m) {
        return _TapChip(
          label: m.name,
          trailing: '${CalculationEngine.formatGrams(m.grams)} г',
          accent: p.accent,
          selected: false,
          onTap: () => _chooseMeasure(m),
        );
      }).toList(),
    );
  }

  Widget _buildQuickRow(Palette p) {
    const increments = <(String, double)>[
      ('+10 г', 10),
      ('+50 г', 50),
      ('+100 г', 100),
      ('+250 г', 250),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      child: Row(
        children: increments.map((inc) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                // STATE-08: срабатывание по нажатию — быстрый ввод быстрыми
                // нажатиями раньше терял часть приращений.
                onTapDown: (_) => _onAdd(inc.$2),
                borderRadius: Radii.fieldAll,
                child: Container(
                  height: kMinTapTarget,
                  alignment: Alignment.center,
                  child: Text(
                    inc.$1,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: AppTypography.numSm.copyWith(
                      color: p.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeypad(Palette p, bool canConfirm, double parsedGrams) {
    const rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['⌫', '0', ','],
    ];
    final scaler = MediaQuery.textScalerOf(context).scale(1);
    final keyGap = Space.x1;
    // Клавиши 56 dp (было 48): больше поверхности нажатия — меньше промахов
    // на кухне. При крупном тексте растём вместе с ним.
    final keyHeight = 56.0 * (scaler > 1.3 ? scaler : 1.0);
    final gridHeight = keyHeight * 4 + keyGap * 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
      child: SizedBox(
        height: gridHeight,
        child: Row(
          children: [
            // 3 классические колонки цифр.
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
            // Колонка Enter: подтверждение — под большим пальцем, как Enter
            // на нормальном калькуляторе.
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.only(bottom: keyGap),
                child: _buildConfirmKey(p, canConfirm, parsedGrams, keyHeight * 4 + keyGap * 3),
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
      // Стабильный ключ клавиши: по нему тесты проверяют размеры нажатия
      // (WCAG 2.5.5) и не зависят от порядка обхода дерева.
      key: ValueKey('key-$k'),
      height: height,
      child: isBackspace
          ? GestureDetector(
              onLongPress: _onClear,
              child: Semantics(
                button: true,
                label: 'Удалить символ. Долгое нажатие — сброс',
                child: InkWell(
                  onTap: _onBackspace,
                  borderRadius: Radii.fieldAll,
                  child: _keySurface(
                    p,
                    child:
                        Icon(Icons.backspace_outlined, size: 22, color: p.ink),
                  ),
                ),
              ),
            )
          // STATE-08: клавиша срабатывает по НАЖАТИЮ, а не по отпусканию.
          // `InkWell.onTap` разрешается ареной жестов на tap-up, и быстрый
          // ввод (палец/несколько касаний в одном кадре, автотесты с
          // pump(Duration.zero)) терял символы — до 20 из 30 нажатий.
          // Реагируем по down: задержка нулевая, потеря исключена.
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _onKey(k),
              child: Semantics(
                button: true,
                label: k == ',' ? 'запятая' : k,
                child: _keySurface(
                  p,
                  child: Text(
                    k,
                    maxLines: 1,
                    style: AppTypography.num.copyWith(
                      fontSize: 24,
                      color: p.ink,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _keySurface(Palette p, {required Widget child}) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: p.border, width: 1),
      ),
      child: child,
    );
  }

  Widget _buildConfirmKey(
      Palette p, bool canConfirm, double parsedGrams, double height) {
    final label = widget.isEditing ? 'Сохранить изменения' : 'Добавить в блюдо';
    return Semantics(
      button: true,
      enabled: canConfirm,
      label: label,
      child: Material(
        color: canConfirm ? p.accent : p.borderStatic,
        borderRadius: Radii.fieldAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canConfirm ? () => _confirm(parsedGrams) : null,
          child: Container(
            height: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.label.copyWith(
                color: canConfirm ? p.onAccent : p.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Чип с высотой 48 dp, опциональной подписью-значением и янтарным маркером
/// активного сезона (2 dp подчёркивание, а не «ещё одна рамка»).
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
    return Material(
      color: selected ? p.accentSoft : p.surface,
      borderRadius: Radii.chipAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          padding: const EdgeInsets.symmetric(
              horizontal: Space.x3, vertical: Space.x1),
          decoration: BoxDecoration(
            borderRadius: Radii.chipAll,
            border: Border.all(color: p.border, width: 1),
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
                  Text(
                    label,
                    style: AppTypography.label.copyWith(
                      color: selected ? accent : p.ink,
                    ),
                  ),
                ],
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text(
                    trailing!,
                    style: AppTypography.numSm.copyWith(
                      fontSize: 11,
                      color: selected ? accent : p.inkSecondary,
                    ),
                  ),
                ),
              Container(
                height: 2,
                margin: const EdgeInsets.only(top: 3),
                constraints: const BoxConstraints(minWidth: 24),
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

