import 'package:flutter/material.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/export/export_service.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';

/// Шторка пакетного экспорта выбранных блюд в единый PDF-сборник или
/// многолистовую книгу Excel (.xlsx).
class BatchExportSheet extends StatefulWidget {
  final List<Dish> dishes;

  const BatchExportSheet({super.key, required this.dishes});

  static Future<void> show(
    BuildContext context, {
    required List<Dish> dishes,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => BatchExportSheet(dishes: dishes),
    );
  }

  @override
  State<BatchExportSheet> createState() => _BatchExportSheetState();
}

class _BatchExportSheetState extends State<BatchExportSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final validDishes = <Dish>[];
    var skippedCount = 0;
    for (final d in widget.dishes) {
      if (CalculationEngine.tryCalculate(d) != null) {
        validDishes.add(d);
      } else {
        skippedCount++;
      }
    }
    final canExport = validDishes.isNotEmpty && !_busy;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x5, 0, Space.x5, Space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Пакетный экспорт',
              style: AppTypography.title.copyWith(color: p.ink),
            ),
            const SizedBox(height: Space.x1),
            Text(
              'Выбрано блюд: ${widget.dishes.length}. В документ войдут '
              'сводная таблица КБЖУ и отдельный бланк каждого блюда.',
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
            if (skippedCount > 0) ...[
              const SizedBox(height: Space.x3),
              Container(
                key: const ValueKey('batch-export-invalid-warning'),
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(
                  color: p.dangerSoft,
                  borderRadius: Radii.fieldAll,
                ),
                child: Text(
                  validDishes.isEmpty
                      ? 'Ни одно из выбранных блюд не может быть рассчитано — проверьте параметры перед экспортом.'
                      : 'Пропущено блюд с ошибкой расчёта: $skippedCount из ${widget.dishes.length}.',
                  style: AppTypography.caption.copyWith(color: p.danger),
                ),
              ),
            ],
            const SizedBox(height: Space.x4),
            FilledButton.icon(
              key: const ValueKey('batch-export-pdf-btn'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget),
              ),
              onPressed: canExport
                  ? () => _runExport(validDishes, ExportType.pdf)
                  : null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(
                _busy
                    ? 'Формирование файла…'
                    : 'PDF-сборник (сводка + бланки)',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Space.x2),
            OutlinedButton.icon(
              key: const ValueKey('batch-export-xlsx-btn'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, kMinTapTarget),
              ),
              onPressed: canExport
                  ? () => _runExport(validDishes, ExportType.xlsx)
                  : null,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
              label: const Text(
                'Excel-книга (.xlsx, листы по блюдам)',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runExport(List<Dish> dishes, ExportType type) async {
    AppHaptics.commit();
    setState(() => _busy = true);
    try {
      await ExportService.shareBatchFile(dishes, type);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(e, prefix: 'Не удалось сформировать сборник'),
          ),
        ),
      );
    }
  }
}
