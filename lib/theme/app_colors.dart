import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─── Single source of color truth for ACALink ─────────────────────────────
/// Values are transcribed 1:1 from the web portal's design system
/// (`src/styles/design-system.css`, the `:root`/`[data-theme="dark"]` and
/// `[data-theme="light"]` blocks) so the mobile app and the web dashboards
/// read as the same product. Previously this palette was copy-pasted, light-
/// mode-only, into four different places (`core/tokens.dart`'s `T`,
/// `theme/app_theme.dart`'s old `AppTheme`, and private `_T` classes in
/// `home_shell.dart` / `student_select_screen.dart`) — this supersedes all
/// of them. Field names are kept as a superset of every field any of those
/// four classes used, so screens only need their `T.`/`_T.`/`AppTheme.`
/// prefix swapped for `context.colors.`, not a rename.
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color bgSecondary;
  final Color heroBg;
  final Color cardBg;
  final Color cardBgHover;
  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  final Color primary;
  final Color primaryLight;
  final Color primaryPale;
  final Color primaryDim;

  final Color secondary;
  final Color secondaryLight;
  final Color secondaryPale;

  final Color navyStart;
  final Color navyEnd;

  final Color warning;
  final Color warningLight;
  final Color warningPale;
  final Color warningDark;

  final Color success;
  final Color successLight;
  final Color successPale;

  final Color danger;
  final Color dangerLight;
  final Color dangerPale;

  final Color purple;
  final Color purplePale;

  final Color inputBg;
  final Color inputBorder;
  final Color overlay;
  final Color modalBg;
  final Color surface;
  final Color surfaceHover;

  final List<Color> heroGradient;

  final String fontMono;
  final String fontDisplay;
  final String fontBody;

  const AppColors({
    required this.bg,
    required this.bgSecondary,
    required this.heroBg,
    required this.cardBg,
    required this.cardBgHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.primary,
    required this.primaryLight,
    required this.primaryPale,
    required this.primaryDim,
    required this.secondary,
    required this.secondaryLight,
    required this.secondaryPale,
    required this.navyStart,
    required this.navyEnd,
    required this.warning,
    required this.warningLight,
    required this.warningPale,
    required this.warningDark,
    required this.success,
    required this.successLight,
    required this.successPale,
    required this.danger,
    required this.dangerLight,
    required this.dangerPale,
    required this.purple,
    required this.purplePale,
    required this.inputBg,
    required this.inputBorder,
    required this.overlay,
    required this.modalBg,
    required this.surface,
    required this.surfaceHover,
    required this.heroGradient,
    required this.fontMono,
    required this.fontDisplay,
    required this.fontBody,
  });

  /// `primaryDark` was the name `core/tokens.dart`'s `T` used for the same
  /// shade `theme/app_theme.dart`/`_T` called `primaryLight` — kept as an
  /// alias so every existing call site resolves without a per-field rename.
  Color get primaryDark => primaryLight;

  static final AppColors dark = AppColors(
    bg: const Color(0xFF0D1427),
    bgSecondary: const Color(0xFF111D35),
    heroBg: const Color(0xF20A0F1E),
    cardBg: const Color(0x08FFFFFF),
    cardBgHover: const Color(0x0EFFFFFF),
    border: const Color(0x244F6EF7),
    borderStrong: const Color(0x474F6EF7),
    textPrimary: const Color(0xFFFFFFFF),
    textSecondary: const Color(0x8CFFFFFF),
    textMuted: const Color(0x38FFFFFF),
    primary: const Color(0xFF4F6EF7),
    primaryLight: const Color(0xFF7B96FF),
    primaryPale: const Color(0x1F4F6EF7),
    primaryDim: const Color(0x144F6EF7),
    secondary: const Color(0xFF0EA5B0),
    secondaryLight: const Color(0xFF22D3DE),
    secondaryPale: const Color(0x1F0EA5B0),
    navyStart: const Color(0xFF2D3A5E),
    navyEnd: const Color(0xFF3D4F7A),
    warning: const Color(0xFFE8A800),
    warningLight: const Color(0xFFF5C842),
    warningPale: const Color(0x1FE8A800),
    warningDark: const Color(0xFF1A1200),
    success: const Color(0xFF22C55E),
    successLight: const Color(0xFF4ADE80),
    successPale: const Color(0x1F22C55E),
    danger: const Color(0xFFEF4444),
    dangerLight: const Color(0xFFF87171),
    dangerPale: const Color(0x1FEF4444),
    purple: const Color(0xFF8B5CF6),
    purplePale: const Color(0x1F8B5CF6),
    inputBg: const Color(0x0AFFFFFF),
    inputBorder: const Color(0x2E4F6EF7),
    overlay: const Color(0xBF050812),
    modalBg: const Color(0xFF111D35),
    surface: const Color(0x08FFFFFF),
    surfaceHover: const Color(0x0EFFFFFF),
    heroGradient: const [Color(0xFF0F1629), Color(0xFF162040), Color(0xFF0F1D38)],
    fontMono: GoogleFonts.dmMono().fontFamily!,
    fontDisplay: GoogleFonts.bebasNeue().fontFamily!,
    fontBody: GoogleFonts.dmSans().fontFamily!,
  );

  static final AppColors light = AppColors(
    bg: const Color(0xFFF0F2F7),
    bgSecondary: const Color(0xFFE4E7EF),
    heroBg: const Color(0xFFFFFFFF),
    cardBg: const Color(0xFFFFFFFF),
    cardBgHover: const Color(0xFFF8F9FD),
    border: const Color(0xFFD0D6E8),
    borderStrong: const Color(0xFFB0BCD8),
    textPrimary: const Color(0xFF0F1729),
    textSecondary: const Color(0xFF3D4A6B),
    textMuted: const Color(0xFF4A5578),
    primary: const Color(0xFF4F6EF7),
    primaryLight: const Color(0xFF3D5CE8),
    primaryPale: const Color(0xFFE8EDFF),
    primaryDim: const Color(0xFFF0F3FF),
    secondary: const Color(0xFF0EA5B0),
    secondaryLight: const Color(0xFF0882A0),
    secondaryPale: const Color(0xFFE0F7F8),
    navyStart: const Color(0xFF2D3A5E),
    navyEnd: const Color(0xFF3D4F7A),
    warning: const Color(0xFFB45309),
    warningLight: const Color(0xFF92400E),
    warningPale: const Color(0xFFFEF3C7),
    warningDark: const Color(0xFFFEF9EC),
    success: const Color(0xFF16A34A),
    successLight: const Color(0xFF15803D),
    successPale: const Color(0xFFDCFCE7),
    danger: const Color(0xFFDC2626),
    dangerLight: const Color(0xFFB91C1C),
    dangerPale: const Color(0xFFFEE2E2),
    purple: const Color(0xFF7C3AED),
    purplePale: const Color(0x1F8B5CF6),
    inputBg: const Color(0xFFFFFFFF),
    inputBorder: const Color(0xFFC4CDE0),
    overlay: const Color(0x730A1020),
    modalBg: const Color(0xFFFFFFFF),
    surface: const Color(0xFFE8ECF8),
    surfaceHover: const Color(0xFFDDE3F5),
    heroGradient: const [Color(0xFFE8EAF4), Color(0xFFDDE1EF), Color(0xFFE8EAF4)],
    fontMono: GoogleFonts.dmMono().fontFamily!,
    fontDisplay: GoogleFonts.bebasNeue().fontFamily!,
    fontBody: GoogleFonts.dmSans().fontFamily!,
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? bgSecondary,
    Color? heroBg,
    Color? cardBg,
    Color? cardBgHover,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? primary,
    Color? primaryLight,
    Color? primaryPale,
    Color? primaryDim,
    Color? secondary,
    Color? secondaryLight,
    Color? secondaryPale,
    Color? navyStart,
    Color? navyEnd,
    Color? warning,
    Color? warningLight,
    Color? warningPale,
    Color? warningDark,
    Color? success,
    Color? successLight,
    Color? successPale,
    Color? danger,
    Color? dangerLight,
    Color? dangerPale,
    Color? purple,
    Color? purplePale,
    Color? inputBg,
    Color? inputBorder,
    Color? overlay,
    Color? modalBg,
    Color? surface,
    Color? surfaceHover,
    List<Color>? heroGradient,
    String? fontMono,
    String? fontDisplay,
    String? fontBody,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      bgSecondary: bgSecondary ?? this.bgSecondary,
      heroBg: heroBg ?? this.heroBg,
      cardBg: cardBg ?? this.cardBg,
      cardBgHover: cardBgHover ?? this.cardBgHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      primaryPale: primaryPale ?? this.primaryPale,
      primaryDim: primaryDim ?? this.primaryDim,
      secondary: secondary ?? this.secondary,
      secondaryLight: secondaryLight ?? this.secondaryLight,
      secondaryPale: secondaryPale ?? this.secondaryPale,
      navyStart: navyStart ?? this.navyStart,
      navyEnd: navyEnd ?? this.navyEnd,
      warning: warning ?? this.warning,
      warningLight: warningLight ?? this.warningLight,
      warningPale: warningPale ?? this.warningPale,
      warningDark: warningDark ?? this.warningDark,
      success: success ?? this.success,
      successLight: successLight ?? this.successLight,
      successPale: successPale ?? this.successPale,
      danger: danger ?? this.danger,
      dangerLight: dangerLight ?? this.dangerLight,
      dangerPale: dangerPale ?? this.dangerPale,
      purple: purple ?? this.purple,
      purplePale: purplePale ?? this.purplePale,
      inputBg: inputBg ?? this.inputBg,
      inputBorder: inputBorder ?? this.inputBorder,
      overlay: overlay ?? this.overlay,
      modalBg: modalBg ?? this.modalBg,
      surface: surface ?? this.surface,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      heroGradient: heroGradient ?? this.heroGradient,
      fontMono: fontMono ?? this.fontMono,
      fontDisplay: fontDisplay ?? this.fontDisplay,
      fontBody: fontBody ?? this.fontBody,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> grad(List<Color> a, List<Color> b) =>
        [for (var i = 0; i < a.length; i++) c(a[i], b[i])];
    return AppColors(
      bg: c(bg, other.bg),
      bgSecondary: c(bgSecondary, other.bgSecondary),
      heroBg: c(heroBg, other.heroBg),
      cardBg: c(cardBg, other.cardBg),
      cardBgHover: c(cardBgHover, other.cardBgHover),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      primary: c(primary, other.primary),
      primaryLight: c(primaryLight, other.primaryLight),
      primaryPale: c(primaryPale, other.primaryPale),
      primaryDim: c(primaryDim, other.primaryDim),
      secondary: c(secondary, other.secondary),
      secondaryLight: c(secondaryLight, other.secondaryLight),
      secondaryPale: c(secondaryPale, other.secondaryPale),
      navyStart: c(navyStart, other.navyStart),
      navyEnd: c(navyEnd, other.navyEnd),
      warning: c(warning, other.warning),
      warningLight: c(warningLight, other.warningLight),
      warningPale: c(warningPale, other.warningPale),
      warningDark: c(warningDark, other.warningDark),
      success: c(success, other.success),
      successLight: c(successLight, other.successLight),
      successPale: c(successPale, other.successPale),
      danger: c(danger, other.danger),
      dangerLight: c(dangerLight, other.dangerLight),
      dangerPale: c(dangerPale, other.dangerPale),
      purple: c(purple, other.purple),
      purplePale: c(purplePale, other.purplePale),
      inputBg: c(inputBg, other.inputBg),
      inputBorder: c(inputBorder, other.inputBorder),
      overlay: c(overlay, other.overlay),
      modalBg: c(modalBg, other.modalBg),
      surface: c(surface, other.surface),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      heroGradient: grad(heroGradient, other.heroGradient),
      fontMono: t < 0.5 ? fontMono : other.fontMono,
      fontDisplay: t < 0.5 ? fontDisplay : other.fontDisplay,
      fontBody: t < 0.5 ? fontBody : other.fontBody,
    );
  }
}

/// `context.colors.primary` instead of threading a `AppColors` param, or a
/// static const, through every widget.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
