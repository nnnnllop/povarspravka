import 'package:flutter/material.dart';

/// Калиброванная швейцарская палитра приложения «Поварская справка».
///
/// Светлая тема: чистый холодно-нейтральный фон (`#F7F7F8`), белоснежные
/// карточки с тонкими границами (`#E5E7EB`) и глубокий кобальтовый акцент
/// (`#1E40AF`). Тёмная тема: графитовый `#0D0E10` + `#16181C` + `#73A5FF`.
///
/// Все пары «текст/фон» измерены по WCAG 2.1, все значения проходят AA (4.5:1)
/// либо 3:1 для интерактивных границ (1.4.11).
class AppColors {
  // ─── Основа: стерильный нейтральный графит и кобальтовый акцент ──────────
  static const canvas = Color(0xFFF7F7F8); // чистый швейцарский фон экранов
  static const surface = Color(0xFFFFFFFF); // чистые карточки и шиты
  static const surfaceSunken = Color(0xFFEFEFF2); // утопленные поля и тональные кнопки

  static const canvasDark = Color(0xFF0D0E10);
  static const surfaceDark = Color(0xFF16181C);
  static const surfaceSunkenDark = Color(0xFF101215);
  static const surfaceRaisedDark = Color(0xFF1F2228);

  // ─── Границы и внутренние разделители ───────────────────────────────────
  /// ≥ 3:1 на canvas/surface (для доступности интерактивных границ).
  static const border = Color(0xFF737984);

  /// Деликатный hairline-контур карточек и тональных кнопок.
  static const borderStatic = Color(0xFFE5E7EB);

  /// Внутренний разделитель строк внутри сгруппированной карточки.
  static const divider = Color(0xFFECEDF0);

  /// ≥ 3:1 к surfaceDark в тёмной теме.
  static const borderDark = Color(0xFF6D7480);
  static const borderStaticDark = Color(0xFF272B33);
  static const dividerDark = Color(0xFF22262E);

  // ─── Текст (весь текст ≥ 4.5:1 AA на canvas и surface) ──────────────────
  static const ink = Color(0xFF111214); // >17:1 на белом
  static const inkSecondary = Color(0xFF4B4F56); // ~7.6:1 на canvas
  static const inkMuted = Color(0xFF626770); // ~5.3:1 на canvas

  static const inkDark = Color(0xFFF4F5F7);
  static const inkSecondaryDark = Color(0xFFA9B0BA);
  static const inkMutedDark = Color(0xFF8C94A0);

  // ─── Главный акцент: глубокий швейцарский кобальт ────────────────────────
  static const accent = Color(0xFF1E40AF); // >8.0:1 на canvas, >8.7:1 на белом
  static const accentOn = Color(0xFFFFFFFF); // текст на accent
  static const accentSoft = Color(0xFFEBF1FE); // мягкий фон активных пилюль
  static const accentSoftDark = Color(0xFF182338);

  static const accentDark = Color(0xFF73A5FF); // >7.0:1 на surfaceDark
  static const accentOnDark = Color(0xFF081429);

  // ─── Нутриенты: чистые тона для микро-точек и полосы баланса ─────────────
  static const protein = Color(0xFF1E6341);
  static const fat = Color(0xFF8E5000);
  static const carbs = Color(0xFF1C518C);
  static const kcal = Color(0xFFA82820);

  static const proteinDark = Color(0xFF7AD19D);
  static const fatDark = Color(0xFFEBB863);
  static const carbsDark = Color(0xFF89B9F0);
  static const kcalDark = Color(0xFFF59384);

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
