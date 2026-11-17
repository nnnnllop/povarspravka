import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/search_provider.dart';
import 'app_buttons.dart';

/// Шторка создания/редактирования своего продукта или сохранения готового
/// блюда в виде полуфабриката на 100 г.
class CustomProductFormSheet extends ConsumerStatefulWidget {
  final Product? initial;
  final String initialName;
  final double? initialProtein;
  final double? initialFat;
  final double? initialCarbs;
  final double? initialKcal;
  final double initialWastePct;
  final bool initialIsDish;
  final String? sheetTitle;
  final String? sheetSubtitle;

  const CustomProductFormSheet({
    super.key,
    this.initial,
    this.initialName = '',
    this.initialProtein,
    this.initialFat,
    this.initialCarbs,
    this.initialKcal,
    this.initialWastePct = 0.0,
    this.initialIsDish = false,
    this.sheetTitle,
    this.sheetSubtitle,
  });

  static Future<Product?> show(
    BuildContext context, {
    Product? initial,
    String initialName = '',
    double? initialProtein,
    double? initialFat,
    double? initialCarbs,
    double? initialKcal,
    double initialWastePct = 0.0,
    bool initialIsDish = false,
    String? sheetTitle,
    String? sheetSubtitle,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = Palette.of(context);
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (_) => CustomProductFormSheet(
        initial: initial,
        initialName: initialName,
        initialProtein: initialProtein,
        initialFat: initialFat,
        initialCarbs: initialCarbs,
        initialKcal: initialKcal,
        initialWastePct: initialWastePct,
        initialIsDish: initialIsDish,
        sheetTitle: sheetTitle,
        sheetSubtitle: sheetSubtitle,
      ),
    );
  }

  @override
  ConsumerState<CustomProductFormSheet> createState() =>
      _CustomProductFormSheetState();
}

