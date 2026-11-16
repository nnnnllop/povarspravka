import 'package:flutter/material.dart';

/// Типографическая шкала приложения «Поварская справка».
///
/// Интерфейс использует системный шрифт платформы (Roboto / SF Pro) с естественными
/// весами `w400` / `w500` / `w600` / `w700`. Шрифт `Arial` сохранён только для
/// печатного и экранного бланка (`instrumentFont`), где требуется точное
/// совпадение с типовым документом.
class AppTypography {
  /// Системный интерфейсный шрифт (`null` = нативный шрифт платформы).
  static const String? fontName = null;

  /// Шрифт бланка: обязан совпадать с печатным типовым бланком.
  static const instrumentFont = 'Arial';

  static const List<FontFeature> _tnum = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ─── Дисплей: одно ключевое число на экран ──────────────────────────────
  static const TextStyle display = TextStyle(
    fontFamily: fontName,
    fontSize: 26,
    height: 1.18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    fontFeatures: _tnum,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontName,
    fontSize: 20,
    height: 1.24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    fontFeatures: _tnum,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: fontName,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    fontFeatures: _tnum,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontName,
    fontSize: 15,
    height: 1.42,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: fontName,
    fontSize: 13.5,
    height: 1.38,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontName,
    fontSize: 13.5,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontName,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  // ─── Числа: всегда tabular figures ──────────────────────────────────────
  static const TextStyle numLg = TextStyle(
    fontFamily: fontName,
    fontSize: 32,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFeatures: _tnum,
  );

  static const TextStyle num = TextStyle(
    fontFamily: fontName,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFeatures: _tnum,
  );

  static const TextStyle numSm = TextStyle(
    fontFamily: fontName,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    fontFeatures: _tnum,
  );

  // ─── Обратная совместимость (используется в существующих виджетах) ──────
  static TextStyle get titleLarge => title;
  static TextStyle get titleMedium => headline;
  static TextStyle get bodyMedium => body;
  static TextStyle get bodySmall => bodySm;
  static TextStyle get numeric => num;
  static TextStyle get numericLarge => numLg;
  static TextStyle get numericSmall => numSm;
}
