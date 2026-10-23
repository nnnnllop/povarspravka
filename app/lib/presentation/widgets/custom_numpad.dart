import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'source_badge.dart';

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

  void _onKey(String k) {
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
        _currentInput = k == '0' ? '0' : k;
        _isFreshInput = false;
        return;
      }

      if (_currentInput == '0') {
        _currentInput = k;
      } else if (_currentInput.length < 7) {
        _currentInput += k;
      }
    });
  }

  void _onBackspace() {
    setState(() {
      _isFreshInput = false;
      if (_currentInput.length > 1) {
        _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      } else {
        _currentInput = '0';
      }
    });
  }

  void _onClear() {
    setState(() {
      _currentInput = '0';
      _isFreshInput = true;
    });
  }

  void _onAdd(double delta) {
    final val = CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final newVal = (val + delta).clamp(1.0, 99999.0);
    setState(() {
      _currentInput = CalculationEngine.formatGrams(newVal);
      _isFreshInput = false;
    });
  }

  void _toggleGross(bool value) {
    final mass = CalculationEngine.parseInputDouble(_currentInput);
    if (mass == null) return;
    final converted = value
        ? Ingredient.grossFromNet(mass, _wastePct)
        : Ingredient.netFromGross(mass, _wastePct);
    if (converted == null || !converted.isFinite || converted > 9999999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'При 100% отходов положительное нетто невозможно перевести в брутто.')));
      return;
    }
    setState(() {
      _isGross = value;
      _currentInput = converted.toString().replaceAll('.', ',');
      _isFreshInput = true;
    });
  }

  void _setWastePct(double newPct) {
    setState(() {
      _wastePct = newPct;
    });
  }

  Future<void> _editWastePercentage() async {
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
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  const SizedBox(height: 12),
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
    });
  }

  void _setPreset(double grams) {
    setState(() {
      _currentInput = CalculationEngine.formatGrams(grams);
      _isFreshInput = true;
    });
  }

  List<(String, double)> _getSeasonalPresets() {
    final name = widget.product.name.toLowerCase();
    if (name.contains('картофел')) {
      return const [
        ('До 1 янв (25%)', 25.0),
        ('С 1 янв (30%)', 30.0),
        ('С 1 мар (35%)', 35.0),
        ('С 25 апр (40%)', 40.0),
        ('Молодой (20%)', 20.0),
      ];
    } else if (name.contains('морков') || name.contains('свекл') || name.contains('капуст')) {
      return const [
        ('До 1 янв (20%)', 20.0),
        ('С 1 янв (25%)', 25.0),
      ];
    } else if (name.contains('лук') && !name.contains('зелен')) {
      return const [
        ('ГОСТ (16%)', 16.0),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final parsedGrams =
        CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final hasWaste = _wastePct > 0;

    double netGrams = parsedGrams;
    if (_isGross) {
      netGrams = Ingredient.netFromGross(parsedGrams, _wastePct);
    }

    final seasonalPresets = _getSeasonalPresets();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Полоска хэндла
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Заголовок продукта
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.product.name,
                      style: AppTypography.titleLarge.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SourceBadge(source: widget.product.source, compact: true),
                ],
              ),
              const SizedBox(height: 12),

              // Поле отображения ввода с кнопкой сброса
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isGross
                                ? 'Масса брутто (с отходами)'
                                : 'Масса нетто (чистая)',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                          if (_isGross && hasWaste)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Съедобная часть: ${CalculationEngine.formatGrams(netGrams)} г (отходы ${CalculationEngine.formatWastePercent(_wastePct)}%)',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: isDark ? AppColors.accentLight : AppColors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: _editWastePercentage,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    child: Text(
                                      'изменить %',
                                      style: AppTypography.bodySmall.copyWith(
                                        color: isDark ? AppColors.primaryLight : AppColors.primary,
                                        decoration: TextDecoration.underline,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentInput,
                          style: AppTypography.numericLarge.copyWith(
                            fontSize: 26,
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'г',
                          style: AppTypography.titleMedium.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _onClear,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.kcalBgDark : AppColors.kcalBgLight,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? AppColors.kcalBorderDark : AppColors.kcalBorderLight,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              'C',
                              style: AppTypography.bodySmall.copyWith(
                                color: isDark ? AppColors.kcalTextDark : AppColors.kcalTextLight,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Сезонные нормы отходов по ГОСТ / Марчуку (если доступны для продукта)
              if (seasonalPresets.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      'Нормы отходов (ГОСТ/Марчук):',
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 11,
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: seasonalPresets.map((preset) {
                      final isSelected = (_wastePct - preset.$2).abs() < 0.01;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => _setWastePct(preset.$2),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (isDark ? AppColors.accentDark : AppColors.accentLight)
                                  : (isDark ? AppColors.cardDark : AppColors.backgroundLight),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : (isDark ? AppColors.borderDark : AppColors.borderLight),
                                width: isSelected ? 1.2 : 0.8,
                              ),
                            ),
                            child: Text(
                              preset.$1,
                              style: AppTypography.bodySmall.copyWith(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.accent
                                    : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Быстрые инкременты граммов
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickChip('+10 г', () => _onAdd(10), isDark),
                    _buildQuickChip('+50 г', () => _onAdd(50), isDark),
                    _buildQuickChip('+100 г', () => _onAdd(100), isDark),
                    _buildQuickChip('+250 г', () => _onAdd(250), isDark),
                    _buildQuickChip('50 г', () => _setPreset(50), isDark),
                    _buildQuickChip('100 г', () => _setPreset(100), isDark),
                    _buildQuickChip('200 г', () => _setPreset(200), isDark),
                  ],
                ),
              ),

              // Меры из базы продуктов (если есть)
              if (widget.product.calculationMeasures.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: widget.product.calculationMeasures.map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text('${m.name} (${CalculationEngine.formatGrams(m.grams)}г)'),
                          onPressed: () => _chooseMeasure(m),
                          backgroundColor: isDark ? AppColors.cardDark : AppColors.surfaceLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                              color: isDark ? AppColors.borderDark : AppColors.borderLight,
                            ),
                          ),
                          labelStyle: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // Переключатель Брутто / Нетто
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  hasWaste
                      ? 'Брутто (с учетом отходов ${CalculationEngine.formatWastePercent(_wastePct)}%)'
                      : 'Брутто (отходы не заданы, принято 0 %)',
                  style: AppTypography.bodyMedium.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _isGross
                      ? 'Ввод в брутто → расчет по нетто'
                      : 'Ввод чистой массы нетто',
                  style: AppTypography.bodySmall,
                ),
                value: _isGross,
                activeColor: isDark ? AppColors.primaryLight : AppColors.primary,
                onChanged: _toggleGross,
              ),

              if (_isGross && !hasWaste)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.fatBgDark : AppColors.fatBgLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.fatBorderDark : AppColors.fatBorderLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: isDark ? AppColors.fatTextDark : AppColors.fatTextLight,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'отходы для этого продукта не заданы, принято 0 %',
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark ? AppColors.fatTextDark : AppColors.fatTextLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _editWastePercentage,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Задать %'),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 8),

              // Цифровая клавиатура (3x4 с запятой)
              _buildKeypad(isDark),

              const SizedBox(height: 12),

              // Кнопка подтверждения
              ElevatedButton(
                onPressed: parsedGrams >= .1 && parsedGrams <= 9999999
                    ? () {
                        final effectiveProduct = _wastePct != widget.product.wastePct
                            ? widget.product.copyWith(wastePct: _wastePct)
                            : widget.product;
                        if (_wastePct != widget.product.wastePct) {
                          widget.onProductUpdated?.call(effectiveProduct);
                        }
                        widget.onConfirm(parsedGrams, _isGross);
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                  foregroundColor: isDark ? AppColors.backgroundDark : Colors.white,
                ),
                child: Text(
                  widget.isEditing ? 'Сохранить изменения' : 'Добавить в блюдо',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.numericSmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(bool isDark) {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [',', '0', '⌫'],
    ];

    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      if (k == '⌫') {
                        _onBackspace();
                      } else {
                        _onKey(k);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.cardDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        k,
                        style: AppTypography.titleLarge.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: k == '⌫'
                              ? (isDark ? AppColors.primaryLight : AppColors.primary)
                              : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
