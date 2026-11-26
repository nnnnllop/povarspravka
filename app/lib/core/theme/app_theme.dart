import 'package:flutter/material.dart';
import 'app_space.dart';
import 'app_typography.dart';

/// Единая сборка темы (аудит §5, этап 1).
///
/// Раньше `light` и `dark` были двумя копиями по ~100 строк с расхождениями
/// (`outlinedButtonTheme` в dark переопределялся, в light нет;
/// `inputDecorationTheme.fillColor` был захардкожен `Colors.white`). Теперь
/// один билдер с явными параметрами — расхождения физически невозможны.
class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        p: const Palette(false),
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        p: const Palette(true),
      );

  /// Единый стиль [SegmentedButton] для всей дизайн-системы (тема + локальные
  /// compact-варианты): фон неактивного сегмента [Palette.sunken], активный —
  /// [Palette.accent], граница >= 3:1 ([Palette.border]).
  static ButtonStyle segmentedStyle(Palette p, {bool compact = false}) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, kMinTapTarget)),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? Space.x2 : Space.x3,
          vertical: Space.x1,
        ),
      ),
      textStyle: const WidgetStatePropertyAll(AppTypography.label),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.accent;
        return p.sunken;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.onAccent;
        return p.ink;
      }),
      side: WidgetStatePropertyAll(BorderSide(color: p.border)),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: Radii.fieldAll),
      ),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Palette p,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.ink,
      secondary: p.ink,
      onSecondary: p.surface,
      secondaryContainer: p.sunken,
      onSecondaryContainer: p.ink,
      tertiary: p.protein,
      onTertiary: Colors.white,
      error: p.danger,
      onError: p.surface,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.ink,
      surfaceContainerHighest: p.sunken,
      onSurfaceVariant: p.inkSecondary,
      outline: p.border,
      outlineVariant: p.borderStatic,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.ink,
      onInverseSurface: p.canvas,
      inversePrimary: p.canvas,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.fontName,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      // Все таргеты по умолчанию — с паддингом до 48 dp.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      displaySmall: AppTypography.display.copyWith(color: p.ink),
      titleLarge: AppTypography.title.copyWith(color: p.ink),
      titleMedium: AppTypography.headline.copyWith(color: p.ink),
      titleSmall: AppTypography.label.copyWith(color: p.ink),
      bodyLarge: AppTypography.body.copyWith(color: p.ink),
      bodyMedium: AppTypography.body.copyWith(color: p.ink),
      bodySmall: AppTypography.bodySm.copyWith(color: p.inkSecondary),
      labelLarge: AppTypography.label.copyWith(color: p.ink),
      labelMedium: AppTypography.caption.copyWith(color: p.inkSecondary),
      labelSmall: AppTypography.caption.copyWith(color: p.inkMuted),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.ink, size: 24),
        actionsIconTheme: IconThemeData(color: p.ink, size: 24),
        titleTextStyle: AppTypography.title.copyWith(color: p.ink),
      ),
      // Тональное разделение поверхностей без лишних рамок:
      // на тёплом холсте #F2F2EF сгруппированные белые поверхности (R=16)
      // читаются за счёт тонового шага.
      cardTheme: CardTheme(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: Radii.cardAll,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.sunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x3,
        ),
        hintStyle: AppTypography.bodySm.copyWith(color: p.inkMuted),
        labelStyle: AppTypography.bodySm.copyWith(color: p.inkSecondary),
        border: const OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: p.border, width: 1),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: p.accent, width: 1.75),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: p.danger, width: 1.75),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: p.danger, width: 1.75),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accent,
        disabledColor: p.sunken,
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.sunken;
          return states.contains(WidgetState.selected) ? p.accent : p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return BorderSide(color: isSelected ? p.accent : p.borderStatic);
        }),
        shape: const RoundedRectangleBorder(borderRadius: Radii.chipAll),
        labelStyle: AppTypography.label.copyWith(color: p.ink),
        secondaryLabelStyle: AppTypography.label.copyWith(color: p.onAccent),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x1,
        ),
        pressElevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.borderStatic,
          disabledForegroundColor: p.inkMuted,
          elevation: 0,
          minimumSize: const Size(0, kMinTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          textStyle: AppTypography.label,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.borderStatic,
          disabledForegroundColor: p.inkMuted,
          elevation: 0,
          minimumSize: const Size(0, kMinTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x3,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          textStyle: AppTypography.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: p.isDark ? p.raised : p.surface,
          foregroundColor: p.ink,
          elevation: 0,
          minimumSize: const Size(0, kMinTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x4,
            vertical: Space.x3,
          ),
          side: BorderSide(color: p.borderStatic, width: 1),
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          textStyle: AppTypography.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(0, kMinTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x3,
            vertical: Space.x2,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          textStyle: AppTypography.label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: segmentedStyle(p),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.inkSecondary,
        textColor: p.ink,
        titleTextStyle: AppTypography.body.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w400,
        ),
        subtitleTextStyle: AppTypography.bodySm.copyWith(color: p.inkSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x2,
        ),
        minVerticalPadding: Space.x2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: AppTypography.body.copyWith(color: p.canvas),
        actionTextColor: p.canvas,
        shape: RoundedRectangleBorder(borderRadius: Radii.fieldAll),
        insetPadding: const EdgeInsets.all(Space.x4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: p.sheetHandle,
        dragHandleSize: const Size(Space.x8, Space.x1),
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.dialogAll),
        titleTextStyle: AppTypography.title.copyWith(color: p.ink),
        contentTextStyle: AppTypography.body.copyWith(color: p.ink),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: AppTypography.body.copyWith(color: p.ink),
        shape: RoundedRectangleBorder(borderRadius: Radii.fieldAll),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.onAccent : p.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.accent : p.sunken,
        ),
        trackOutlineColor: WidgetStatePropertyAll(p.border),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        thumbColor: p.accent,
      ),
    );
  }
}
