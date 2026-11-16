import 'package:flutter/material.dart';

/// Калиброванная палитра приложения «Поварская справка».
///
/// Принцип (см. `docs/DESIGN_UX_AUDIT.md` §3.1, правило R1):
/// **одна ось цвета = один смысл.** Три системы — бренд / данные / источник —
/// не пересекаются по хью.
///
/// Все пары «текст/фон» измерены по WCAG 2.1, все значения проходят AA (4.5:1)
/// либо 3:1 для интерактивных границ (1.4.11).
class AppColors {
  // ─── Основа: тёплая нейтральная палитра и один спокойный акцент ────────
  static const canvas = Color(0xFFF4F3EF); // тёплый нейтральный фон экранов
  static const surface = Color(0xFFFFFFFF); // чистые карточки и шиты
  static const surfaceSunken = Color(0xFFEBE9E2); // утопленные поля и пилюли

  static const canvasDark = Color(0xFF121413);
  static const surfaceDark = Color(0xFF1B1E1C);
  static const surfaceSunkenDark = Color(0xFF141615);
  static const surfaceRaisedDark = Color(0xFF242825);

  // ─── Границы и внутренние разделители ───────────────────────────────────
  /// ≥ 3:1 для границ настоящих интерактивных контролов (поля, кнопки).
  static const border = Color(0xFF7B7F7A);

  /// Мягкая разделительная/контурная линия без тяжёлой «решётки».
  static const borderStatic = Color(0xFFE2E0D8);

  /// Внутренний деликатный разделитель строк внутри одной группы.
  static const divider = Color(0xFFECEAE3);

  /// ≥ 3:1 к surfaceDark в тёмной теме.
  static const borderDark = Color(0xFF717671);
  static const borderStaticDark = Color(0xFF2C302D);
  static const dividerDark = Color(0xFF272B28);

  // ─── Текст (весь текст ≥ 4.5:1 AA на canvas и surface) ──────────────────
  static const ink = Color(0xFF171918); // >15:1 на canvas
  static const inkSecondary = Color(0xFF4F5450); // ~7.0:1 на canvas
  static const inkMuted = Color(0xFF616560); // ~5.28:1 на canvas

  static const inkDark = Color(0xFFF2F3F0);
  static const inkSecondaryDark = Color(0xFFB4B8B2);
  static const inkMutedDark = Color(0xFF939891);

  // ─── Главный акцент: глубокий кулинарный зелёный (хвоя / шалфей) ────────
  static const accent = Color(0xFF1E5C45); // >7.0:1 на canvas, >7.8:1 на белом
  static const accentOn = Color(0xFFFFFFFF); // текст на accent
  static const accentSoft = Color(0xFFE5F0EB); // мягкий фон активных пилюль
  static const accentSoftDark = Color(0xFF21312A);

  static const accentDark = Color(0xFF82C4A6); // >8:1 на surfaceDark
  static const accentOnDark = Color(0xFF0E1D16);

  // ─── Нутриенты: чистый типографический акцент, все ≥ 4.5:1 ──────────────
  static const protein = Color(0xFF285F3C);
  static const fat = Color(0xFF8C5600);
  static const carbs = Color(0xFF1E4E79);
  static const kcal = Color(0xFF9C2C1C);

  static const proteinDark = Color(0xFF8FD0A0);
  static const fatDark = Color(0xFFE4B96B);
  static const carbsDark = Color(0xFF9CC0E8);
  static const kcalDark = Color(0xFFF09A88);

  // ─── Бейдж источника: спокойный нейтральный тон ─────────────────────────
  static const sourceInk = Color(0xFF42413C);
  static const sourceLine = borderStatic;
  static const sourceInkDark = Color(0xFFCFCAC0);
  static const sourceLineDark = borderStaticDark;

