import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/loss_table.dart';
import '../../core/calculation/models/heat_process.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';

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

/// Чистая строка потерь для карточки ингредиента без повторяющегося префикса
/// «Потери:».
String ingredientLossDisplayText(Ingredient ing, HeatProcess dishProcess) =>
    lossLabelFor(ing, dishProcess).replaceFirst(RegExp(r'^Потери:\s*'), '');

/// Карточка ингредиента (аудит P1-6, доработка v1.2).
///
/// Нетто и брутто рядом (tabular figures), отходы — подписью, БЖУ — строкой
/// [InlineMacroCell], потери — лёгкой строкой-кнопкой `>= 48 dp` без серой
/// плашки, явная ручка перестановки и свайп-удаление (`Dismissible`).
class IngredientCard extends StatelessWidget {
  final int index;
  final Ingredient ingredient;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Индекс в `ReorderableListView` — включает явную ручку перетаскивания.
  final int? dragHandleIndex;

  /// Флаги сгруппированного списка (скругления 20 dp на первой/последней строке).
  final bool isFirst;
  final bool isLast;

  const IngredientCard({
    super.key,
    required this.index,
    required this.ingredient,
    required this.onTap,
    required this.onDelete,
    this.dragHandleIndex,
    this.lossLabel,
    this.onLossTap,
    this.isFirst = true,
    this.isLast = true,
  });

  /// Строка потерь нового расчёта (таблица потерь по группам продуктов).
  /// `null` — старый расчёт (legacy), строки нет.
  final String? lossLabel;

  /// Выбор группы и способа обработки ингредиента (тап по [lossLabel]).
  final VoidCallback? onLossTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ing = ingredient;

    final netGramsStr = _orDash(() => CalculationEngine.formatNetGrams(
        ing.netGramsRounded, ing.product.wastePct));
    final grossGramsStr = CalculationEngine.formatGrams(ing.weightGrams);
    final showGross = ing.isGross && ing.product.wastePct > 0;
    final cleanLossLabel =
        lossLabel?.replaceFirst(RegExp(r'^Потери:\s*'), '').trim();

    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final inlineWeightReadout =
        !AppLayout.isNarrow(media.width) && !AppLayout.isLargeText(textScale);

    final weightReadout = Text(
      'Нетто $netGramsStr г',
      style: AppTypography.numSm.copyWith(
        color: p.ink,
        fontWeight: FontWeight.w700,
      ),
    );

    final rowRadius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? Radii.card : 0),
      bottom: Radius.circular(isLast ? Radii.card : 0),
    );

    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: 'Удалить ингредиент'): onDelete,
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isLast ? Space.x2 : 0),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: rowRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Space.x4,
                    Space.x3,
                    dragHandleIndex != null ? Space.x1 : Space.x4,
                    cleanLossLabel != null ? Space.x1 : Space.x3,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ing.product.name,
                              style: AppTypography.body.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!inlineWeightReadout) ...[
                              const SizedBox(height: Space.x1),
                              weightReadout,
                            ],
                            if (showGross) ...[
                              const SizedBox(height: Space.x1),
                              Text(
                                'Введено брутто $grossGramsStr г · отходы ${CalculationEngine.formatWastePercent(ing.product.wastePct)}\u00A0%',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkMuted),
                              ),
                            ],
                            const SizedBox(height: Space.x1),
                            // Полное КБЖУ с гармоничными разноцветными точками (Б/Ж/У + ккал).
                            Wrap(
                              spacing: Space.x2,
                              runSpacing: Space.x1,
                              children: [
                                InlineMacroCell(
                                  type: NutrientType.protein,
                                  value: _orDash(() =>
                                      CalculationEngine.formatMacro(
                                          ing.proteinInDish)),
                                  compact: true,
                                ),
                                InlineMacroCell(
                                  type: NutrientType.fat,
                                  value: _orDash(() =>
                                      CalculationEngine.formatMacro(
                                          ing.fatInDish)),
                                  compact: true,
                                ),
                                InlineMacroCell(
                                  type: NutrientType.carbs,
                                  value: _orDash(() =>
                                      CalculationEngine.formatMacro(
                                          ing.carbsInDish)),
                                  compact: true,
                                ),
                                InlineMacroCell(
                                  type: NutrientType.kcal,
                                  value: _orDash(() =>
                                      CalculationEngine.formatKcal(
                                          ing.blankKcalInDish)),
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (inlineWeightReadout) ...[
                        const SizedBox(width: Space.x2),
                        weightReadout,
                      ],
                      if (dragHandleIndex != null)
                        ReorderableDragStartListener(
                          index: dragHandleIndex!,
                          child: Semantics(
                            label: 'Перетащить ингредиент',
                            child: SizedBox(
                              width: kMinTapTarget,
                              height: kMinTapTarget,
                              child: Icon(Icons.drag_indicator_rounded,
                                  size: IconSizes.md, color: p.inkMuted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (cleanLossLabel != null)
                  InkWell(
                    key: ValueKey('loss-${ing.id}'),
                    onTap: onLossTap,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: kMinTapTarget),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.x4,
                          Space.x1,
                          Space.x4,
                          Space.x2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department_outlined,
                              size: IconSizes.xs,
                              color: p.accent,
                            ),
                            const SizedBox(width: Space.x1),
                            Expanded(
                              child: Text(
                                cleanLossLabel,
                                style: AppTypography.caption.copyWith(
                                  color: p.inkSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: Space.x1),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: IconSizes.xs,
                              color: p.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!isLast)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: Space.x4),
                    color: p.divider,
                  ),
              ],
            ),
          ),
        ),
      ),
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
