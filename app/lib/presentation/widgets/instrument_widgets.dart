import 'package:flutter/material.dart';

import '../../core/theme/app_space.dart';

/// Приборная плита (`#15171A` в светлой / `#1E2126` в тёмной теме)
/// со скруглениями в духе Material 3 / iOS (`R = 20 dp`).
class InstrumentSlab extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Color? color;

  const InstrumentSlab({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final radius = borderRadius ?? Radii.slabAll;
    final bg = color ?? p.slab;

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(
          color: p.slabEdge.withOpacity(p.isDark ? 0.9 : 0.65),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap != null
            ? InkWell(
                onTap: onTap,
                splashColor: Colors.white.withOpacity(0.08),
                highlightColor: Colors.white.withOpacity(0.04),
                child: content,
              )
            : content,
      ),
    );
  }
}

/// Чистая сгруппированная поверхность без жёсткой сетки рамок (`R = 16 dp`).
class GroupedSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  const GroupedSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final radius = borderRadius ?? Radii.cardAll;
    final bg = color ?? p.surface;

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: p.isDark
            ? Border.all(color: p.borderStatic.withOpacity(0.8), width: 1)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap != null ? InkWell(onTap: onTap, child: content) : content,
      ),
    );
  }
}

/// Калибровочная сигнальная точка прибора (`#FF6A1F` / `#FF8A4C`).
class SignalDot extends StatelessWidget {
  final Color? color;
  final double size;
  final bool glow;

  const SignalDot({
    super.key,
    this.color,
    this.size = 7,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.signal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: c.withOpacity(0.42),
                  blurRadius: 6,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Декоративная микрометрическая линейка делений для приборной плиты.
class RulerTicks extends StatelessWidget {
  final Color color;
  final double height;
  final int ticks;
  final int majorEvery;

  const RulerTicks({
    super.key,
    required this.color,
    this.height = 6,
    this.ticks = 25,
    this.majorEvery = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _RulerTicksPainter(
          color: color,
          ticks: ticks,
          majorEvery: majorEvery,
        ),
      ),
    );
  }
}

class _RulerTicksPainter extends CustomPainter {
  final Color color;
  final int ticks;
  final int majorEvery;

  const _RulerTicksPainter({
    required this.color,
    required this.ticks,
    required this.majorEvery,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ticks < 2 || size.width <= 0) return;
    final minorPaint = Paint()
      ..color = color.withOpacity(0.28)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = color.withOpacity(0.58)
      ..strokeWidth = 1.25;

    final step = size.width / (ticks - 1);
    for (int i = 0; i < ticks; i++) {
      final x = (i * step).clamp(0.5, size.width - 0.5);
      final isMajor = i % majorEvery == 0;
      final tickH = isMajor ? size.height : size.height * 0.55;
      canvas.drawLine(
        Offset(x, size.height - tickH),
        Offset(x, size.height),
        isMajor ? majorPaint : minorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RulerTicksPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.ticks != ticks ||
      oldDelegate.majorEvery != majorEvery;
}

/// Штрихованная полоса статуса (для состояний без валидного расчёта выхода).
class HatchedBar extends StatelessWidget {
  final Color color;
  final Color? backgroundColor;
  final double height;

  const HatchedBar({
    super.key,
    required this.color,
    this.backgroundColor,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HatchedBarPainter(
            color: color,
            backgroundColor: backgroundColor ?? p.slabSurface,
          ),
        ),
      ),
    );
  }
}

class _HatchedBarPainter extends CustomPainter {
  final Color color;
  final Color backgroundColor;

  const _HatchedBarPainter({
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = backgroundColor,
    );
    final stripePaint = Paint()
      ..color = color.withOpacity(0.62)
      ..strokeWidth = 2;
    const stride = 7.0;
    for (double x = -size.height; x < size.width + size.height; x += stride) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchedBarPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.backgroundColor != backgroundColor;
}

/// Плавная анимация числового значения без бесконечного тикера.
class AnimatedMetricText extends StatelessWidget {
  final double value;
  final String Function(double animatedValue) formatter;
  final TextStyle style;
  final int maxLines;

  const AnimatedMetricText({
    super.key,
    required this.value,
    required this.formatter,
    required this.style,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnimations) {
      return Text(
        formatter(value),
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: Motion.base,
      curve: Motion.ease,
      builder: (context, animatedValue, _) {
        return Text(
          formatter(animatedValue),
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Фирменная векторная эмблема весов для шапки главной библиотеки.
class AppScaleGlyph extends StatelessWidget {
  final double size;

  const AppScaleGlyph({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScaleGlyphPainter(
          ink: p.ink,
          accent: p.accent,
        ),
      ),
    );
  }
}

class _ScaleGlyphPainter extends CustomPainter {
  final Color ink;
  final Color accent;

  const _ScaleGlyphPainter({
    required this.ink,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = size.width * 0.5;
    final top = size.height * 0.22;
    final base = size.height * 0.84;

    // Вертикальная стойка и основание весов
    canvas.drawLine(Offset(cx, top), Offset(cx, base), stroke);
    canvas.drawLine(
      Offset(size.width * 0.24, base),
      Offset(size.width * 0.76, base),
      stroke,
    );

    // Коромысло весов
    final left = Offset(size.width * 0.16, size.height * 0.34);
    final right = Offset(size.width * 0.84, size.height * 0.28);
    canvas.drawLine(left, right, stroke);

    // Две дуги-чаши
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(left.dx, left.dy + size.height * 0.24),
        width: size.width * 0.28,
        height: size.height * 0.14,
      ),
      0,
      3.14159,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(right.dx, right.dy + size.height * 0.24),
        width: size.width * 0.28,
        height: size.height * 0.14,
      ),
      0,
      3.14159,
      false,
      stroke,
    );

    // Точка калибровки шалфейного цвета на центральной оси
    canvas.drawCircle(
      Offset(cx, top),
      size.width * 0.085,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _ScaleGlyphPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.accent != accent;
}