  // ─── Статусы: единственные места, где допустим красный/зелёный ──────────
  static const danger = Color(0xFF9B1C1C);
  static const dangerSoft = Color(0xFFFBEAEA);
  static const dangerDark = Color(0xFFF0A0A0);
  static const dangerSoftDark = Color(0xFF2C1919);
  static const warning = Color(0xFF7A4E00);
  static const warningSoft = Color(0xFFFDF3DC);
  static const warningDark = Color(0xFFE9B872);
  static const warningSoftDark = Color(0xFF2C2216);
  static const success = Color(0xFF1F6B3E);
  static const successDark = Color(0xFF8FD0A0);

  // ─── Бланк: «бумажная» палитра. Привязана к печати — НЕ трогать ─────────
  static const paper = Color(0xFFFFFFFF);
  static const paperInk = Color(0xFF000000);
  static const paperRule = Color(0xFF000000);
  static const paperHeader = Color(0xFFFFFFFF); // #F8FAFC давал серую грязь

  // ─── Backward-compatible алиасы (переименованы в новые токены) ──────────
  static const backgroundLight = canvas;
  static const surfaceLight = surface;
  static const cardLight = surface;
  static const cardDark = surfaceDark;

  static const borderLight = border;
  static const borderSubtleLight = divider;
  static const backgroundDark = canvasDark;
  static const borderSubtleDark = dividerDark;

  /// Акцент бренда: раньше был `#B45309` — то же значение, что и `fat`.
  /// Теперь это настоящий янтарь `#9A5B14`.
  static const primary = ink;
  static const primaryLight = Color(0xFFE7E5E4);
  static const primaryContainerLight = surfaceSunken;
  static const primaryContainerDark = surfaceRaisedDark;

  static const accentLight = accentSoft;
  static const error = danger;
  static const errorLight = dangerSoft;
  static const errorBgLight = dangerSoft;
  static const errorTextLight = danger;

  static const textPrimaryLight = ink;
  static const textSecondaryLight = inkSecondary;
  static const textMutedLight = inkMuted; // было #9E988F — 2.72:1 (провал AA)
  static const textPrimaryDark = inkDark;
  static const textSecondaryDark = inkSecondaryDark;
  static const textMutedDark = inkMutedDark;

  // Старые макросы-заливки остались только для обратной совместимости
  // API — но UI их больше не использует (правило R2).
  static const proteinLight = Color(0xFFEDF5EE);
  static const proteinBgLight = Color(0xFFEDF5EE);
  static const proteinTextLight = Color(0xFF225828);
  static const proteinBorderLight = Color(0xFFD4E7D6);
  static const proteinBgDark = Color(0xFF19281C);
  static const proteinTextDark = proteinDark;
  static const proteinBorderDark = Color(0xFF27422B);

  static const fatLight = Color(0xFFFAF3E8);
  static const fatBgLight = Color(0xFFFAF3E8);
  static const fatTextLight = Color(0xFF8C5815);
  static const fatBorderLight = Color(0xFFF3E4CD);
  static const fatBgDark = Color(0xFF2A2216);
  static const fatTextDark = fatDark;
  static const fatBorderDark = Color(0xFF43341E);

  static const carbsLight = Color(0xFFEEF3F9);
  static const carbsBgLight = Color(0xFFEEF3F9);
  static const carbsTextLight = Color(0xFF244F7D);
  static const carbsBorderLight = Color(0xFFD5E3F3);
  static const carbsBgDark = Color(0xFF162230);
  static const carbsTextDark = carbsDark;
  static const carbsBorderDark = Color(0xFF26394F);

  static const kcalLight = Color(0xFFFBF0EE);
  static const kcalBgLight = dangerSoft;
  static const kcalTextLight = kcal;
  static const kcalBorderLight = Color(0xFFF3D4CF);
  static const kcalBgDark = dangerSoftDark;
  static const kcalTextDark = kcalDark;
  static const kcalBorderDark = Color(0xFF482927);

  // Источники: раньше «Скурихин» == «жиры», «USDA» == «углеводы». Коллизия
  // снята — оба источника живут на нейтральном контуре.
  static const badgeSkurikhin = sourceInk;
  static const badgeSkurikhinBg = surface;
  static const badgeSkurikhinBorder = sourceLine;
  static const badgeUsda = sourceInk;
  static const badgeUsdaBg = surface;
  static const badgeUsdaBorder = sourceLine;
}
