import 'package:flutter/material.dart';
import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/ingredient.dart';
import '../../core/theme/app_typography.dart';
import 'source_badge.dart';

class IngredientCard extends StatelessWidget {
  final int index;
  final Ingredient ingredient;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const IngredientCard(
      {super.key,
      required this.index,
      required this.ingredient,
      required this.onTap,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final theme = Theme.of(context);
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 3, right: 12),
                  child: Text('$index', style: AppTypography.numeric)),
              Expanded(
                  child: Text(ing.product.name,
                      softWrap: true, style: theme.textTheme.titleMedium)),
              IconButton(
                  tooltip: 'Удалить ингредиент',
                  onPressed: onDelete,
                  icon: const Icon(Icons.close)),
            ]),
            SourceBadge(source: ing.product.source),
            const SizedBox(height: 12),
            Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Сырой вес (нетто)'),
                  OutlinedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                          '${CalculationEngine.formatGrams(ing.netGramsRounded)} г',
                          style: AppTypography.numeric
                              .copyWith(color: theme.colorScheme.primary))),
                  if (ing.isGross)
                    Text(
                        'Брутто ${CalculationEngine.formatGrams(ing.weightGrams)} г'),
                ]),
            const SizedBox(height: 8),
            Text(
                'Сырой состав: Б: ${CalculationEngine.formatMacro(ing.proteinInDish)} · Ж: ${CalculationEngine.formatMacro(ing.fatInDish)} · У: ${CalculationEngine.formatMacro(ing.carbsInDish)} · ${CalculationEngine.formatKcal(ing.blankKcalInDish)} ккал',
                style: AppTypography.numeric.copyWith(
                    fontSize: 14, color: theme.colorScheme.onSurface)),
          ]),
        ));
  }
}