class _CustomProductFormSheetState
    extends ConsumerState<CustomProductFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pCtrl;
  late final TextEditingController _fCtrl;
  late final TextEditingController _cCtrl;
  late final TextEditingController _kcalCtrl;
  late final TextEditingController _wasteCtrl;
  late bool _isDish;
  bool _kcalManual = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    final pVal = init?.protein ?? widget.initialProtein;
    final fVal = init?.fat ?? widget.initialFat;
    final cVal = init?.carbs ?? widget.initialCarbs;
    final kcalVal = init?.kcal ?? widget.initialKcal;
    final wasteVal = init?.wastePct ?? widget.initialWastePct;

    _nameCtrl = TextEditingController(
      text: init?.name ?? widget.initialName,
    );
    _pCtrl = TextEditingController(
      text: pVal != null ? CalculationEngine.formatMacro(pVal) : '',
    );
    _fCtrl = TextEditingController(
      text: fVal != null ? CalculationEngine.formatMacro(fVal) : '',
    );
    _cCtrl = TextEditingController(
      text: cVal != null ? CalculationEngine.formatMacro(cVal) : '',
    );
    _kcalCtrl = TextEditingController(
      text: kcalVal != null ? CalculationEngine.formatKcal(kcalVal) : '0',
    );
    _wasteCtrl = TextEditingController(
      text: CalculationEngine.formatWastePercent(wasteVal),
    );
    _isDish = init?.isDishOnly ?? widget.initialIsDish;
    _kcalManual = init != null || widget.initialKcal != null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pCtrl.dispose();
    _fCtrl.dispose();
    _cCtrl.dispose();
    _kcalCtrl.dispose();
    _wasteCtrl.dispose();
    super.dispose();
  }

  void _recalcKcalIfAuto() {
    if (_kcalManual) return;
    final prot = CalculationEngine.parseInputDouble(_pCtrl.text) ?? 0.0;
    final fat = CalculationEngine.parseInputDouble(_fCtrl.text) ?? 0.0;
    final carbs = CalculationEngine.parseInputDouble(_cCtrl.text) ?? 0.0;
    final kcal = prot * 4.0 + fat * 9.0 + carbs * 4.0;
    _kcalCtrl.text = CalculationEngine.formatKcal(kcal);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название продукта');
      return;
    }
    final prot = _pCtrl.text.trim().isEmpty
        ? 0.0
        : CalculationEngine.parseInputDouble(_pCtrl.text);
    final fat = _fCtrl.text.trim().isEmpty
        ? 0.0
        : CalculationEngine.parseInputDouble(_fCtrl.text);
    final carbs = _cCtrl.text.trim().isEmpty
        ? 0.0
        : CalculationEngine.parseInputDouble(_cCtrl.text);
    final kcal = CalculationEngine.parseInputDouble(_kcalCtrl.text);
    final waste = _wasteCtrl.text.trim().isEmpty
        ? 0.0
        : CalculationEngine.parseInputDouble(_wasteCtrl.text);

    if (prot == null || fat == null || carbs == null || kcal == null) {
      setState(() => _error = 'Проверьте числа Б, Ж, У и ккал');
      return;
    }
    if (prot < 0 || fat < 0 || carbs < 0 || kcal < 0) {
      setState(() => _error = 'Значения не могут быть отрицательными');
      return;
    }
    if (prot + fat + carbs > 100.0) {
      setState(() =>
          _error = 'Сумма Б + Ж + У на 100 г не должна превышать 100 г');
      return;
    }
    if (waste == null || waste < 0 || waste >= 100) {
      setState(() => _error = 'Отходы должны быть от 0 до 99 %');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(customProductsProvider.notifier);
      final Product result;
      if (widget.initial == null) {
        result = await notifier.addProduct(
          name: name,
          protein: prot,
          fat: fat,
          carbs: carbs,
          kcal: kcal,
          wastePct: waste,
          isDish: _isDish,
        );
      } else {
        result = await notifier.updateProduct(
          widget.initial!.copyWith(
            name: name,
            protein: prot,
            fat: fat,
            carbs: carbs,
            kcal: kcal,
            wastePct: waste,
            isDish: _isDish,
          ),
        );
        syncRecentProduct(ref, result);
      }
      if (!mounted) return;
      AppHaptics.commit();
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            friendlyErrorMessage(e, prefix: 'Не удалось сохранить продукт');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final stackMacros = size.width < 360 || textScale > 1.35;

    Widget numField({
      required Key fieldKey,
      required TextEditingController ctrl,
      required String label,
      void Function(String)? onChanged,
    }) {
      return TextField(
        key: fieldKey,
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: AppTypography.num.copyWith(color: p.ink),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
        ),
        onChanged: onChanged,
      );
    }

    final macroFields = [
      numField(
        fieldKey: const ValueKey('custom-protein'),
        ctrl: _pCtrl,
        label: 'Белки, г',
        onChanged: (_) => setState(_recalcKcalIfAuto),
      ),
      numField(
        fieldKey: const ValueKey('custom-fat'),
        ctrl: _fCtrl,
        label: 'Жиры, г',
        onChanged: (_) => setState(_recalcKcalIfAuto),
      ),
      numField(
        fieldKey: const ValueKey('custom-carbs'),
        ctrl: _cCtrl,
        label: 'Углеводы, г',
        onChanged: (_) => setState(_recalcKcalIfAuto),
      ),
    ];

    final title = widget.sheetTitle ??
        (widget.initial == null
            ? 'Свой продукт (на 100 г)'
            : 'Редактировать продукт');
    final subtitle = widget.sheetSubtitle ??
        'Удобно для продуктов с этикетки или авторских заготовок.';

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: size.height * 0.9),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppTypography.title.copyWith(color: p.ink)),
                const SizedBox(height: Space.x1),
                Text(
                  subtitle,
                  style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
                ),
                const SizedBox(height: Space.x3),
                TextField(
                  key: const ValueKey('custom-name'),
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Название продукта',
                    hintText: 'Например, соус терияки',
                  ),
                ),
                const SizedBox(height: Space.x3),
                if (stackMacros)
                  Column(
                    children: [
                      macroFields[0],
                      const SizedBox(height: Space.x2),
                      macroFields[1],
                      const SizedBox(height: Space.x2),
                      macroFields[2],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: macroFields[0]),
                      const SizedBox(width: Space.x2),
                      Expanded(child: macroFields[1]),
                      const SizedBox(width: Space.x2),
                      Expanded(child: macroFields[2]),
                    ],
                  ),
                const SizedBox(height: Space.x2),
                if (stackMacros) ...[
                  numField(
                    fieldKey: const ValueKey('custom-kcal'),
                    ctrl: _kcalCtrl,
                    label: _kcalManual ? 'Ккал / 100 г' : 'Ккал (авто)',
                    onChanged: (_) => setState(() => _kcalManual = true),
                  ),
                  const SizedBox(height: Space.x2),
                  numField(
                    fieldKey: const ValueKey('custom-waste'),
                    ctrl: _wasteCtrl,
                    label: 'Отходы, %',
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: numField(
                          fieldKey: const ValueKey('custom-kcal'),
                          ctrl: _kcalCtrl,
                          label: _kcalManual ? 'Ккал / 100 г' : 'Ккал (авто)',
                          onChanged: (_) => setState(() => _kcalManual = true),
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: numField(
                          fieldKey: const ValueKey('custom-waste'),
                          ctrl: _wasteCtrl,
                          label: 'Отходы, %',
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: Space.x2),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  title: Text(
                    'Готовое блюдо',
                    style: AppTypography.bodySm.copyWith(color: p.ink),
                  ),
                  value: _isDish,
                  onChanged: (v) => setState(() => _isDish = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.x2),
                  Container(
                    padding: const EdgeInsets.all(Space.x3),
                    decoration: BoxDecoration(
                      color: p.dangerSoft,
                      borderRadius: Radii.fieldAll,
                    ),
                    child: Text(
                      _error!,
                      style: AppTypography.caption.copyWith(color: p.danger),
                    ),
                  ),
                ],
                const SizedBox(height: Space.x3),
                if (stackMacros) ...[
                  FilledButton(
                    key: const ValueKey('custom-save-btn'),
                    onPressed: _saving ? null : _submit,
                    child: const Text('Сохранить продукт',
                        textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: Space.x1),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                ] else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('custom-save-btn'),
                            onPressed: _saving ? null : _submit,
                            child: const Text('Сохранить продукт',
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
