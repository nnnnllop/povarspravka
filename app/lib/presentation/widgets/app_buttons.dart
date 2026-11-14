import 'package:flutter/material.dart';

import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

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

/// Единый плоский нижний док с 1 px верхним разделителем, SafeArea
/// и ограничением ширины до [Space.maxWidth] — без теней и плавающих FAB.
class AppBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AppBottomBar({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Space.gutter(width);

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
/// 48 dp минимальная высота, 1 px граница 3:1, активный сегмент — [Palette.accent].
class AppSegmentedStyle {
  const AppSegmentedStyle._();

  static ButtonStyle of(Palette p, {bool compact = false}) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, kMinTapTarget)),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? Space.x2 : Space.x3,
          vertical: Space.x2,
        ),
      ),
      textStyle: WidgetStatePropertyAll(AppTypography.label),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.accent;
        return p.surface;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.onAccent;
        return p.ink;
      }),
      side: WidgetStatePropertyAll(BorderSide(color: p.border)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: Radii.fieldAll),
      ),
    );
  }
}
