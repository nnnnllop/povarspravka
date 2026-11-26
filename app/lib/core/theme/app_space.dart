import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 4-dp сетка отступов (аудит §3.3).
///
/// Правило: внутри карточки — [x4] (16), между карточками — [x2] (8),
/// между секциями — [x6] (24), внешние поля экрана — [x4] (16).
/// Никаких 6/10/14/18/22 — дробление отступов даёт визуальный дребезг.
class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;

  static const double maxWidth = 640;
  static const double minRowHeight = 56;

  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: x4);
  static const EdgeInsets card = EdgeInsets.all(x4);
  static const EdgeInsets sheet = EdgeInsets.fromLTRB(x4, x3, x4, x4);

  /// Единый горизонтальный отступ экрана: 16 dp.
  static double gutter([double? width]) => x4;
}

/// Единые токены размеров иконок (шаг 4 dp + явная роль 18 dp для кнопок).
class IconSizes {
  static const double xs = 16;
  static const double btn = 18;
  static const double md = 20;
  static const double lg = 24;
}

/// Единая политика адаптивных порогов для всего интерфейса.
class AppLayout {
  /// Очень узкий экран (<360 dp, например 320 dp).
  static bool isNarrow(double width) => width < 360;

  /// Узкий для 1-строчной панели зума и плашки бланка (<380 dp).
  static bool isCompactBlankBar(double width) => width < 380;

  /// Компактный телефонный экран (<480 dp).
  static bool isCompact(double width) => width < 480;

  /// Короткий экран (landscape, <460 dp).
  static bool isShort(double height) => height < 460;

  /// Сжатая высота портретного экрана при крупном тексте.
  static bool isCompactHeight(double height, double textScale) =>
      height < 580 && isLargeText(textScale);

  /// Переводить ли нижнюю шторку в единый скролл целиком.
  static bool isTightSheet(double height, double textScale) =>
      isShort(height) || isCompactHeight(height, textScale);

  /// Крупный пользовательский масштаб текста.
  static bool isLargeText(double textScale) => textScale >= 1.3;

  /// Складывать ли парные кнопки действий в столбец вместо строки.
  static bool shouldStackActions(double width, double textScale) =>
      width < 360 || textScale >= 1.45;

  /// Складывать ли строку ввода веса готового блюда в 2 строки.
  static bool shouldStackYieldRow(double width, double textScale) =>
      width < 340 || textScale > 1.35;

  /// Разрешена ли 2-колоночная компоновка нумпада (ввод + клавиатура рядом).
  static bool canSideBySideNumpad(
    double width,
    double height, [
    double textScale = 1.0,
  ]) =>
      width >= 540 && height >= 260 && height < 460;
}

/// Скругления в стиле Material 3 / iOS (дизайн «Прибор», шаг 4 dp).
class Radii {
  static const double chip = 8;
  static const double field = 12;
  static const double card = 16;
  static const double dock = 20;
  static const double slab = 20;
  static const double sheet = 24;
  static const double dialog = 24;

  static const BorderRadius chipAll = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius fieldAll = BorderRadius.all(Radius.circular(field));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius dockAll = BorderRadius.all(Radius.circular(dock));
  static const BorderRadius slabAll = BorderRadius.all(Radius.circular(slab));
  static const BorderRadius dialogAll =
      BorderRadius.all(Radius.circular(dialog));
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

  Color get canvas => isDark ? AppColors.canvasDark : AppColors.canvas;
  Color get surface => isDark ? AppColors.surfaceDark : AppColors.surface;
  Color get sunken =>
      isDark ? AppColors.surfaceSunkenDark : AppColors.surfaceSunken;

  /// Интерактивные границы (>= 3:1 WCAG 1.4.11).
  Color get border => isDark ? AppColors.borderDark : AppColors.border;

  /// Декоративные контуры карточек: тонкий 1px контур.
  Color get borderStatic =>
      isDark ? AppColors.borderStaticDark : AppColors.borderStatic;

