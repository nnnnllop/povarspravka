import 'package:flutter/material.dart';

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

  Color get canvas => isDark ? const Color(0xFF131311) : const Color(0xFFF7F5F1);
  Color get surface => isDark ? const Color(0xFF1B1B19) : const Color(0xFFFFFFFF);
  Color get sunken => isDark ? const Color(0xFF101010) : const Color(0xFFF1EEE8);

  /// Интерактивные границы: 3.02:1 (WCAG 1.4.11).
  Color get border => isDark ? const Color(0xFF6A665E) : const Color(0xFF948D82);

  /// Декоративные контуры карточек: осознанно мягкие.
  Color get borderStatic =>
      isDark ? const Color(0xFF3A3833) : const Color(0xFFDDD8CF);

  Color get divider => isDark ? const Color(0xFF2A2925) : const Color(0xFFECE8E1);

  Color get ink => isDark ? const Color(0xFFF3F1ED) : const Color(0xFF1A1917);
  Color get inkSecondary =>
      isDark ? const Color(0xFFB3AEA5) : const Color(0xFF5C5852);
  Color get inkMuted => isDark ? const Color(0xFF8F8A81) : const Color(0xFF6B665D);

  Color get accent => isDark ? const Color(0xFFE9B872) : const Color(0xFF9A5B14);
  Color get onAccent =>
      isDark ? const Color(0xFF1A1917) : const Color(0xFFFFFBF5);
  Color get accentSoft =>
      isDark ? const Color(0xFF2C2216) : const Color(0xFFF6EEDF);

  Color get protein => isDark ? const Color(0xFF8FD0A0) : const Color(0xFF2F6B3A);
  Color get fat => isDark ? const Color(0xFFE4B96B) : const Color(0xFF8A5A00);
  Color get carbs => isDark ? const Color(0xFF9CC0E8) : const Color(0xFF1F4E79);
  Color get kcal => isDark ? const Color(0xFFF09A88) : const Color(0xFF9A2C1B);

  Color get sourceInk =>
      isDark ? const Color(0xFFCFCAC0) : const Color(0xFF4A463F);
  Color get sourceLine =>
      isDark ? const Color(0xFF3A3833) : const Color(0xFFDDD8CF);

  Color get danger => isDark ? const Color(0xFFF0A0A0) : const Color(0xFF9B1C1C);
  Color get dangerSoft =>
      isDark ? const Color(0xFF2C1919) : const Color(0xFFFBEAEA);
  Color get warning => isDark ? const Color(0xFFE9B872) : const Color(0xFF7A4E00);
  Color get warningSoft =>
      isDark ? const Color(0xFF2C2216) : const Color(0xFFFDF3DC);
  Color get success => isDark ? const Color(0xFF8FD0A0) : const Color(0xFF1F6B3E);
}
