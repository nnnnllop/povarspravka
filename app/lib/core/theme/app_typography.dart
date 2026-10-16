import 'package:flutter/material.dart';

class AppTypography {
  static const fontName = 'Arial';

  static TextStyle get headline => const TextStyle(
        fontFamily: fontName,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get titleLarge => const TextStyle(
        fontFamily: fontName,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get titleMedium => const TextStyle(
        fontFamily: fontName,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: fontName,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get bodySmall => const TextStyle(
        fontFamily: fontName,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
      );

  /// Числовые показатели в таблицах и карточках со строгим табличным выравниванием
  static TextStyle get numeric => const TextStyle(
        fontFamily: fontName,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      );

  static TextStyle get numericLarge => const TextStyle(
        fontFamily: fontName,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
        letterSpacing: -0.5,
      );

  static TextStyle get numericSmall => const TextStyle(
        fontFamily: fontName,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
      );
}
