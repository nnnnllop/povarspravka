import 'package:flutter/material.dart';

/// Калиброванная палитра «Прибор» (Instrument · Sage) для «Поварской справки».
///
/// Светлая тема: тёплый приборный холст (`#F2F2EF`), чисто-белые сгруппированные
/// поверхности (`#FFFFFF`), графитовая приборная плита (`#15171A`) и глубокий
/// шалфейный акцент (`#1D5E46`).
/// Тёмная тема: `#0B0C0E` + `#17191D` + приподнятая плита `#1E2126` + мятный
/// шалфей (`#6FD09C`).
///
/// Все пары «текст/фон» измерены по WCAG 2.1, все значения проходят AA (4.5:1)
/// либо 3:1 для интерактивных границ (1.4.11).
class AppColors {
  // ─── Основа: тёплый приборный холст и шалфейный акцент ───────────────────
  static const canvas = Color(0xFFF2F2EF); // тёплый матовый фон экранов
  static const surface = Color(0xFFFFFFFF); // сгруппированные карточки и шиты
  static const surfaceSunken = Color(0xFFE7E7E2); // утопленные поля и клавиши

  static const canvasDark = Color(0xFF0B0C0E);
  static const surfaceDark = Color(0xFF17191D);
  static const surfaceSunkenDark = Color(0xFF101215);
  static const surfaceRaisedDark = Color(0xFF1F2228);

  // ─── Приборная плита (Hero / Readout / Меню) ─────────────────────────────
  static const slab = Color(0xFF15171A);
  static const slabInk = Color(0xFFF7F7F8);
  static const slabSecondary = Color(0xFFA3A9B3);
  static const slabEdge = Color(0xFF2A2E36);
  static const slabSurface = Color(0xFF23262C);
  static const signal = Color(0xFFFF6A1F);
  static const sheetHandle = Color(0xFFB8BCC4);

  static const slabDark = Color(0xFF1E2126);
  static const slabInkDark = Color(0xFFF7F7F8);
  static const slabSecondaryDark = Color(0xFFAEB4BE);
  static const slabEdgeDark = Color(0xFF2E333B);
  static const slabSurfaceDark = Color(0xFF2A2D33);
  static const signalDark = Color(0xFFFF8A4C);
  static const sheetHandleDark = Color(0xFF3B404A);

  // ─── Границы и внутренние разделители ───────────────────────────────────
  /// ≥ 3:1 на canvas/surface (для доступности интерактивных границ).
  static const border = Color(0xFF6B7079);

  /// Деликатный hairline-контур и неактивный ободок.
  static const borderStatic = Color(0xFFD9DAD5);

  /// Внутренний разделитель строк внутри сгруппированной поверхности.
  static const divider = Color(0xFFE3E4DF);

  /// ≥ 3:1 к surfaceDark в тёмной теме.
  static const borderDark = Color(0xFF737A86);
  static const borderStaticDark = Color(0xFF262A31);
  static const dividerDark = Color(0xFF262A31);

  // ─── Текст (весь текст ≥ 4.5:1 AA на canvas и surface) ──────────────────
  static const ink = Color(0xFF111214); // >17:1 на белом
  static const inkSecondary = Color(0xFF4B4F56); // ~7.4:1 на canvas
  static const inkMuted = Color(0xFF5E636B); // ~5.4:1 на canvas

  static const inkDark = Color(0xFFF4F5F7);
  static const inkSecondaryDark = Color(0xFFAEB4BE);
  static const inkMutedDark = Color(0xFF949BA6);

  // ─── Главный акцент: шалфей (Sage) ───────────────────────────────────────
  static const accent = Color(0xFF1D5E46); // ~7.1:1 на canvas, ~7.8:1 на белом
  static const accentOn = Color(0xFFFFFFFF); // текст на accent
  static const accentSoft = Color(0xFFE6F2EC); // мягкий фон активных пилюль
  static const accentSoftDark = Color(0xFF13261B);

  static const accentDark = Color(0xFF6FD09C); // >8.0:1 на surfaceDark
  static const accentOnDark = Color(0xFF071D12);

  // ─── Нутриенты: чистые гармоничные тона для точек Б/Ж/У и полосы баланса ──
  static const protein = Color(0xFF23703B);
  static const fat = Color(0xFF945200);
  static const carbs = Color(0xFF2455A4);
  static const kcal = Color(0xFFB42B22);

  static const proteinDark = Color(0xFF6EE09B);
  static const fatDark = Color(0xFFF0B85A);
  static const carbsDark = Color(0xFF7EB4FF);
  static const kcalDark = Color(0xFFF69484);

  // ─── Бейдж источника: спокойный нейтральный тон ─────────────────────────
  static const sourceInk = Color(0xFF3F434A);
  static const sourceLine = borderStatic;
  static const sourceInkDark = Color(0xFFC4C9D2);
  static const sourceLineDark = borderStaticDark;

  // ─── Статусы ─────────────────────────────────────────────────────────────
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFEECEB);
  static const dangerDark = Color(0xFFF49494);
  static const dangerSoftDark = Color(0xFF301818);
  static const warning = Color(0xFF8A4F00);
  static const warningSoft = Color(0xFFFEF4E2);
  static const warningDark = Color(0xFFEAB96E);
  static const warningSoftDark = Color(0xFF2E2212);
  static const success = Color(0xFF156B3E);
  static const successDark = Color(0xFF7CD49F);

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
