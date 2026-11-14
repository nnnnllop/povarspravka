import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Строка потерь ингредиента в блюде со способом [dishProcess]:
/// «Потери: мясо · варка — Б 10 %, Ж 25 %, У 0 %».
///
/// Числа — из [LossTable.lossFor] (источники — `docs/COEFFICIENT_SOURCES.md`);
/// «(вручную)» — группа или способ заданы поваром, «оценка» — значение
/// не подтверждено таблицей источника (список UNVERIFIED).
String lossLabelFor(Ingredient ing, HeatProcess dishProcess) {
  final group = ing.lossGroup;
  final process = ing.processIn(dishProcess);
  final loss = LossTable.lossFor(group, process);
  final g = '${group.label}${ing.groupOverride != null ? ' (вручную)' : ''}';
  final p = '${process.label}${ing.processOverride != null ? ' (вручную)' : ''}';
  final none = loss.protein == 0 && loss.fat == 0 && loss.carbs == 0;
  final numbers = none
      ? 'нет'
      : 'Б ${CalculationEngine.formatGrams(loss.protein)} %, '
          'Ж ${CalculationEngine.formatGrams(loss.fat)} %, '
          'У ${CalculationEngine.formatGrams(loss.carbs)} %'
          '${loss.isVerified ? '' : ' (оценка)'}';
  return 'Потери: $g · $p — $numbers';
}

/// Карточка ингредиента (аудит P1-6).
///
/// Было: номер, название, бейдж источника, строка «Брутто → −20% → Нетто»,
/// 4 цветные плашки БЖУ и кнопка ✕ 28×28 — семь точек внимания на одну
/// строку списка. Стало: нетто и брутто рядом (tabular figures), отходы —
/// подписью, БЖУ — одной числовой строкой с 2-dp маркерами, явная ручка
/// перестановки ⟷ и иконка удаления 48×48.
class IngredientCard extends StatelessWidget {
  final int index;
  final Ingredient ingredient;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Индекс в `ReorderableListView` — включает явную ручку перетаскивания.
  final int? dragHandleIndex;

  const IngredientCard({
    super.key,
    required this.index,
    required this.ingredient,
    required this.onTap,
    required this.onDelete,
    this.dragHandleIndex,
    this.lossLabel,
    this.onLossTap,
  });

  /// Строка «Потери: группа · способ» нового расчёта (таблица потерь по
  /// группам продуктов). `null` — старый расчёт (legacy), строки нет.
  final String? lossLabel;

  /// Выбор группы и способа обработки ингредиента (тап по [lossLabel]).
  final VoidCallback? onLossTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ing = ingredient;

    final indexLabel = index.toString().padLeft(2, '0');
    // MATH-04: при больших отходах печатаем больше знаков, иначе обратный
    // пересчёт брутто теряет десятки граммов.
    // Сохранённый документ может содержать отход 100 % — тогда нетто не
    // вычисляется; карточка показывает «—», а не роняет экран.
    final netGramsStr = _orDash(() => CalculationEngine.formatNetGrams(
        ing.netGramsRounded, ing.product.wastePct));
    final grossGramsStr = CalculationEngine.formatGrams(ing.weightGrams);
    final showGross = ing.product.wastePct > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.x2),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: p.borderStatic, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x1, Space.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$indexLabel  ',
                            style: AppTypography.numSm.copyWith(
                              color: p.inkMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ing.product.name,
                              style: AppTypography.body.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.x1),
                      // Числовая строка: масса табличными цифрами.
                      Wrap(
                        spacing: Space.x4,
                        runSpacing: Space.x2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MassCell(
                            label: 'Нетто',
                            value: '$netGramsStr г',
                            note: showGross
                                ? ' −${CalculationEngine.formatWastePercent(ing.product.wastePct)} %'
                                : null,
                            palette: p,
                            emphasized: true,
                          ),
                          if (showGross)
                            _MassCell(
                              label: 'Брутто',
                              value: '$grossGramsStr г',
                              palette: p,
                              emphasized: false,
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.x1),
                      // БЖУ: tabular figures + 2-dp маркеры. Без плашек.
                      Wrap(
                        spacing: Space.x3,
                        runSpacing: 2,
                        children: [
                          _MacroCell(
                            tint: p.protein,
                            label: 'Б',
                            value:
                                _orDash(() => CalculationEngine.formatMacro(ing.proteinInDish)),
                            palette: p,
                          ),
                          _MacroCell(
                            tint: p.fat,
                            label: 'Ж',
                            value: _orDash(() => CalculationEngine.formatMacro(ing.fatInDish)),
                            palette: p,
                          ),
                          _MacroCell(
                            tint: p.carbs,
                            label: 'У',
                            value: _orDash(() => CalculationEngine.formatMacro(ing.carbsInDish)),
                            palette: p,
                          ),
                          _MacroCell(
                            tint: p.kcal,
                            label: 'ккал',
                            value:
                                _orDash(() => CalculationEngine.formatKcal(ing.blankKcalInDish)),
                            palette: p,
                          ),
                        ],
                      ),
                      if (lossLabel != null)
                        // Высота строки — 48 dp (WCAG 2.5.5): это отдельная
                        // цель нажатия, а не часть тапа «изменить массу».
                        InkWell(
                          key: ValueKey('loss-${ing.id}'),
                          onTap: onLossTap,
                          borderRadius: BorderRadius.circular(6),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                minHeight: kMinTapTarget),
                            child: Row(
                              children: [
                                Icon(Icons.local_fire_department_outlined,
                                    size: 16, color: p.inkMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    lossLabel!,
                                    style: AppTypography.caption
                                        .copyWith(color: p.inkSecondary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.edit_outlined,
                                    size: 16, color: p.inkMuted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Явная ручка ⟷: перетаскивание больше не борется с тапом
                // «изменить» и свайпом «удалить».
                if (dragHandleIndex != null)
                  ReorderableDragStartListener(
                    index: dragHandleIndex!,
                    child: Semantics(
                      label: 'Перетащить ингредиент',
                      child: SizedBox(
                        width: kMinTapTarget,
                        height: kMinTapTarget,
                        child: Icon(Icons.drag_indicator_rounded,
                            size: 22, color: p.inkMuted),
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: p.inkMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: kMinTapTarget, minHeight: kMinTapTarget),
                  tooltip: 'Удалить ингредиент',
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MassCell extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Palette palette;
  final bool emphasized;

  const _MassCell({
    required this.label,
    required this.value,
    required this.palette,
    required this.emphasized,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$label ',
          style: AppTypography.caption.copyWith(color: palette.inkMuted),
        ),
        Text(
          value,
          style: AppTypography.num.copyWith(
            color: emphasized ? palette.ink : palette.inkSecondary,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        if (note != null)
          Flexible(
            child: Text(
              note!,
              style: AppTypography.caption.copyWith(color: palette.inkMuted),
            ),
          ),
      ],
    );
  }
}

class _MacroCell extends StatelessWidget {
  final Color tint;
  final String label;
  final String value;
  final Palette palette;

  const _MacroCell({
    required this.tint,
    required this.label,
    required this.value,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 2, height: 11, color: tint),
        const SizedBox(width: 4),
        Text(
          '$label ',
          style: AppTypography.caption.copyWith(color: palette.inkMuted),
        ),
        Text(
          value,
          style: AppTypography.numSm.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Значение из сохранённого документа, которое отвергает валидатор
/// (например, отход 100 %), печатается как «—»: карточка не роняет экран,
/// а причину показывает баннер ошибки расчёта.
String _orDash(String Function() format) {
  try {
    return format();
  } on ArgumentError {
    return '—';
  }
}
