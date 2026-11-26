import 'package:flutter/material.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/dish.dart';
import '../../core/export/export_service.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';

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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => BatchExportSheet(dishes: dishes),
    );
  }

  @override
  State<BatchExportSheet> createState() => _BatchExportSheetState();
}

class _BatchExportSheetState extends State<BatchExportSheet> {
  ExportType? _busyType;
  String? _errorText;

  static String _formatSkippedNames(List<String> names) {
    if (names.length <= 5) return names.join(', ');
    final visible = names.take(5).join(', ');
    final rest = names.length - 5;
    return '$visible и ещё $rest';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final validDishes = <Dish>[];
    final skippedNames = <String>[];
    for (final d in widget.dishes) {
      if (CalculationEngine.tryCalculate(d) != null) {
        validDishes.add(d);
      } else {
        final t = d.title.trim();
        skippedNames.add(t.isEmpty ? 'Блюдо без названия' : t);
      }
    }
    final skippedCount = skippedNames.length;
    final skippedText = _formatSkippedNames(skippedNames);
    final isBusy = _busyType != null;
    final canExport = validDishes.isNotEmpty && !isBusy;

    return AppSheetScaffold(
      title: 'Пакетный экспорт',
      subtitle: 'Выбрано ${pluralDishes(widget.dishes.length)}. В документ '
          'войдут сводная таблица КБЖУ и отдельный бланк каждого блюда.',
      showHandle: true,
      showClose: true,
      maxHeightFactor: 0.85,
      noticeText: _errorText,
      noticeIsError: true,
      bodyPadding:
          const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (skippedCount > 0) ...[
            Container(
              key: const ValueKey('batch-export-invalid-warning'),
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(
                color: p.dangerSoft,
                borderRadius: Radii.fieldAll,
              ),
              child: Text(
                validDishes.isEmpty
                    ? 'Ни одно из выбранных блюд не может быть рассчитано ($skippedText) — проверьте параметры перед экспортом.'
                    : 'Пропущено блюд с ошибкой расчёта ($skippedCount из ${widget.dishes.length}): $skippedText.',
                style: AppTypography.caption.copyWith(color: p.danger),
              ),
            ),
            const SizedBox(height: Space.x4),
          ],
          FilledButton.icon(
            key: const ValueKey('batch-export-pdf-btn'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, kMinTapTarget),
            ),
            onPressed: canExport
                ? () => _runExport(validDishes, ExportType.pdf)
                : null,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: IconSizes.btn),
            label: Text(
              _busyType == ExportType.pdf
                  ? 'Формирование файла…'
                  : 'PDF — сводка и бланки',
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
            icon: const Icon(Icons.table_chart_outlined, size: IconSizes.btn),
            label: Text(
              _busyType == ExportType.xlsx
                  ? 'Формирование файла…'
                  : 'Excel (.xlsx) — лист на блюдо',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runExport(List<Dish> dishes, ExportType type) async {
    AppHaptics.commit();
    setState(() {
      _busyType = type;
      _errorText = null;
    });
    try {
      await ExportService.shareBatchFile(dishes, type);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyType = null;
        _errorText = friendlyErrorMessage(
          e,
          prefix: 'Не удалось сформировать сборник',
        );
      });
    }
  }
}
