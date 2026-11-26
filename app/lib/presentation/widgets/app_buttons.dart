import 'dart:io' show FileSystemException;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;

import '../../core/theme/app_space.dart';
import '../../core/theme/app_theme.dart';

export 'nutrient_chip.dart' show InlineMacroCell, NutrientChip, NutrientType;

/// Центрирует контент в колонке шириной не более [Space.maxWidth] (640 dp)
/// на планшетах и в альбомной ориентации.
class AppContentFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const AppContentFrame({
    super.key,
    required this.child,
    this.maxWidth = Space.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Единый нижний док с SafeArea и ограничением ширины до [Space.maxWidth] —
/// либо плоский с 1 px разделителем, либо в виде парящей швейцарской капсулы
/// (`floating: true`).
class AppBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool floating;

  const AppBottomBar({
    super.key,
    required this.child,
    this.padding,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Space.gutter(width);

    if (floating) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(hPad, Space.x1, hPad, Space.x2),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Space.maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.isDark ? p.raised : p.surface,
                  borderRadius: Radii.dockAll,
                  border: Border.all(
                    color: p.borderStatic.withOpacity(p.isDark ? 0.9 : 0.75),
                  ),
                  boxShadow: p.isDark
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x16000000),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ],
                ),
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(Space.x2),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding:
              padding ??
              EdgeInsets.symmetric(horizontal: hPad, vertical: Space.x2),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Space.maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Унифицированный стиль [SegmentedButton] для всей дизайн-системы:
/// 48 dp минимальная высота, 1 px граница >= 3:1, активный сегмент — [Palette.accent],
/// неактивный — [Palette.sunken]. Единая точка правды с [AppTheme.segmentedStyle].
class AppSegmentedStyle {
  const AppSegmentedStyle._();

  static ButtonStyle of(Palette p, {bool compact = false}) =>
      AppTheme.segmentedStyle(p, compact: compact);
}

/// Лёгкий тактильный отклик нажатия (`scale: 0.97` за [Motion.fast]).
///
/// Использует [Listener], чтобы не конкурировать на арене жестов и не вносить
/// задержку нажатия в [InkWell], кнопки или клавиши нумпада. При скролле/свайпе
/// (сдвиг дальше [kTouchSlop]) и при `MediaQuery.disableAnimationsOf(context)`
/// анимация корректно сбрасывается / отключается.
class TactilePress extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;

  const TactilePress({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<TactilePress> createState() => _TactilePressState();
}

class _TactilePressState extends State<TactilePress> {
  bool _pressed = false;
  int? _activePointer;
  Offset? _downPosition;

  @override
  void didUpdateWidget(covariant TactilePress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
      _activePointer = null;
      _downPosition = null;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _activePointer != null) return;
    _activePointer = event.pointer;
    _downPosition = event.position;
    if (!_pressed) setState(() => _pressed = true);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _downPosition == null) return;
    if ((event.position - _downPosition!).distance > kTouchSlop) {
      _release(event.pointer);
    }
  }

  void _release(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    _downPosition = null;
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final targetScale =
        (!disableAnimations && widget.enabled && _pressed) ? widget.scale : 1.0;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (e) => _release(e.pointer),
      onPointerCancel: (e) => _release(e.pointer),
      child: AnimatedScale(
        scale: targetScale,
        duration: disableAnimations ? Duration.zero : Motion.fast,
        curve: Motion.ease,
        child: widget.child,
      ),
    );
  }
}

/// Человеческое склонение количества ингредиентов:
/// «1 ингредиент», «2 ингредиента», «5 ингредиентов».
String pluralIngredients(int count) {
  final n = count.abs();
  final mod100 = n % 100;
  final mod10 = n % 10;
  if (mod100 >= 11 && mod100 <= 14) {
    return '$count ингредиентов';
  }
  if (mod10 == 1) {
    return '$count ингредиент';
  }
  if (mod10 >= 2 && mod10 <= 4) {
    return '$count ингредиента';
  }
  return '$count ингредиентов';
}

/// Безопасный пользовательский текст ошибки без сырых исключений (`$e`),
/// путей ОС и stack trace.
String friendlyErrorMessage(
  Object error, {
  String? prefix,
  String fallback = 'Не удалось выполнить действие. Попробуйте ещё раз.',
}) {
  final String? reason;
  if (error is FileSystemException) {
    final code = error.osError?.errorCode;
    if (code == 28 || code == 112) {
      reason = 'недостаточно свободного места на устройстве';
    } else if (code == 13 || code == 1 || code == 5) {
      reason = 'нет доступа к файлу или папке сохранения';
    } else {
      reason = 'ошибка при работе с файлами устройства';
    }
  } else if (error is FormatException) {
    reason = 'некорректный формат данных';
  } else if (error is ArgumentError || error is RangeError) {
    reason = 'проверьте введённые числа и параметры';
  } else if (error is StateError) {
    reason = 'действие сейчас недоступно';
  } else if (error is MissingPluginException || error is PlatformException) {
    reason = 'операция не поддерживается на этом устройстве';
  } else {
    reason = null;
  }

  final cleanPrefix = prefix?.trim();
  if (cleanPrefix != null && cleanPrefix.isNotEmpty) {
    return reason != null
        ? '$cleanPrefix: $reason.'
        : '$cleanPrefix. Попробуйте ещё раз.';
  }
  if (reason != null) {
    return '${reason[0].toUpperCase()}${reason.substring(1)}.';
  }
  return fallback;
}
