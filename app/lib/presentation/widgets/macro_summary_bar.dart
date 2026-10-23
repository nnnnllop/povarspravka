import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/calculation_result.dart';
import '../../core/calculation/yield_explanation.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Итоги блюда как **жизненный цикл** (аудит P1-6).
///
/// Было: 4 цветные пастельные карточки Б/Ж/У/ккал, под ними текстовый блок
/// «Сырьё → т.о. → готовое блюдо», всё это — в подвале прокручиваемой ленты,
/// то есть далеко от глаз и под клавиатурой. Читатель не понимал, к какой
/// стадии относятся цифры.
///
/// Стало: три ступени сверху вниз, ровно в той последовательности, в которой
/// существует блюдо:
///
/// | Ступень | Что показывает | Почему |
/// |---|---|---|
/// | 1. Сырьё | нетто-масса и Б/Ж/У до т.о. | «сколько положили в кастрюлю» |
/// | 2. После т.о. | что выжило после сохранности | «что осталось» |
/// | 3. Порция | на 100 г, на всё блюдо, любая масса | «что съел гость» |
///
/// Числа — tabular figures, без цветных заливок; цвет — только 2-dp маркер.
class MacroSummaryBar extends StatefulWidget {
  final CalculationResult result;

  /// Компактный режим для нижней закреплённой полосы на коротком экране:
  /// одна строка + «Инспектор расчёта» + переключатель.
  final bool compact;

  const MacroSummaryBar({
    super.key,
    required this.result,
    this.compact = false,
  });

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
    final p = Palette.of(context);

    if (widget.compact) return _buildCompact(context, p, r);

    return Container(
      color: p.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Пищевая ценность готового блюда',
                    style: AppTypography.label.copyWith(
                      color: p.ink,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                _buildInspectorButton(p, dense: true),
              ],
            ),
            const SizedBox(height: Space.x2),

