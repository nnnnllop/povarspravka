import 'package:flutter/material.dart';

/// Типографическая шкала приложения «Поварская справка».
///
/// Интерфейс использует встроенный офлайн-шрифт `Inter` с табличными цифрами
/// (`tabularFigures`) и выразительным диапазоном размеров (`12–34 sp`).
/// Шрифт `Arial` сохранён только для печатного и экранного бланка (`instrumentFont`),
/// где требуется точное совпадение с типовым документом.
class AppTypography {
  /// Интерфейсный шрифт (`Inter`, встроен в APK для стабильного рендера).
  static const String? fontName = 'Inter';

  /// Шрифт бланка: обязан совпадать с печатным типовым бланком.
  static const instrumentFont = 'Arial';

  static const List<FontFeature> _tnum = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ─── Дисплей: главное число экрана ──────────────────────────────────────
  static const TextStyle display = TextStyle(
    fontFamily: fontName,
    fontSize: 30,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    fontFeatures: _tnum,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontName,
    fontSize: 21,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.35,
    fontFeatures: _tnum,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: fontName,
    fontSize: 16,
    height: 1.28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.15,
    fontFeatures: _tnum,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontName,
    fontSize: 15,
    height: 1.4,
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
    letterSpacing: 0.05,
  );

  // ─── Числа: всегда tabular figures ──────────────────────────────────────
  static const TextStyle numLg = TextStyle(
    fontFamily: fontName,
    fontSize: 34,
    height: 1.04,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.7,
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
