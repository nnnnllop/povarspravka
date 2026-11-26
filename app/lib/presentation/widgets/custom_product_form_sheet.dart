import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calculation/calculation_engine.dart';
import '../../core/calculation/models/product.dart';
import '../../core/theme/app_haptics.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';
import '../providers/search_provider.dart';
import 'app_buttons.dart';
import 'app_sheet.dart';

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
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
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

enum _CustomFieldError { none, name, macros, kcal, waste }

class _CustomProductFormSheetState
    extends ConsumerState<CustomProductFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pCtrl;
  late final TextEditingController _fCtrl;
  late final TextEditingController _cCtrl;
  late final TextEditingController _kcalCtrl;
  late final TextEditingController _wasteCtrl;
  late final String _initNameText;
  late final String _initPText;
  late final String _initFText;
  late final String _initCText;
  late final String _initKcalText;
  late final String _initWasteText;
  late final bool _initIsDishVal;
  late bool _isDish;
  bool _kcalManual = false;
  bool _saving = false;
  String? _error;
  _CustomFieldError _errorField = _CustomFieldError.none;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    final pVal = init?.protein ?? widget.initialProtein;
    final fVal = init?.fat ?? widget.initialFat;
    final cVal = init?.carbs ?? widget.initialCarbs;
    final kcalVal = init?.kcal ?? widget.initialKcal;
    final wasteVal = init?.wastePct ?? widget.initialWastePct;

    _initNameText = init?.name ?? widget.initialName;
    _initPText = pVal != null ? CalculationEngine.formatMacro(pVal) : '';
    _initFText = fVal != null ? CalculationEngine.formatMacro(fVal) : '';
    _initCText = cVal != null ? CalculationEngine.formatMacro(cVal) : '';
    _initKcalText = kcalVal != null ? CalculationEngine.formatKcal(kcalVal) : '0';
    _initWasteText = CalculationEngine.formatWastePercent(wasteVal);
    _initIsDishVal = init?.isDishOnly ?? widget.initialIsDish;

    _nameCtrl = TextEditingController(text: _initNameText);
    _pCtrl = TextEditingController(text: _initPText);
    _fCtrl = TextEditingController(text: _initFText);
    _cCtrl = TextEditingController(text: _initCText);
    _kcalCtrl = TextEditingController(text: _initKcalText);
    _wasteCtrl = TextEditingController(text: _initWasteText);
    _isDish = _initIsDishVal;
    _kcalManual = init != null || widget.initialKcal != null;
  }

  bool get _hasUnsavedEdits =>
      _nameCtrl.text != _initNameText ||
      _pCtrl.text != _initPText ||
      _fCtrl.text != _initFText ||
      _cCtrl.text != _initCText ||
      _kcalCtrl.text != _initKcalText ||
      _wasteCtrl.text != _initWasteText ||
      _isDish != _initIsDishVal;

  Future<void> _confirmDiscardAndClose() async {
    if (_saving) return;
    if (!_hasUnsavedEdits) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final p = Palette.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Отменить изменения?'),
        content: const Text(
          'Введённые данные продукта не сохранены и будут потеряны.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Продолжить ввод'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Сбросить и закрыть'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context);
    }
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
      setState(() {
        _error = 'Введите название продукта';
        _errorField = _CustomFieldError.name;
      });
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

    if (prot == null || fat == null || carbs == null) {
      setState(() {
        _error = 'Проверьте числа Б, Ж и У';
        _errorField = _CustomFieldError.macros;
      });
      return;
    }
    if (kcal == null || kcal < 0) {
      setState(() {
        _error = 'Проверьте энергетическую ценность (ккал ≥ 0)';
        _errorField = _CustomFieldError.kcal;
      });
      return;
    }
    if (prot < 0 || fat < 0 || carbs < 0) {
      setState(() {
        _error = 'Значения Б, Ж и У не могут быть отрицательными';
        _errorField = _CustomFieldError.macros;
      });
      return;
    }
    if (prot + fat + carbs > 100.0) {
      setState(() {
        _error = 'Сумма Б + Ж + У на 100 г не должна превышать 100 г';
        _errorField = _CustomFieldError.macros;
      });
      return;
    }
    if (waste == null || waste < 0 || waste >= 100) {
      setState(() {
        _error = 'Отходы должны быть от 0 до 99,9\u202F%';
        _errorField = _CustomFieldError.waste;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _errorField = _CustomFieldError.none;
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
    final stackMacros = AppLayout.shouldStackActions(size.width, textScale);

    Widget numField({
      required Key fieldKey,
      required TextEditingController ctrl,
      required String label,
      bool hasError = false,
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
          error: hasError ? const SizedBox.shrink() : null,
        ),
        onChanged: onChanged,
      );
    }

    void clearError() {
      if (_error != null) {
        _error = null;
        _errorField = _CustomFieldError.none;
      }
    }

    final macroFields = [
      numField(
        fieldKey: const ValueKey('custom-protein'),
        ctrl: _pCtrl,
        label: 'Белки, г',
        hasError: _errorField == _CustomFieldError.macros,
        onChanged: (_) => setState(() {
          clearError();
          _recalcKcalIfAuto();
        }),
      ),
      numField(
        fieldKey: const ValueKey('custom-fat'),
        ctrl: _fCtrl,
        label: 'Жиры, г',
        hasError: _errorField == _CustomFieldError.macros,
        onChanged: (_) => setState(() {
          clearError();
          _recalcKcalIfAuto();
        }),
      ),
      numField(
        fieldKey: const ValueKey('custom-carbs'),
        ctrl: _cCtrl,
        label: 'Углеводы, г',
        hasError: _errorField == _CustomFieldError.macros,
        onChanged: (_) => setState(() {
          clearError();
          _recalcKcalIfAuto();
        }),
      ),
    ];

    final title = widget.sheetTitle ??
        (widget.initial == null
            ? 'Свой продукт (на 100 г)'
            : 'Редактировать продукт');
    final subtitle = widget.sheetSubtitle ??
        'Удобно для продуктов с этикетки или авторских заготовок.';

    final footerWidget = stackMacros
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('custom-save-btn'),
                onPressed: _saving ? null : _submit,
                child: const Text(
                  'Сохранить продукт',
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Space.x1),
              TextButton(
                onPressed: _saving ? null : _confirmDiscardAndClose,
                child: const Text('Отмена'),
              ),
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton(
                  onPressed: _saving ? null : _confirmDiscardAndClose,
                  child: const Text('Отмена'),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('custom-save-btn'),
                    onPressed: _saving ? null : _submit,
                    child: const Text(
                      'Сохранить продукт',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );

    return PopScope(
      canPop: !_hasUnsavedEdits || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscardAndClose();
      },
      child: AppSheetScaffold(
        title: title,
        subtitle: subtitle,
        showHandle: true,
        maxHeightFactor: 0.9,
        noticeText: _error,
        noticeIsError: true,
        bodyPadding:
            const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
        footer: footerWidget,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('custom-name'),
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_errorField == _CustomFieldError.name) {
                  setState(clearError);
                }
              },
              decoration: InputDecoration(
                labelText: 'Название продукта',
                hintText: 'Например, соус терияки',
                errorText: _errorField == _CustomFieldError.name ? _error : null,
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
                hasError: _errorField == _CustomFieldError.kcal,
                onChanged: (_) => setState(() {
                  clearError();
                  _kcalManual = true;
                }),
              ),
              const SizedBox(height: Space.x2),
              numField(
                fieldKey: const ValueKey('custom-waste'),
                ctrl: _wasteCtrl,
                label: 'Отходы, %',
                hasError: _errorField == _CustomFieldError.waste,
                onChanged: (_) => setState(clearError),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: numField(
                      fieldKey: const ValueKey('custom-kcal'),
                      ctrl: _kcalCtrl,
                      label: _kcalManual ? 'Ккал / 100 г' : 'Ккал (авто)',
                      hasError: _errorField == _CustomFieldError.kcal,
                      onChanged: (_) => setState(() {
                        clearError();
                        _kcalManual = true;
                      }),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: numField(
                      fieldKey: const ValueKey('custom-waste'),
                      ctrl: _wasteCtrl,
                      label: 'Отходы, %',
                      hasError: _errorField == _CustomFieldError.waste,
                      onChanged: (_) => setState(clearError),
                    ),
                  ),
                ],
              ),
            if (_kcalManual)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('custom-kcal-recalc-btn'),
                  onPressed: () {
                    AppHaptics.toggle();
                    setState(() {
                      _kcalManual = false;
                      clearError();
                      _recalcKcalIfAuto();
                    });
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  ),
                  icon: const Icon(
                    Icons.calculate_outlined,
                    size: IconSizes.btn,
                  ),
                  label: const Text('Пересчитать по БЖУ'),
                ),
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
          ],
        ),
      ),
    );
  }
}
