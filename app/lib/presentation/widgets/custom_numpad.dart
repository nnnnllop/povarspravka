import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'source_badge.dart';

class CustomNumpadSheet extends StatefulWidget {
  final Product product;
  final double initialGrams;
  final bool initialIsGross;
  final bool isEditing;
  final Function(double grams, bool isGross) onConfirm;

  const CustomNumpadSheet({
    super.key,
    required this.product,
    required this.initialGrams,
    this.initialIsGross = false,
    this.isEditing = false,
    required this.onConfirm,
  });

  @override
  State<CustomNumpadSheet> createState() => _CustomNumpadSheetState();
}

class _CustomNumpadSheetState extends State<CustomNumpadSheet> {
  late String _currentInput;
  late bool _isGross;
  bool _isFreshInput = true;

  @override
  void initState() {
    super.initState();
    _currentInput = widget.initialGrams > 0
        ? CalculationEngine.formatGrams(widget.initialGrams)
        : '100';
    _isGross = widget.initialIsGross;
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

  void _setPreset(double grams) {
    setState(() {
      _currentInput = CalculationEngine.formatGrams(grams);
      _isFreshInput = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parsedGrams =
        CalculationEngine.parseInputDouble(_currentInput) ?? 0.0;
    final hasWaste = widget.product.wastePct > 0;

    double netGrams = parsedGrams;
    if (_isGross && hasWaste) {
      netGrams = parsedGrams * (100.0 - widget.product.wastePct) / 100.0;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Полоска хэндла
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Заголовок продукта
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.product.name,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SourceBadge(source: widget.product.source),
                ],
              ),
              const SizedBox(height: 12),

              // Карточка ввода граммов с кнопкой сброса C
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.45),
                    width: 1.5,
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
                            Text(
                              'Съедобная часть: ${CalculationEngine.formatGrams(netGrams)} г (отходы ${widget.product.wastePct.toStringAsFixed(0)}%)',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
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
                            fontSize: 28,
                            color: AppColors.primary,
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
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _onClear,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.kcal.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'C',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.kcal,
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
              const SizedBox(height: 10),

              // Быстрые чипсы граммовки
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickChip('+10 г', () => _onAdd(10)),
                    _buildQuickChip('+50 г', () => _onAdd(50)),
                    _buildQuickChip('+100 г', () => _onAdd(100)),
                    _buildQuickChip('+250 г', () => _onAdd(250)),
                    _buildQuickChip('50 г', () => _setPreset(50)),
                    _buildQuickChip('100 г', () => _setPreset(100)),
                    _buildQuickChip('200 г', () => _setPreset(200)),
                  ],
                ),
              ),

              // Меры из базы (если есть)
              if (widget.product.measures.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: widget.product.measures.map((m) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(
                              '${m.name} (${CalculationEngine.formatGrams(m.grams)}г)'),
                          onPressed: () => _setPreset(m.grams),
                          backgroundColor:
                              isDark ? AppColors.cardDark : Colors.white,
                          labelStyle: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // Переключатель Брутто / Нетто (если у продукта есть процент отходов)
              if (hasWaste) ...[
                const SizedBox(height: 6),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Брутто (с учетом отходов ${widget.product.wastePct.toStringAsFixed(0)}%)',
                    style: AppTypography.bodyMedium.copyWith(fontSize: 13),
                  ),
                  subtitle: Text(
                    _isGross
                        ? 'Ввод в брутто → расчет по нетто'
                        : 'Ввод чистой массы нетто',
                    style: AppTypography.bodySmall,
                  ),
                  value: _isGross,
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => _isGross = val),
                ),
              ],

              const SizedBox(height: 10),

              // Цифровая клавиатура (3x4 с запятой)
              _buildKeypad(isDark),

              const SizedBox(height: 14),

              // Кнопка подтверждения
              ElevatedButton(
                onPressed: parsedGrams > 0
                    ? () {
                        widget.onConfirm(parsedGrams, _isGross);
                        Navigator.pop(context);
                      }
                    : null,
                child: Text(
                  widget.isEditing ? 'Сохранить изменения' : 'Добавить в блюдо',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: AppTypography.bodySmall.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.cardDark
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Text(
                        k,
                        style: AppTypography.titleLarge.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: k == '⌫' ? AppColors.primary : null,
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
