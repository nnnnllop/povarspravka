import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 4-dp сетка отступов (аудит §3.3).
///
/// Правило: внутри карточки — [x3] (12), между карточками — [x2] (8),
/// между секциями — [x6] (24). Никаких 6/10/14/18/22 — восемь значений на
/// одном экране и есть «визуальный дребезг».
class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;

  static const double maxWidth = 640;

  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: x4);
  static const EdgeInsets card = EdgeInsets.all(x3);
  static const EdgeInsets sheet = EdgeInsets.fromLTRB(x4, x3, x4, x4);

  /// Горизонтальный отступ экрана: 16 (узкий) → 20 (≥400 dp).
  static double gutter(double width) => width >= 400 ? x5 : x4;
}

/// Радиусы (аудит §3.4).
class Radii {
  static const double chip = 6;
  static const double field = 10;
  static const double card = 14;
  static const double sheet = 20;
  static const double dialog = 16;

  static const BorderRadius chipAll = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius fieldAll = BorderRadius.all(Radius.circular(field));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
}

/// Минимальный тап-таргет (WCAG 2.5.5 / Material).
const double kMinTapTarget = 48;

/// Motion-токены (аудит §3.7).
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const sheet = Duration(milliseconds: 280);

  static const Curve ease = Curves.easeOutCubic;
}

/// Семантические цвета, разрешённые по яркости один раз на `build`.
///
/// Это убирает «айрон-хват» из ~174 инлайн-веток `isDark ? A : B` в каждом
/// виджете: одна точка правды на тему.
class Palette {
  final bool isDark;
  const Palette(this.isDark);

  factory Palette.of(BuildContext context) =>
      Palette(Theme.of(context).brightness == Brightness.dark);

  Color get canvas => isDark ? AppColors.canvasDark : AppColors.canvas;
  Color get surface => isDark ? AppColors.surfaceDark : AppColors.surface;
  Color get sunken =>
      isDark ? AppColors.surfaceSunkenDark : AppColors.surfaceSunken;

  /// Интерактивные границы (>= 3:1 WCAG 1.4.11).
  Color get border => isDark ? AppColors.borderDark : AppColors.border;

  /// Декоративные контуры карточек: тонкий 1px контур.
  Color get borderStatic =>
      isDark ? AppColors.borderStaticDark : AppColors.borderStatic;

  Color get divider => isDark ? AppColors.dividerDark : AppColors.divider;

  Color get ink => isDark ? AppColors.inkDark : AppColors.ink;
  Color get inkSecondary =>
      isDark ? AppColors.inkSecondaryDark : AppColors.inkSecondary;
  Color get inkMuted => isDark ? AppColors.inkMutedDark : AppColors.inkMuted;

  Color get accent => isDark ? AppColors.accentDark : AppColors.accent;
  Color get onAccent => isDark ? AppColors.accentOnDark : AppColors.accentOn;
  Color get accentSoft =>
      isDark ? AppColors.accentSoftDark : AppColors.accentSoft;

  Color get protein => isDark ? AppColors.proteinDark : AppColors.protein;
  Color get fat => isDark ? AppColors.fatDark : AppColors.fat;
  Color get carbs => isDark ? AppColors.carbsDark : AppColors.carbs;
  Color get kcal => isDark ? AppColors.kcalDark : AppColors.kcal;

  Color get sourceInk => isDark ? AppColors.sourceInkDark : AppColors.sourceInk;
  Color get sourceLine =>
      isDark ? AppColors.sourceLineDark : AppColors.sourceLine;

  Color get danger => isDark ? AppColors.dangerDark : AppColors.danger;
  Color get dangerSoft =>
      isDark ? AppColors.dangerSoftDark : AppColors.dangerSoft;
  Color get warning => isDark ? AppColors.warningDark : AppColors.warning;
  Color get warningSoft =>
      isDark ? AppColors.warningSoftDark : AppColors.warningSoft;
  Color get success => isDark ? AppColors.successDark : AppColors.success;
}