  Color get divider => isDark ? AppColors.dividerDark : AppColors.divider;

  Color get ink => isDark ? AppColors.inkDark : AppColors.ink;
  Color get inkSecondary =>
      isDark ? AppColors.inkSecondaryDark : AppColors.inkSecondary;
  Color get inkMuted => isDark ? AppColors.inkMutedDark : AppColors.inkMuted;

  Color get accent => isDark ? AppColors.accentDark : AppColors.accent;
  Color get onAccent => isDark ? AppColors.accentOnDark : AppColors.accentOn;
  Color get accentSoft =>
      isDark ? AppColors.accentSoftDark : AppColors.accentSoft;

  Color get protein => isDark ? AppColors.proteinDark : AppColors.protein;
  Color get fat => isDark ? AppColors.fatDark : AppColors.fat;
  Color get carbs => isDark ? AppColors.carbsDark : AppColors.carbs;
  Color get kcal => isDark ? AppColors.kcalDark : AppColors.kcal;

  Color get sourceInk => isDark ? AppColors.sourceInkDark : AppColors.sourceInk;
  Color get sourceLine =>
      isDark ? AppColors.sourceLineDark : AppColors.sourceLine;

  Color get danger => isDark ? AppColors.dangerDark : AppColors.danger;
  Color get dangerSoft =>
      isDark ? AppColors.dangerSoftDark : AppColors.dangerSoft;
  Color get warning => isDark ? AppColors.warningDark : AppColors.warning;
  Color get warningSoft =>
      isDark ? AppColors.warningSoftDark : AppColors.warningSoft;
  Color get success => isDark ? AppColors.successDark : AppColors.success;

  /// Тёмная графитовая приборная плита (Hero / Readout / Меню).
  Color get slab => isDark ? AppColors.slabDark : AppColors.slab;
  Color get slabInk => isDark ? AppColors.slabInkDark : AppColors.slabInk;
  Color get slabSecondary =>
      isDark ? AppColors.slabSecondaryDark : AppColors.slabSecondary;
  Color get slabEdge => isDark ? AppColors.slabEdgeDark : AppColors.slabEdge;
  Color get slabSurface =>
      isDark ? AppColors.slabSurfaceDark : AppColors.slabSurface;
  Color get signal => isDark ? AppColors.signalDark : AppColors.signal;
  Color get sheetHandle =>
      isDark ? AppColors.sheetHandleDark : AppColors.sheetHandle;

  /// Цвета акцента, статусов и полосы нутриентов на тёмной приборной плите (AA >= 4.5).
  Color get slabProtein => AppColors.proteinDark;
  Color get slabFat => AppColors.fatDark;
  Color get slabCarbs => AppColors.carbsDark;
  Color get slabAccent => AppColors.accentDark;
  Color get slabDanger => AppColors.dangerDark;
  Color get slabWarning => AppColors.warningDark;

  /// Поднятая поверхность для плавающих капсул и кнопок в тёмной теме.
  Color get raised => isDark ? AppColors.surfaceRaisedDark : AppColors.surface;

  /// Тень парящего дока (токенизированный цвет вместо сырых литералов).
  List<BoxShadow> get dockShadow => isDark
      ? const <BoxShadow>[
          BoxShadow(
            color: AppColors.dockShadowDark,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ]
      : const <BoxShadow>[
          BoxShadow(
            color: AppColors.dockShadowLight,
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ];

  /// Контрастный «монтажный стол» под белым печатным листом бланка.
  Color get mountingTable =>
      isDark ? AppColors.mountingTableDark : AppColors.mountingTableLight;

  /// Калибровочная точка монтажного стола под печатным бланком.
  Color get tableDot =>
      isDark ? AppColors.tableDotDark : AppColors.tableDotLight;

  /// Поверхности в «Приборе» разделяются тоном и скруглениями без диффузных теней.
  List<BoxShadow> get cardShadow => const <BoxShadow>[];
}
