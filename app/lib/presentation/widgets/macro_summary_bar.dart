import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'nutrient_chip.dart';

class MacroSummaryBar extends StatefulWidget {
  final CalculationResult result;
  const MacroSummaryBar({super.key, required this.result});

  @override
  State<MacroSummaryBar> createState() => _MacroSummaryBarState();
}

class _MacroSummaryBarState extends State<MacroSummaryBar> {
  bool _showPer100g = false;
  double _portionGrams = 200;
  String? _portionError;

  String m(double value) => CalculationEngine.formatMacro(value);
  String g(double value) => CalculationEngine.formatGrams(value);
  String k(double value) => CalculationEngine.formatKcal(value);
  String macros(double p, double f, double c) =>
      'Б: ${m(p)} · Ж: ${m(f)} · У: ${m(c)} г';

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Заголовок и кнопка инспектора
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Пищевая ценность готового блюда',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _inspect(context),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Инспектор расчёта', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Переключатель: на всё блюдо vs на 100 г
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                  selectedForegroundColor: isDark ? AppColors.backgroundDark : Colors.white,
                  foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  side: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      'На всё блюдо (${g(r.yieldGrams)} г)',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      'На 100 г готового блюда',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                selected: {_showPer100g},
                onSelectionChanged: (value) => setState(() => _showPer100g = value.single),
              ),
            ),

            const SizedBox(height: 14),

            // 4 пастельные карточки макронутриентов
            LayoutBuilder(builder: (context, constraints) {
              final values = [
                (
                  'Белки',
                  m(_showPer100g ? r.per100gProtein : r.cookedProtein),
                  'г',
                  NutrientType.protein,
                ),
                (
                  'Жиры',
                  m(_showPer100g ? r.per100gFat : r.cookedFat),
                  'г',
                  NutrientType.fat,
                ),
                (
                  'Углеводы',
                  m(_showPer100g ? r.per100gCarbs : r.cookedCarbs),
                  'г',
                  NutrientType.carbs,
                ),
                (
                  'Энергия',
                  k(_showPer100g ? r.per100gKcal : r.cookedKcal),
                  'ккал',
                  NutrientType.kcal,
                ),
              ];

              final columns = constraints.maxWidth < 350 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3
                  ? 2
                  : 4;

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in values)
                    _buildNutrientCard(
                      context: context,
                      width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                      type: v.$4,
                      title: v.$1,
                      value: v.$2,
                      unit: v.$3,
                      isDark: isDark,
                    ),
                ],
              );
            }),

            const SizedBox(height: 14),

            // Сводная технологическая цепочка сырье -> т.о. -> готовое блюдо
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сырье → тепловая обработка → готовое блюдо',
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Сырье (нетто ${g(r.rawTotalWeight)} г): ${macros(r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Сохранность Б / Ж / У: ${CalculationEngine.formatPercent(r.retentionProtein)}% / ${CalculationEngine.formatPercent(r.retentionFat)}% / ${CalculationEngine.formatPercent(r.retentionCarbs)}%${r.retentionProtein == 0.94 && r.retentionFat == 0.88 && r.retentionCarbs == 0.91 ? ' (усреднённые)' : ''}',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'После т.о.: ${k(r.cookedKcal)} ккал на всё блюдо (4Б + 9Ж + 4У)',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),

            // Калькулятор порции
            if (r.yieldGrams > 0) ...[
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('portion-grams'),
                initialValue: '200',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: AppTypography.numeric,
                decoration: InputDecoration(
                  labelText: 'Масса порции, г',
                  errorText: _portionError,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (text) {
                  final v = CalculationEngine.parseInputDouble(text);
                  setState(() {
                    if (v == null || v < .1 || v > 9999999) {
                      _portionError = 'Введите массу от 0,1 до 9999999 г';
                    } else {
                      _portionGrams = v;
                      _portionError = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final p = r.portion(_portionGrams);
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Text(
                    'Порция ${g(_portionGrams)} г: ${macros(p.protein, p.fat, p.carbs)} · ${k(p.kcal)} ккал',
                    key: const ValueKey('portion-result'),
                    style: AppTypography.numericSmall.copyWith(
                      fontSize: 12,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientCard({
    required BuildContext context,
    required double width,
    required NutrientType type,
    required String title,
    required String value,
    required String unit,
    required bool isDark,
  }) {
    final Color bg;
    final Color text;
    final Color border;

    switch (type) {
      case NutrientType.protein:
        bg = isDark ? AppColors.proteinBgDark : AppColors.proteinBgLight;
        text = isDark ? AppColors.proteinTextDark : AppColors.proteinTextLight;
        border = isDark ? AppColors.proteinBorderDark : AppColors.proteinBorderLight;
        break;
      case NutrientType.fat:
        bg = isDark ? AppColors.fatBgDark : AppColors.fatBgLight;
        text = isDark ? AppColors.fatTextDark : AppColors.fatTextLight;
        border = isDark ? AppColors.fatBorderDark : AppColors.fatBorderLight;
        break;
      case NutrientType.carbs:
        bg = isDark ? AppColors.carbsBgDark : AppColors.carbsBgLight;
        text = isDark ? AppColors.carbsTextDark : AppColors.carbsTextLight;
        border = isDark ? AppColors.carbsBorderDark : AppColors.carbsBorderLight;
        break;
      case NutrientType.kcal:
        bg = isDark ? AppColors.kcalBgDark : AppColors.kcalBgLight;
        text = isDark ? AppColors.kcalTextDark : AppColors.kcalTextLight;
        border = isDark ? AppColors.kcalBorderDark : AppColors.kcalBorderLight;
        break;
    }

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: text.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value $unit',
            key: ValueKey('macro-$title'),
            style: AppTypography.numeric.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ],
      ),
    );
  }

  void _inspect(BuildContext context) {
    final r = widget.result;
    final e = YieldExplanation(r.rawTotalWeight, r.yieldGrams);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Инспектор расчёта',
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _buildStepCard(
                title: '1. Сырье — нетто ${g(r.rawTotalWeight)} г',
                content: Text(
                  macros(r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs),
                  style: AppTypography.numeric,
                ),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildStepCard(
                title: '2. Потери при т.о. — применяем сохранность',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in [
                      ('Белки', r.rawTotalProtein, r.retentionProtein, r.cookedProtein),
                      ('Жиры', r.rawTotalFat, r.retentionFat, r.cookedFat),
                      ('Углеводы', r.rawTotalCarbs, r.retentionCarbs, r.cookedCarbs),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${row.$1}: ${m(row.$2)} × ${CalculationEngine.formatPercent(row.$3)}% = ${m(row.$4)} г',
                          style: AppTypography.numeric,
                        ),
                      ),
                  ],
                ),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildStepCard(
                title: '3. Энергетическая ценность после т.о.',
                content: Text(
                  '${m(r.cookedProtein)} × 4 + ${m(r.cookedFat)} × 9 + ${m(r.cookedCarbs)} × 4 = ${k(r.cookedKcal)} ккал',
                  style: AppTypography.numeric,
                ),
                isDark: isDark,
              ),
              const SizedBox(height: 10),
              _buildStepCard(
                title: '4. Выход готового блюда: ${g(r.yieldGrams)} г',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.badge, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(e.description, style: AppTypography.bodySmall),
                    if (r.yieldGrams > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'На 100 г: каждый итог после т.о. × 100 / ${g(r.yieldGrams)}',
                        style: AppTypography.bodySmall,
                      ),
                      Text(
                        '${macros(r.per100gProtein, r.per100gFat, r.per100gCarbs)} · ${k(r.per100gKcal)} ккал',
                        style: AppTypography.numeric,
                      ),
                    ],
                  ],
                ),
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              Text(
                'Сырой состав и готовое блюдо — разные стадии, а не противоречащие значения. Сохранность задаётся в параметрах и не определяет уварку. Округление как в бланке: БЖУ до 0,01 г, энергия до 0,1 ккал; энергия считается по округлённым БЖУ.',
                style: AppTypography.bodySmall.copyWith(
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.primaryLight : AppColors.primary,
                  foregroundColor: isDark ? AppColors.backgroundDark : Colors.white,
                ),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required String title,
    required Widget content,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          content,
        ],
      ),
    );
  }
}