            // ── Ступень 1: Сырьё ────────────────────────────────────────
            _StageRow(
              palette: p,
              number: 1,
              title: 'Сырьё',
              subtitle: 'нетто ${g(r.rawTotalWeight)} г',
              cells: [
                ('Б', m(r.rawTotalProtein), p.protein),
                ('Ж', m(r.rawTotalFat), p.fat),
                ('У', m(r.rawTotalCarbs), p.carbs),
              ],
              muted: true,
            ),
            // ── Ступень 2: После т.о. ───────────────────────────────────
            _StageRow(
              palette: p,
              number: 2,
              title: 'После т.о.',
              subtitle:
                  'сохранность ${CalculationEngine.formatPercent(r.retentionProtein)} / '
                  '${CalculationEngine.formatPercent(r.retentionFat)} / '
                  '${CalculationEngine.formatPercent(r.retentionCarbs)} %',
              cells: [
                ('Б', m(r.cookedProtein), p.protein),
                ('Ж', m(r.cookedFat), p.fat),
                ('У', m(r.cookedCarbs), p.carbs),
              ],
              trailing: '${k(r.cookedKcal)} ккал',
              trailingTint: p.kcal,
              onTap: () => _inspect(context),
            ),
            // ── Ступень 3: Порция ───────────────────────────────────────
            _buildPortionStage(context, p, r),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorButton(Palette p, {required bool dense}) {
    return TextButton.icon(
      onPressed: () => _inspect(context),
      icon: const Icon(Icons.tune_rounded, size: 16),
      label: const Text('Инспектор расчёта'),
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        padding: EdgeInsets.symmetric(
            horizontal: dense ? Space.x2 : Space.x3, vertical: 0),
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Ступень 3: «Порция» — переключатель «на всё блюдо / на 100 г» верхней
  /// строкой, затем 4 значения в ряд и калькулятор произвольной массы.
  Widget _buildPortionStage(BuildContext context, Palette p, CalculationResult r) {
    final totalLabel = 'На всё блюдо (${g(r.yieldGrams)} г)';
    final per100Label = 'На 100 г готового блюда';

    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '3',
                  style: AppTypography.caption.copyWith(
                    color: p.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  'Порция',
                  style: AppTypography.label.copyWith(color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          // Выбор ответа: «на всё блюдо» или «на 100 г».
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
              backgroundColor: p.surface,
              foregroundColor: p.inkSecondary,
              selectedBackgroundColor: p.accentSoft,
              selectedForegroundColor: p.accent,
              side: BorderSide(color: p.border),
              shape: RoundedRectangleBorder(borderRadius: Radii.fieldAll),
              textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
            ),
            segments: [
              ButtonSegment(
                value: false,
                label: Text(totalLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              ButtonSegment(
                value: true,
                label: Text(per100Label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
            selected: {_showPer100g},
            onSelectionChanged: (value) =>
                setState(() => _showPer100g = value.single),
          ),
          const SizedBox(height: Space.x3),
          // Четыре числа — одна строка, tabular figures, 2-dp маркеры.
          Wrap(
            spacing: Space.x4,
            runSpacing: Space.x2,
            children: [
              _ValueCell(
                tint: p.protein,
                title: 'Белки',
                value: m(_showPer100g ? r.per100gProtein : r.cookedProtein),
                unit: 'г',
                palette: p,
              ),
              _ValueCell(
                tint: p.fat,
                title: 'Жиры',
                value: m(_showPer100g ? r.per100gFat : r.cookedFat),
                unit: 'г',
                palette: p,
              ),
              _ValueCell(
                tint: p.carbs,
                title: 'Углеводы',
                value: m(_showPer100g ? r.per100gCarbs : r.cookedCarbs),
                unit: 'г',
                palette: p,
              ),
              _ValueCell(
                tint: p.kcal,
                title: 'Энергия',
                value: k(_showPer100g ? r.per100gKcal : r.cookedKcal),
                unit: 'ккал',
                palette: p,
              ),
            ],
          ),
          if (r.yieldGrams > 0) ...[
            const SizedBox(height: Space.x3),
            TextFormField(
              key: const ValueKey('portion-grams'),
              initialValue: '200',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.num,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Масса порции, г',
                errorText: _portionError,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: Space.x3, vertical: Space.x2),
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
            const SizedBox(height: Space.x2),
            Builder(builder: (_) {
              final portion = r.portion(_portionGrams);
              return Text(
                'Порция ${g(_portionGrams)} г: ${macros(portion.protein, portion.fat, portion.carbs)} · ${k(portion.kcal)} ккал',
                key: const ValueKey('portion-result'),
                style: AppTypography.numSm.copyWith(color: p.ink),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Компактная полоса для нижнего дока: одна числовая строка + инспектор.
  ///
  /// Выход блюда здесь сознательно НЕ дублируется: он уже выведен крупной
  /// строкой в карточке параметров выше, а повтор в доке — это второй ответ
  /// на тот же вопрос.
  Widget _buildCompact(BuildContext context, Palette p, CalculationResult r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'После т.о. · на всё блюдо',
                  style: AppTypography.caption.copyWith(color: p.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Wrap не даёт строгих ограничений по ширине ни ОДНОМУ
                // ребёнку и переносит их сам — поэтому внутренние Column
                // здесь безопасны, а при крупном шрифте строка уйдёт вниз.
                Wrap(
                  spacing: Space.x3,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    for (final cell in <(Color, String, String, String)>[
                      (p.protein, 'Белки', m(r.cookedProtein), 'г'),
                      (p.fat, 'Жиры', m(r.cookedFat), 'г'),
                      (p.carbs, 'Углеводы', m(r.cookedCarbs), 'г'),
                      (p.kcal, 'Энергия', k(r.cookedKcal), 'ккал'),
                    ])
                      _ValueCell(
                        tint: cell.$1,
                        title: cell.$2,
                        value: cell.$3,
                        unit: cell.$4,
                        palette: p,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            // В компактном доке места на текст нет — подпись уходит в
            // семантику и tooltip, чтобы кнопка оставалась находимой
            // скринридером и голосовым управлением.
            tooltip: 'Инспектор расчёта',
            onPressed: () => _inspect(context),
            icon: Semantics(
              label: 'Инспектор расчёта',
              child: Icon(Icons.tune_rounded, size: 20, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _inspect(BuildContext context) {
    final r = widget.result;
    final e = YieldExplanation(r.rawTotalWeight, r.yieldGrams);
    final p = Palette.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      // Фиксированная высота: неограниченный bottom sheet + Column без
      // строгих ограничений = бесконечно пружинящее полотно. Берём явную
      // долю экрана.
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(Space.x5, 0, Space.x5, Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Инспектор расчёта',
                style: AppTypography.title.copyWith(color: p.ink),
              ),
              const SizedBox(height: Space.x1),
              Text(
                'Откуда взялась каждая цифра — по шагам.',
                style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: Space.x4),
              _buildStepCard(
                palette: p,
                title: '1. Сырье — нетто ${g(r.rawTotalWeight)} г',
                content: Text(
                  macros(r.rawTotalProtein, r.rawTotalFat, r.rawTotalCarbs),
                  style: AppTypography.num.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: Space.x2),
              _buildStepCard(
                palette: p,
                title: '2. Потери при т.о. — применяем сохранность',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in [
                      (
                        'Белки',
                        r.rawTotalProtein,
                        r.retentionProtein,
                        r.cookedProtein
                      ),
                      (
                        'Жиры',
                        r.rawTotalFat,
                        r.retentionFat,
                        r.cookedFat
                      ),
                      (
                        'Углеводы',
                        r.rawTotalCarbs,
                        r.retentionCarbs,
                        r.cookedCarbs
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${row.$1}: ${m(row.$2)} × ${CalculationEngine.formatPercent(row.$3)}% = ${m(row.$4)} г',
                          style: AppTypography.num.copyWith(color: p.ink),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.x2),
              _buildStepCard(
                palette: p,
                title: '3. Энергетическая ценность после т.о.',
                content: Text(
                  '${m(r.cookedProtein)} × 4 + ${m(r.cookedFat)} × 9 + ${m(r.cookedCarbs)} × 4 = ${k(r.cookedKcal)} ккал',
                  style: AppTypography.num.copyWith(color: p.ink),
                ),
              ),
              const SizedBox(height: Space.x2),
              _buildStepCard(
                palette: p,
                title: '4. Выход готового блюда: ${g(r.yieldGrams)} г',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.badge,
                        style: AppTypography.bodySm.copyWith(
                            color: p.ink, fontWeight: FontWeight.w700)),
                    Text(e.description,
                        style: AppTypography.bodySm
                            .copyWith(color: p.inkSecondary)),
                    if (r.yieldGrams > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'На 100 г: каждый итог после т.о. × 100 / ${g(r.yieldGrams)}',
                        style: AppTypography.bodySm
                            .copyWith(color: p.inkSecondary),
                      ),
                      Text(
                        '${macros(r.per100gProtein, r.per100gFat, r.per100gCarbs)} · ${k(r.per100gKcal)} ккал',
                        style: AppTypography.num.copyWith(color: p.ink),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.x4),
              Text(
                'Сырой состав и готовое блюдо — разные стадии, а не противоречащие значения. '
                'Сохранность задаётся в параметрах и не определяет уварку. Округление как в бланке: '
                'БЖУ до 0,01 г, энергия до 0,1 ккал; энергия считается по округлённым БЖУ.',
                style:
                    AppTypography.bodySm.copyWith(color: p.inkSecondary),
              ),
              const SizedBox(height: Space.x4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required Palette palette,
    required String title,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: Radii.fieldAll,
        border: Border.all(color: palette.borderStatic),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.label.copyWith(color: palette.ink),
          ),
          const SizedBox(height: Space.x1),
          content,
        ],
      ),
    );
  }
}

/// Ступень жизненного цикла: номер, заголовок, Б/Ж/У и опционально энергия.
class _StageRow extends StatelessWidget {
  final Palette palette;
  final int number;
  final String title;
  final String subtitle;
  final List<(String, String, Color)> cells;
  final String? trailing;
  final Color? trailingTint;
  final bool muted;
  final VoidCallback? onTap;

  const _StageRow({
    required this.palette,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.cells,
    this.trailing,
    this.trailingTint,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: muted ? p.sunken : p.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$number',
              style: AppTypography.caption.copyWith(
                color: muted ? p.inkSecondary : p.onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          // Заголовок ступени и её значения — одной колонкой внутри Expanded:
          // никаких неограниченных Column внутри Row (это и давало overflow
          // на 320 dp при масштабе 2.0×).
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.label.copyWith(color: p.ink)),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(color: p.inkSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (cells.isNotEmpty || trailing != null) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: Space.x3,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final c in cells)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 2, height: 11, color: c.$3),
                            const SizedBox(width: 4),
                            Text(
                              '${c.$1} ',
                              style: AppTypography.caption
                                  .copyWith(color: p.inkMuted),
                            ),
                            Text(
                              c.$2,
                              style: AppTypography.numSm.copyWith(
                                color: muted ? p.inkSecondary : p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      if (trailing != null)
                        Text(
                          trailing!,
                          style: AppTypography.numSm.copyWith(
                            color: trailingTint ?? p.kcal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.fieldAll,
      child: row,
    );
  }
}

/// Одно числовое значение с 2-dp маркером и подписью.
class _ValueCell extends StatelessWidget {
  final Color tint;
  final String title;
  final String value;
  final String unit;
  final Palette palette;
  final bool compact;

  const _ValueCell({
    required this.tint,
    required this.title,
    required this.value,
    required this.unit,
    required this.palette,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 2,
          height: compact ? 26 : 30,
          color: tint,
          margin: const EdgeInsets.only(right: Space.x2),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: AppTypography.caption
                    .copyWith(color: palette.inkMuted)),
            Text(
              '$value $unit',
              key: ValueKey('macro-$title'),
              style: (compact ? AppTypography.numSm : AppTypography.num)
                  .copyWith(color: palette.ink),
            ),
          ],
        ),
      ],
    );
  }
}

