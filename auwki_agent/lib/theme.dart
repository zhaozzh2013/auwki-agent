import 'package:flutter/material.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.sidebar,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.hover,
    required this.primary,
    required this.primarySoft,
    required this.planAccent,
    required this.planAccentSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  final Color bg, sidebar, surface, surfaceAlt, border, hover;
  final Color primary, primarySoft, planAccent, planAccentSoft;
  final Color textPrimary, textSecondary, textTertiary;

  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0E0E0E),
    sidebar: Color(0xFF181818),
    surface: Color(0xFF1F1F1F),
    surfaceAlt: Color(0xFF252525),
    border: Color(0xFF2A2A2A),
    hover: Color(0xFF2A2A2A),
    primary: Color(0xFF4D8AFF),
    primarySoft: Color(0x1A4D8AFF),
    planAccent: Color(0xFFE6B800),
    planAccentSoft: Color(0x1AE6B800),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF9AA0A6),
    textTertiary: Color(0xFF6B7280),
  );

  static const AppPalette light = AppPalette(
    bg: Color(0xFFFAFAFA),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F3F4),
    border: Color(0xFFE2E5E8),
    hover: Color(0xFFEEEEEE),
    primary: Color(0xFF2563EB),
    primarySoft: Color(0x142563EB),
    planAccent: Color(0xFFD97706),
    planAccentSoft: Color(0x14D97706),
    textPrimary: Color(0xFF1F1F1F),
    textSecondary: Color(0xFF5F6368),
    textTertiary: Color(0xFF9AA0A6),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? sidebar,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? hover,
    Color? primary,
    Color? primarySoft,
    Color? planAccent,
    Color? planAccentSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
  }) =>
      AppPalette(
        bg: bg ?? this.bg,
        sidebar: sidebar ?? this.sidebar,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        hover: hover ?? this.hover,
        primary: primary ?? this.primary,
        primarySoft: primarySoft ?? this.primarySoft,
        planAccent: planAccent ?? this.planAccent,
        planAccentSoft: planAccentSoft ?? this.planAccentSoft,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      planAccent: Color.lerp(planAccent, other.planAccent, t)!,
      planAccentSoft: Color.lerp(planAccentSoft, other.planAccentSoft, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

extension PaletteAccess on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

class AppColors {
  AppColors._();

  static AppPalette _current = AppPalette.dark;

  static set palette(AppPalette p) => _current = p;
  static AppPalette get palette => _current;

  static Color get bg => _current.bg;
  static Color get sidebar => _current.sidebar;
  static Color get surface => _current.surface;
  static Color get surfaceAlt => _current.surfaceAlt;
  static Color get border => _current.border;
  static Color get hover => _current.hover;
  static Color get primary => _current.primary;
  static Color get primarySoft => _current.primarySoft;
  static Color get planAccent => _current.planAccent;
  static Color get planAccentSoft => _current.planAccentSoft;
  static Color get textPrimary => _current.textPrimary;
  static Color get textSecondary => _current.textSecondary;
  static Color get textTertiary => _current.textTertiary;
}