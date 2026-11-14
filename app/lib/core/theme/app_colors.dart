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
  // ─── Основа: утилитарный монохром ────────────────────────────────────────
  static const canvas = Color(0xFFF7F6F3); // фон рабочей области
  static const surface = Color(0xFFFFFFFF); // карточка / лист
  static const surfaceSunken = Color(0xFFF0EFEA); // вложенные поля ввода

  static const canvasDark = Color(0xFF141413);
  static const surfaceDark = Color(0xFF1C1C1A);
  static const surfaceSunkenDark = Color(0xFF111110);
  static const surfaceRaisedDark = Color(0xFF242422);

  // ─── Границы ────────────────────────────────────────────────────────────
  /// 3.36:1 к canvas — для ГРАНИЦ ИНТЕРАКТИВНЫХ компонентов (WCAG 1.4.11):
  /// поля, кнопки, чипы, клавиши.
  static const border = Color(0xFF88857E);

  /// Декоративные контуры карточек: тонкий 1px контур.
  static const borderStatic = Color(0xFFE2E0DA);

  /// ТОЛЬКО внутренние линии (разделители внутри одного смыслового блока).
  static const divider = Color(0xFFEBE9E3);

  /// 3.33:1 к surfaceDark — интерактивные границы в тёмной теме.
  static const borderDark = Color(0xFF706E69);
  static const borderStaticDark = Color(0xFF2E2E2B);
  static const dividerDark = Color(0xFF282825);

  // ─── Тушь (текст) ───────────────────────────────────────────────────────
  static const ink = Color(0xFF181817); // >16:1 на canvas
  static const inkSecondary = Color(0xFF575550); // 6.7:1 на canvas
  static const inkMuted = Color(0xFF66635E); // 5.55:1 на canvas

  static const inkDark = Color(0xFFF3F2EE);
  static const inkSecondaryDark = Color(0xFFB3B0A8); // 7.8:1 на surfaceDark
  static const inkMutedDark = Color(0xFF928F88); // 5.2:1 на surfaceDark

  // ─── Акцент: строгий угольный графит (действие / фокус) ─────────────────
  static const accent = Color(0xFF1E1D1B); // >15:1 к canvas/surface
  static const accentOn = Color(0xFFFFFFFF); // текст на accent
  static const accentSoft = Color(0xFFECEAE4); // фон активного сегмента/чипа
  static const accentSoftDark = Color(0xFF2A2926);

  static const accentDark = Color(0xFFEAE6DF); // >12:1 на surfaceDark
  static const accentOnDark = Color(0xFF1A1917);

  // ─── Макросы: ТОЛЬКО текст и 2 dp маркер. НЕ заливки ────────────────────
  static const protein = Color(0xFF2F6B3A); // 6.39:1 на белом
  static const fat = Color(0xFF8A5A00); // 5.93:1 на белом
  static const carbs = Color(0xFF1F4E79); // 8.66:1 на белом
  static const kcal = Color(0xFF9A2C1B); // 7.64:1 на белом

  static const proteinDark = Color(0xFF8FD0A0);
  static const fatDark = Color(0xFFE4B96B);
  static const carbsDark = Color(0xFF9CC0E8);
  static const kcalDark = Color(0xFFF09A88);

  // ─── Источник: ТОЛЬКО нейтральный контур. Не цвет — а слово ─────────────
  static const sourceInk = Color(0xFF4A463F);
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
