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

  /// Строка потерь нового расчёта (таблица потерь по группам продуктов).
  /// `null` — старый расчёт (legacy), строки нет.
  final String? lossLabel;

  /// Выбор группы и способа обработки ингредиента (тап по [lossLabel]).
  final VoidCallback? onLossTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ing = ingredient;

    final indexLabel = '$index.';
    // MATH-04: при больших отходах печатаем больше знаков, иначе обратный
    // пересчёт брутто теряет десятки граммов.
    // Сохранённый документ может содержать отход 100 % — тогда нетто не
    // вычисляется; карточка показывает «—», а не роняет экран.
    final netGramsStr = _orDash(() => CalculationEngine.formatNetGrams(
        ing.netGramsRounded, ing.product.wastePct));
    final grossGramsStr = CalculationEngine.formatGrams(ing.weightGrams);
    final showGross = ing.product.wastePct > 0;
    final cleanLossLabel =
        lossLabel?.replaceFirst(RegExp(r'^Потери:\s*'), '').trim();

    final media = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final inlineWeightPill = media.width >= 340 && textScale <= 1.35;

    final weightPill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x2 + 2,
        vertical: Space.x1 + 2,
      ),
      decoration: BoxDecoration(
        color: p.sunken,
        borderRadius: Radii.chipAll,
        border: Border.all(color: p.borderStatic),
      ),
      child: Text(
        '$netGramsStr г',
        style: AppTypography.num.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        const CustomSemanticsAction(label: 'Удалить ингредиент'): onDelete,
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.x2),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: Radii.cardAll,
          border: Border.all(color: p.borderStatic),
          boxShadow: p.cardShadow,
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
                    Space.x3,
                    Space.x3,
                    dragHandleIndex != null ? Space.x1 : Space.x3,
                    cleanLossLabel != null ? Space.x2 : Space.x3,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$indexLabel ',
                                  style: AppTypography.numSm.copyWith(
                                    color: p.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    ing.product.name,
                                    style: AppTypography.body.copyWith(
                                      color: p.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (!inlineWeightPill) ...[
                              const SizedBox(height: Space.x2),
                              weightPill,
                            ],
                            if (showGross) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Брутто $grossGramsStr г · −${CalculationEngine.formatWastePercent(ing.product.wastePct)} %',
                                style: AppTypography.caption
                                    .copyWith(color: p.inkMuted),
                              ),
                            ],
                            const SizedBox(height: Space.x1 + 2),
                            // БЖУ: микро-точки M2 и нейтральный текст.
                            Wrap(
                              spacing: Space.x3,
                              runSpacing: 2,
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
                      if (inlineWeightPill) ...[
                        const SizedBox(width: Space.x2),
                        weightPill,
                      ],
                      // Явная ручка перестановки ⟷ (удаление — свайп Dismissible
                      // и действие доступности).
                      if (dragHandleIndex != null)
                        ReorderableDragStartListener(
                          index: dragHandleIndex!,
                          child: Semantics(
                            label: 'Перетащить ингредиент',
                            child: SizedBox(
                              width: kMinTapTarget,
                              height: kMinTapTarget,
                              child: Icon(Icons.drag_indicator_rounded,
                                  size: 20, color: p.inkMuted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (cleanLossLabel != null) ...[
                  Divider(color: p.divider, height: 1),
                  InkWell(
                    key: ValueKey('loss-${ing.id}'),
                    onTap: onLossTap,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: kMinTapTarget),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.x3,
                          vertical: Space.x2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_fire_department_outlined,
                              size: 14,
                              color: p.inkSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cleanLossLabel,
                                style: AppTypography.caption
                                    .copyWith(color: p.inkSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 15,
                              color: p.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
