import 'package:flutter/material.dart';

/// Semantic colour tokens for the whole presentation layer.
///
/// Brand green is the only "identity" colour. The four semantic colours
/// (success / warning / danger / info) are used ONLY to convey meaning, never
/// for decoration. Every other surface is a neutral. There are no rainbow
/// gradients and no full-bleed gradient cards.
///
/// Registered on [ThemeData.extensions] as a [ThemeExtension] so light and dark
/// mode share one set of names.
///
/// Usage:
/// ```dart
/// final colors = context.appColors;
/// Container(color: colors.surface, ...);
/// ```
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.primary,
    required this.primaryHover,
    required this.primaryPressed,
    required this.onPrimary,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnDark,
    required this.chartGrid,
    required this.chartAxisText,
    required this.chartComparison,
    required this.tableHeaderBg,
    required this.tableRowHover,
    required this.tableRowStripe,
    required this.tableBorder,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.shadow,
    required this.shadowStrong,
    required this.overlayScrim,
  });

  final Brightness brightness;

  // --- Brand ---------------------------------------------------------------
  /// Brand green. Buttons, active navigation, the primary chart series.
  final Color primary;
  final Color primaryHover;
  final Color primaryPressed;
  final Color onPrimary;

  /// Tinted green for selected rows, chips and icon-chip backgrounds.
  final Color primarySoft;
  final Color onPrimarySoft;

  // --- The single accent ---------------------------------------------------
  /// Used for the comparison series and "informational" highlights.
  final Color accent;
  final Color accentSoft;

  // --- Semantic (meaning only) --------------------------------------------
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  // --- Neutral surfaces ----------------------------------------------------
  /// Window background. Matches the value the existing theme already uses.
  final Color canvas;

  /// Card / panel background.
  final Color surface;

  /// Recessed blocks inside a card (legend wells, stat strips).
  final Color surfaceMuted;

  /// Table headers and wells.
  final Color surfaceSunken;

  final Color border;
  final Color borderStrong;

  // --- Text ----------------------------------------------------------------
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnDark;

  // --- Charts --------------------------------------------------------------
  final Color chartGrid;
  final Color chartAxisText;

  /// Muted neutral for the previous-period comparison line.
  final Color chartComparison;

  // --- Tables --------------------------------------------------------------
  final Color tableHeaderBg;
  final Color tableRowHover;
  final Color tableRowStripe;
  final Color tableBorder;

  // --- Loading skeletons ---------------------------------------------------
  final Color skeletonBase;
  final Color skeletonHighlight;

  // --- Effects -------------------------------------------------------------
  final Color shadow;
  final Color shadowStrong;
  final Color overlayScrim;

  // -------------------------------------------------------------------------
  // Convenience
  // -------------------------------------------------------------------------

  bool get isDark => brightness == Brightness.dark;

  /// One soft shadow for every card in the app.
  List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: shadow,
          blurRadius: isDark ? 0 : 10,
          offset: Offset(0, isDark ? 0 : 2),
        ),
      ];

  /// Slightly lifted — used on hover for clickable cards.
  List<BoxShadow> get cardShadowHover => [
        BoxShadow(
          color: shadowStrong,
          blurRadius: isDark ? 0 : 16,
          offset: Offset(0, isDark ? 0 : 6),
        ),
      ];

  /// A tinted background for a semantic badge / icon chip.
  Color softOf(Color semantic) => semantic.withValues(alpha: isDark ? 0.20 : 0.12);

  // -------------------------------------------------------------------------
  // Light
  // -------------------------------------------------------------------------

  static const AppColors light = AppColors(
    brightness: Brightness.light,
    primary: Color(0xFF00843D), // Keells Green — the brand colour
    primaryHover: Color(0xFF006F35),
    primaryPressed: Color(0xFF005A2A),
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFE6F3EA),
    onPrimarySoft: Color(0xFF005A2A),
    accent: Color(0xFF0B6BCB),
    accentSoft: Color(0xFFE7F0FB),
    success: Color(0xFF2E7D32),
    successSoft: Color(0xFFE8F5E9),
    warning: Color(0xFFB26A00),
    warningSoft: Color(0xFFFFF4E0),
    danger: Color(0xFFC62828),
    dangerSoft: Color(0xFFFDECEC),
    info: Color(0xFF1565C0),
    infoSoft: Color(0xFFE7F0FB),
    canvas: Color(0xFFF4F7F6),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF7F9F8),
    surfaceSunken: Color(0xFFEFF3F1),
    border: Color(0xFFE3E9E6),
    borderStrong: Color(0xFFCBD5D0),
    textPrimary: Color(0xFF14201A),
    textSecondary: Color(0xFF5B6B63),
    textTertiary: Color(0xFF8A9A92),
    textDisabled: Color(0xFFB4BEB9),
    textOnDark: Color(0xFFFFFFFF),
    chartGrid: Color(0xFFE9EEEC),
    chartAxisText: Color(0xFF7A8A82),
    chartComparison: Color(0xFF9AA8A2),
    tableHeaderBg: Color(0xFFEFF3F1),
    tableRowHover: Color(0xFFF2F7F4),
    tableRowStripe: Color(0xFFFAFCFB),
    tableBorder: Color(0xFFE3E9E6),
    skeletonBase: Color(0xFFE9EEEC),
    skeletonHighlight: Color(0xFFF7FAF9),
    shadow: Color(0x140B1F14),
    shadowStrong: Color(0x240B1F14),
    overlayScrim: Color(0x66000000),
  );

  // -------------------------------------------------------------------------
  // Dark
  // -------------------------------------------------------------------------

  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    primary: Color(0xFF34C77B),
    primaryHover: Color(0xFF4FD892),
    primaryPressed: Color(0xFF28A868),
    onPrimary: Color(0xFF04210F),
    primarySoft: Color(0xFF12301F),
    onPrimarySoft: Color(0xFF7EE2A6),
    accent: Color(0xFF5FA8F5),
    accentSoft: Color(0xFF14263A),
    success: Color(0xFF5CC98A),
    successSoft: Color(0xFF13301F),
    warning: Color(0xFFF0B357),
    warningSoft: Color(0xFF33260F),
    danger: Color(0xFFF2726F),
    dangerSoft: Color(0xFF3A1615),
    info: Color(0xFF6FA8F0),
    infoSoft: Color(0xFF152437),
    canvas: Color(0xFF121212), // unchanged from the existing dark theme
    surface: Color(0xFF171B19),
    surfaceMuted: Color(0xFF1E2422),
    surfaceSunken: Color(0xFF111514),
    border: Color(0xFF2A322F),
    borderStrong: Color(0xFF3A443F),
    textPrimary: Color(0xFFE8EFEB),
    textSecondary: Color(0xFFA7B4AE),
    textTertiary: Color(0xFF7C8B85),
    textDisabled: Color(0xFF5A6862),
    textOnDark: Color(0xFFFFFFFF),
    chartGrid: Color(0xFF262D2A),
    chartAxisText: Color(0xFF8B9A93),
    chartComparison: Color(0xFF7C8B85),
    tableHeaderBg: Color(0xFF1B211F),
    tableRowHover: Color(0xFF1E2724),
    tableRowStripe: Color(0xFF151A18),
    tableBorder: Color(0xFF2A322F),
    skeletonBase: Color(0xFF232A27),
    skeletonHighlight: Color(0xFF2E3633),
    shadow: Color(0x40000000),
    shadowStrong: Color(0x59000000),
    overlayScrim: Color(0x99000000),
  );

  // -------------------------------------------------------------------------
  // ThemeExtension
  // -------------------------------------------------------------------------

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? primary,
    Color? primaryHover,
    Color? primaryPressed,
    Color? onPrimary,
    Color? primarySoft,
    Color? onPrimarySoft,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnDark,
    Color? chartGrid,
    Color? chartAxisText,
    Color? chartComparison,
    Color? tableHeaderBg,
    Color? tableRowHover,
    Color? tableRowStripe,
    Color? tableBorder,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? shadow,
    Color? shadowStrong,
    Color? overlayScrim,
  }) =>
      AppColors(
        brightness: brightness ?? this.brightness,
        primary: primary ?? this.primary,
        primaryHover: primaryHover ?? this.primaryHover,
        primaryPressed: primaryPressed ?? this.primaryPressed,
        onPrimary: onPrimary ?? this.onPrimary,
        primarySoft: primarySoft ?? this.primarySoft,
        onPrimarySoft: onPrimarySoft ?? this.onPrimarySoft,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        warning: warning ?? this.warning,
        warningSoft: warningSoft ?? this.warningSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        textDisabled: textDisabled ?? this.textDisabled,
        textOnDark: textOnDark ?? this.textOnDark,
        chartGrid: chartGrid ?? this.chartGrid,
        chartAxisText: chartAxisText ?? this.chartAxisText,
        chartComparison: chartComparison ?? this.chartComparison,
        tableHeaderBg: tableHeaderBg ?? this.tableHeaderBg,
        tableRowHover: tableRowHover ?? this.tableRowHover,
        tableRowStripe: tableRowStripe ?? this.tableRowStripe,
        tableBorder: tableBorder ?? this.tableBorder,
        skeletonBase: skeletonBase ?? this.skeletonBase,
        skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
        shadow: shadow ?? this.shadow,
        shadowStrong: shadowStrong ?? this.shadowStrong,
        overlayScrim: overlayScrim ?? this.overlayScrim,
      );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryPressed: c(primaryPressed, other.primaryPressed),
      onPrimary: c(onPrimary, other.onPrimary),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimarySoft: c(onPrimarySoft, other.onPrimarySoft),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      textOnDark: c(textOnDark, other.textOnDark),
      chartGrid: c(chartGrid, other.chartGrid),
      chartAxisText: c(chartAxisText, other.chartAxisText),
      chartComparison: c(chartComparison, other.chartComparison),
      tableHeaderBg: c(tableHeaderBg, other.tableHeaderBg),
      tableRowHover: c(tableRowHover, other.tableRowHover),
      tableRowStripe: c(tableRowStripe, other.tableRowStripe),
      tableBorder: c(tableBorder, other.tableBorder),
      skeletonBase: c(skeletonBase, other.skeletonBase),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      shadow: c(shadow, other.shadow),
      shadowStrong: c(shadowStrong, other.shadowStrong),
      overlayScrim: c(overlayScrim, other.overlayScrim),
    );
  }
}

/// Convenience accessors. Both fall back to the matching light/dark default so
/// a widget can never crash because a theme forgot to register the extension.
extension AppColorsX on BuildContext {
  AppColors get appColors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  }
}
