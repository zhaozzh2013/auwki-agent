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
    required this.codeBg,
    required this.codeFg,
    required this.codeblockBg,
  });

  final Color bg, sidebar, surface, surfaceAlt, border, hover;
  final Color primary, primarySoft, planAccent, planAccentSoft;
  final Color textPrimary, textSecondary, textTertiary;
  final Color codeBg, codeFg, codeblockBg;

  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0B0D10),
    sidebar: Color(0xFF12151A),
    surface: Color(0xFF191D23),
    surfaceAlt: Color(0xFF1F242B),
    border: Color(0xFF272D35),
    hover: Color(0xFF313A45),
    primary: Color(0xFF5B8CFF),
    primarySoft: Color(0x1A5B8CFF),
    planAccent: Color(0xFFE6B800),
    planAccentSoft: Color(0x1AE6B800),
    textPrimary: Color(0xFFECEFF4),
    textSecondary: Color(0xFF9BA4B0),
    textTertiary: Color(0xFF6C7480),
    codeBg: Color(0xFF2A313B),
    codeFg: Color(0xFFECEFF4),
    codeblockBg: Color(0xFF14171C),
  );

  static const AppPalette darkFlagship = AppPalette(
    bg: Color(0xFF0E0B14),
    sidebar: Color(0xFF181222),
    surface: Color(0xFF201830),
    surfaceAlt: Color(0xFF2A1F3C),
    border: Color(0xFF382950),
    hover: Color(0xFF433261),
    primary: Color(0xFFA855F7),
    primarySoft: Color(0x24A855F7),
    planAccent: Color(0xFFE879F9),
    planAccentSoft: Color(0x24E879F9),
    textPrimary: Color(0xFFF3E8FF),
    textSecondary: Color(0xFFC4B5FD),
    textTertiary: Color(0xFF8B7AA8),
    codeBg: Color(0xFF3B2D4C),
    codeFg: Color(0xFFF3E8FF),
    codeblockBg: Color(0xFF181122),
  );

  static const AppPalette light = AppPalette(
    bg: Color(0xFFF6F7F9),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F2F5),
    border: Color(0xFFE2E6EC),
    hover: Color(0xFFDEE3EA),
    primary: Color(0xFF2F6BED),
    primarySoft: Color(0x142F6BED),
    planAccent: Color(0xFFD97706),
    planAccentSoft: Color(0x14D97706),
    textPrimary: Color(0xFF1C2026),
    textSecondary: Color(0xFF5D6570),
    textTertiary: Color(0xFF96A0AC),
    codeBg: Color(0xFFEAEDF2),
    codeFg: Color(0xFF1C2026),
    codeblockBg: Color(0xFFF4F5F7),
  );

  static const AppPalette lightFlagship = AppPalette(
    bg: Color(0xFFFCF7FF),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF5ECFF),
    border: Color(0xFFE8D5FF),
    hover: Color(0xFFE5D2FA),
    primary: Color(0xFF9333EA),
    primarySoft: Color(0x189333EA),
    planAccent: Color(0xFFC026D3),
    planAccentSoft: Color(0x18C026D3),
    textPrimary: Color(0xFF21152D),
    textSecondary: Color(0xFF6B4D82),
    textTertiary: Color(0xFF9F86B5),
    codeBg: Color(0xFFF1E5FF),
    codeFg: Color(0xFF21152D),
    codeblockBg: Color(0xFFF9F2FF),
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
    Color? codeBg,
    Color? codeFg,
    Color? codeblockBg,
  }) => AppPalette(
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
    codeBg: codeBg ?? this.codeBg,
    codeFg: codeFg ?? this.codeFg,
    codeblockBg: codeblockBg ?? this.codeblockBg,
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
      codeBg: Color.lerp(codeBg, other.codeBg, t)!,
      codeFg: Color.lerp(codeFg, other.codeFg, t)!,
      codeblockBg: Color.lerp(codeblockBg, other.codeblockBg, t)!,
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

  /// 卡片/气泡阴影色：浅色主题用轻阴影，深色主题用深阴影。
  static Color get cardShadow =>
      AppColors.bg.computeLuminance() > 0.5
          ? const Color(0x12000000)
          : const Color(0x40000000);

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
  static Color get codeBg => _current.codeBg;
  static Color get codeFg => _current.codeFg;
  static Color get codeblockBg => _current.codeblockBg;
}

/// C13：统一动画时长（避免各处节奏不一、感知卡顿）。
const Duration kAnimFast = Duration(milliseconds: 150);
const Duration kAnimMed = Duration(milliseconds: 220);
const Duration kAnimSlow = Duration(milliseconds: 320);

/// 统一的底部提示条：文本颜色跟随主题，不再硬编码黑/白。
void showAppSnack(
  BuildContext context,
  String text, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: TextStyle(
            color: error ? Colors.white : AppColors.textPrimary,
            fontSize: 12,
          ),
        ),
        backgroundColor: error
            ? Colors.redAccent.shade700
            : AppColors.surfaceAlt,
      ),
    );
}
