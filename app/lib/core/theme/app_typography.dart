import 'package:flutter/material.dart';

/// Типографическая шкала (аудит §3.5).
///
/// Правила:
/// * 7 размеров максимум: 28 / 20 / 16 / 15 / 13 / 12 / 11.
/// * Только два реальных веса — 400 и 700 (в сборке объявлены `arial.ttf` и
///   `arialbd.ttf`). `w600` и `w800` синтезировались движком двумя разными
///   путями и давали «то жирные, то жирнее» заголовки — они изгнаны.
/// * Меньше 11 px в интерфейсе нельзя; 8.5–9.5 px — только в бланке,
///   потому что так на бумаге.
class AppTypography {
  /// Основной интерфейсный шрифт.
  static const fontName = 'Arial';

  /// Шрифт бланка: обязан совпадать с печатным типовым бланком.
  static const instrumentFont = 'Arial';

  static const List<FontFeature> _tnum = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  // ─── Дисплей: одно значение на экран, только для числа-ответа ───────────
  static const TextStyle display = TextStyle(
    fontFamily: fontName,
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontName,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: fontName,
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontName,
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: fontName,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontName,
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontName,
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.3,
  );

  // ─── Числа: всегда tabular figures ──────────────────────────────────────
  static const TextStyle numLg = TextStyle(
    fontFamily: fontName,
    fontSize: 34,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    fontFeatures: _tnum,
  );

  static const TextStyle num = TextStyle(
    fontFamily: fontName,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w700,
    fontFeatures: _tnum,
  );

  static const TextStyle numSm = TextStyle(
    fontFamily: fontName,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
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
