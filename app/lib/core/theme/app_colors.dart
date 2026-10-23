import 'package:flutter/material.dart';

/// Калиброванная палитра приложения «Поварская справка»
/// Стиль: швейцарский минимализм, теплый бумажный фон (warm paper monochrome),
/// пастельные неброские плашки нутриентов, полное отсутствие кислотных градиентов.
class AppColors {
  // Базовые фоны и поверхности (Warm Paper Monochrome)
  static const backgroundLight = Color(0xFFFAF9F6); // Теплый бумажный алебастр
  static const surfaceLight = Color(0xFFFFFFFF); // Чистая белая поверхность
  static const cardLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE8E5DF); // Четкий 1px нейтрально-теплый контур
  static const borderSubtleLight = Color(0xFFF2EFEB);

  static const backgroundDark = Color(0xFF141416); // Глубокий нейтральный обсидиан
  static const surfaceDark = Color(0xFF1C1C1F);
  static const cardDark = Color(0xFF222226);
  static const borderDark = Color(0xFF2E2E34);
  static const borderSubtleDark = Color(0xFF26262B);

  // Акценты бренда (Минималистичный строгий дизайн + теплый янтарь для фокуса)
  static const primary = Color(0xFF1C1917); // Глубокий charcoal для главных кнопок
  static const primaryLight = Color(0xFFE7E5E4);
  static const primaryContainerLight = Color(0xFFF5F4F0);
  static const primaryContainerDark = Color(0xFF2A2A2E);

  static const accent = Color(0xFFB45309); // Кулинарный янтарный фокус
  static const accentLight = Color(0xFFFEF3C7);
  static const accentDark = Color(0xFF451A03);

  // Макронутриенты — калиброванные гармоничные пастельные тона (Muted Spot Pastels)
  // Белки (Б) — спокойный шалфейный (Calm Sage)
  static const protein = Color(0xFF2E7D32);
  static const proteinLight = Color(0xFFEDF5EE);
  static const proteinBgLight = Color(0xFFEDF5EE);
  static const proteinTextLight = Color(0xFF225828);
  static const proteinBorderLight = Color(0xFFD4E7D6);
  static const proteinBgDark = Color(0xFF19281C);
  static const proteinTextDark = Color(0xFF8FD898);
  static const proteinBorderDark = Color(0xFF27422B);

  // Жиры (Ж) — теплая спелая пшеница (Warm Wheat)
  static const fat = Color(0xFFB45309);
  static const fatLight = Color(0xFFFAF3E8);
  static const fatBgLight = Color(0xFFFAF3E8);
  static const fatTextLight = Color(0xFF8C5815);
  static const fatBorderLight = Color(0xFFF3E4CD);
  static const fatBgDark = Color(0xFF2A2216);
  static const fatTextDark = Color(0xFFF5C77E);
  static const fatBorderDark = Color(0xFF43341E);

  // Углеводы (У) — выстиранный индиго / сланец (Washed Slate Indigo)
  static const carbs = Color(0xFF1D4ED8);
  static const carbsLight = Color(0xFFEEF3F9);
  static const carbsBgLight = Color(0xFFEEF3F9);
  static const carbsTextLight = Color(0xFF244F7D);
  static const carbsBorderLight = Color(0xFFD5E3F3);
  static const carbsBgDark = Color(0xFF162230);
  static const carbsTextDark = Color(0xFF90BAEC);
  static const carbsBorderDark = Color(0xFF26394F);

  // Энергетическая ценность (ккал) — мягкая терракота (Soft Terracotta)
  static const kcal = Color(0xFFC2410C);
  static const kcalLight = Color(0xFFFBF0EE);
  static const kcalBgLight = Color(0xFFFBF0EE);
  static const kcalTextLight = Color(0xFF9C382A);
  static const kcalBorderLight = Color(0xFFF3D4CF);
  static const kcalBgDark = Color(0xFF2A1A19);
  static const kcalTextDark = Color(0xFFF39284);
  static const kcalBorderDark = Color(0xFF482927);

  // Ошибки и предупреждения
  static const error = Color(0xFFB91C1C);
  static const errorLight = Color(0xFFFEE2E2);
  static const errorBgLight = Color(0xFFFEF2F2);
  static const errorTextLight = Color(0xFF991B1B);

  // Источники справочников (Скурихин / USDA)
  static const badgeSkurikhin = Color(0xFF8C5815);
  static const badgeSkurikhinBg = Color(0xFFFAF3E8);
  static const badgeSkurikhinBorder = Color(0xFFF3E4CD);

  static const badgeUsda = Color(0xFF244F7D);
  static const badgeUsdaBg = Color(0xFFEEF3F9);
  static const badgeUsdaBorder = Color(0xFFD5E3F3);

  // Текст (Off-black вместо грубого чисто черного)
  static const textPrimaryLight = Color(0xFF1A1918);
  static const textSecondaryLight = Color(0xFF6E6A64);
  static const textMutedLight = Color(0xFF9E988F);

  static const textPrimaryDark = Color(0xFFF4F4F2);
  static const textSecondaryDark = Color(0xFF9E9A92);
  static const textMutedDark = Color(0xFF6E6A64);
}
