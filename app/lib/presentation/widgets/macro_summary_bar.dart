import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_typography.dart';

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
    return Card(
      child: InkWell(
          onTap: () => _inspect(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Пищевая ценность готового блюда',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: theme.colorScheme.primary,
                            selectedForegroundColor:
                                theme.colorScheme.onPrimary,
                            side: BorderSide(color: theme.colorScheme.primary),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12)),
                        segments: [
                          ButtonSegment(
                              value: false,
                              label: Text('На всё блюдо (${g(r.yieldGrams)} г)',
                                  textAlign: TextAlign.center)),
                          const ButtonSegment(
                              value: true,
                              label: Text('На 100 г готового блюда',
                                  textAlign: TextAlign.center)),
                        ],
                        selected: {_showPer100g},
                        onSelectionChanged: (value) =>
                            setState(() => _showPer100g = value.single),
                      )),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    final values = [
                      (
                        'Белки',
                        m(_showPer100g ? r.per100gProtein : r.cookedProtein),
                        'г'
                      ),
                      (
                        'Жиры',
                        m(_showPer100g ? r.per100gFat : r.cookedFat),
                        'г'
                      ),
                      (
                        'Углеводы',
                        m(_showPer100g ? r.per100gCarbs : r.cookedCarbs),
                        'г'
                      ),
                      (
                        'Энергия',
                        k(_showPer100g ? r.per100gKcal : r.cookedKcal),
                        'ккал'
                      ),
                    ];
                    final columns = constraints.maxWidth < 350 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? 2
                        : 4;
                    return Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final v in values)
                        Container(
                          width: (constraints.maxWidth - (columns - 1) * 8) /
                              columns,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withOpacity(.35),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.$1, style: theme.textTheme.bodyMedium),
                                const SizedBox(height: 4),
                                Text('${v.$2} ${v.$3}',
                                    key: ValueKey('macro-${v.$1}'),
                                    style: AppTypography.numeric.copyWith(
                                        fontSize: 16,
                                        color: theme.colorScheme.onSurface)),
                              ]),
                        ),
                    ]);
                  }),
                  const SizedBox(height: 12),
                  Text('Сырье → тепловая обработка → готовое блюдо',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                      'Сырье (нетто ${g(r.rawTotalWeight)} г): ${macros(r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs)}',
                      style: theme.textTheme.bodyMedium),
                  Text(
                      'Сохранность Б / Ж / У: ${CalculationEngine.formatPercent(r.retentionProtein)}% / ${CalculationEngine.formatPercent(r.retentionFat)}% / ${CalculationEngine.formatPercent(r.retentionCarbs)}%${r.retentionProtein == 94 && r.retentionFat == 88 && r.retentionCarbs == 91 ? ' (усреднённые)' : ''}',
                      style: theme.textTheme.bodyMedium),
                  Text(
                      'После т.о.: ${k(r.cookedKcal)} ккал на всё блюдо (4Б + 9Ж + 4У)',
                      style: theme.textTheme.bodyMedium),
                  if (r.yieldGrams > 0) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('portion-grams'),
                      initialValue: '200',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Масса порции, г',
                          errorText: _portionError),
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
                    Builder(builder: (_) {
                      final p = r.portion(_portionGrams);
                      return Text(
                          'Порция ${g(_portionGrams)} г: ${macros(p.protein, p.fat, p.carbs)} · ${k(p.kcal)} ккал',
                          key: const ValueKey('portion-result'));
                    }),
                  ],
                  TextButton.icon(
                      onPressed: () => _inspect(context),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Инспектор расчёта')),
                ]),
          )),
    );
  }

  void _inspect(BuildContext context) {
    final r = widget.result;
    final e = YieldExplanation(r.rawTotalWeight, r.yieldGrams);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Инспектор расчёта',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('1. Сырье — нетто ${g(r.rawTotalWeight)} г'),
              Text(macros(r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs),
                  style: AppTypography.numeric),
              const SizedBox(height: 16),
              const Text('2. Потери при т.о. — применяем сохранность'),
              for (final row in [
                (
                  'Белки',
                  r.rawTotalProtein,
                  r.retentionProtein,
                  r.cookedProtein
                ),
                ('Жиры', r.rawTotalFat, r.retentionFat, r.cookedFat),
                ('Углеводы', r.rawTotalCarbs, r.retentionCarbs, r.cookedCarbs),
              ])
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${row.$1}: ${m(row.$2)} × ${CalculationEngine.formatPercent(row.$3)}% = ${m(row.$4)} г',
                        style: AppTypography.numeric)),
              const SizedBox(height: 16),
              const Text('3. Энергетическая ценность после т.о.'),
              Text(
                  '${m(r.cookedProtein)} × 4 + ${m(r.cookedFat)} × 9 + ${m(r.cookedCarbs)} × 4 = ${k(r.cookedKcal)} ккал',
                  style: AppTypography.numeric),
              const SizedBox(height: 16),
              Text('4. Выход готового блюда: ${g(r.yieldGrams)} г'),
              Text(e.badge),
              Text(e.description),
              if (r.yieldGrams > 0) ...[
                const SizedBox(height: 8),
                Text(
                    'На 100 г: каждый итог после т.о. × 100 / ${g(r.yieldGrams)}'),
                Text(
                    '${macros(r.per100gProtein, r.per100gFat, r.per100gCarbs)} · ${k(r.per100gKcal)} ккал',
                    style: AppTypography.numeric),
              ],
              const SizedBox(height: 16),
              const Text(
                  'Сырой состав и готовое блюдо — разные стадии, а не противоречащие значения. Сохранность задаётся в параметрах и не определяет уварку. Округление как в бланке: БЖУ до 0,01 г, энергия до 0,1 ккал; энергия считается по округлённым БЖУ.'),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно')),
            ]),
      )),
    );
  }
}
