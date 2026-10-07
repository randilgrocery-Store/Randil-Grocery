import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// The app type scale.
///
/// Only used by the new shell / dashboard components. The global
/// `ThemeData.textTheme` is deliberately left at Material's defaults so that
/// none of the existing screens shift by a single pixel; these named styles
/// are opted into explicitly.
///
/// Colours are baked in per brightness because this is a `ThemeExtension` —
/// so `context.typography.h2` is always readable on the surface behind it.
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography._({
    required this.brightness,
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.title,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
    required this.overline,
    required this.numberXl,
    required this.numberLg,
    required this.numberMd,
    required this.numberSm,
    required this.numberTable,
  });

  /// Page-level figure. Use at most once per screen.
  final TextStyle display;

  /// Screen / dialog title.
  final TextStyle h1;

  /// Card and section-header title.
  final TextStyle h2;

  /// Sub-section title, list group title.
  final TextStyle h3;

  /// Emphasised body text, list item title.
  final TextStyle title;

  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle label;

  /// Hint text, timestamps, secondary metadata.
  final TextStyle caption;

  /// Small uppercase group label above a set of fields.
  final TextStyle overline;

  // --- Numeric styles. All tabular so columns line up. ---------------------
  final TextStyle numberXl;
  final TextStyle numberLg;
  final TextStyle numberMd;
  final TextStyle numberSm;

  /// Body-sized numeric style for table cells.
  final TextStyle numberTable;

  final Brightness brightness;

  // -------------------------------------------------------------------------
  // Light
  // -------------------------------------------------------------------------

  static final AppTypography light = AppTypography._(
    brightness: Brightness.light,
    display: _s(30, FontWeight.w700, AppColors.light.textPrimary, h: 34),
    h1: _s(22, FontWeight.w700, AppColors.light.textPrimary, h: 28),
    h2: _s(17, FontWeight.w700, AppColors.light.textPrimary, h: 22),
    h3: _s(15, FontWeight.w600, AppColors.light.textPrimary, h: 20),
    title: _s(14, FontWeight.w600, AppColors.light.textPrimary, h: 20),
    body: _s(13, FontWeight.w400, AppColors.light.textSecondary, h: 18),
    bodyStrong: _s(13, FontWeight.w600, AppColors.light.textPrimary, h: 18),
    label: _s(12, FontWeight.w500, AppColors.light.textSecondary, h: 16),
    caption: _s(11, FontWeight.w400, AppColors.light.textTertiary, h: 15),
    overline: _s(10, FontWeight.w700, AppColors.light.textTertiary,
        h: 12, ls: 0.9),
    numberXl: _s(30, FontWeight.w700, AppColors.light.textPrimary,
        h: 34, tabular: true),
    numberLg: _s(24, FontWeight.w700, AppColors.light.textPrimary,
        h: 28, tabular: true),
    numberMd: _s(17, FontWeight.w700, AppColors.light.textPrimary,
        h: 22, tabular: true),
    numberSm: _s(14, FontWeight.w600, AppColors.light.textPrimary,
        h: 18, tabular: true),
    numberTable: _s(13, FontWeight.w400, AppColors.light.textPrimary,
        h: 18, tabular: true),
  );

  // -------------------------------------------------------------------------
  // Dark
  // -------------------------------------------------------------------------

  static final AppTypography dark = AppTypography._(
    brightness: Brightness.dark,
    display: _s(30, FontWeight.w700, AppColors.dark.textPrimary, h: 34),
    h1: _s(22, FontWeight.w700, AppColors.dark.textPrimary, h: 28),
    h2: _s(17, FontWeight.w700, AppColors.dark.textPrimary, h: 22),
    h3: _s(15, FontWeight.w600, AppColors.dark.textPrimary, h: 20),
    title: _s(14, FontWeight.w600, AppColors.dark.textPrimary, h: 20),
    body: _s(13, FontWeight.w400, AppColors.dark.textSecondary, h: 18),
    bodyStrong: _s(13, FontWeight.w600, AppColors.dark.textPrimary, h: 18),
    label: _s(12, FontWeight.w500, AppColors.dark.textSecondary, h: 16),
    caption: _s(11, FontWeight.w400, AppColors.dark.textTertiary, h: 15),
    overline: _s(10, FontWeight.w700, AppColors.dark.textTertiary,
        h: 12, ls: 0.9),
    numberXl: _s(30, FontWeight.w700, AppColors.dark.textPrimary,
        h: 34, tabular: true),
    numberLg: _s(24, FontWeight.w700, AppColors.dark.textPrimary,
        h: 28, tabular: true),
    numberMd: _s(17, FontWeight.w700, AppColors.dark.textPrimary,
        h: 22, tabular: true),
    numberSm: _s(14, FontWeight.w600, AppColors.dark.textPrimary,
        h: 18, tabular: true),
    numberTable: _s(13, FontWeight.w400, AppColors.dark.textPrimary,
        h: 18, tabular: true),
  );

  static TextStyle _s(
    double size,
    FontWeight weight,
    Color color, {
    double? h,
    double? ls,
    bool tabular = false,
  }) =>
      TextStyle(
        fontFamily: AppType.fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: h == null ? null : h / size,
        letterSpacing: ls,
        fontFeatures: tabular ? AppType.tabular : null,
      );

  // -------------------------------------------------------------------------
  // ThemeExtension
  // -------------------------------------------------------------------------

  @override
  AppTypography copyWith({
    Brightness? brightness,
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? title,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? numberXl,
    TextStyle? numberLg,
    TextStyle? numberMd,
    TextStyle? numberSm,
    TextStyle? numberTable,
  }) =>
      AppTypography._(
        brightness: brightness ?? this.brightness,
        display: display ?? this.display,
        h1: h1 ?? this.h1,
        h2: h2 ?? this.h2,
        h3: h3 ?? this.h3,
        title: title ?? this.title,
        body: body ?? this.body,
        bodyStrong: bodyStrong ?? this.bodyStrong,
        label: label ?? this.label,
        caption: caption ?? this.caption,
        overline: overline ?? this.overline,
        numberXl: numberXl ?? this.numberXl,
        numberLg: numberLg ?? this.numberLg,
        numberMd: numberMd ?? this.numberMd,
        numberSm: numberSm ?? this.numberSm,
        numberTable: numberTable ?? this.numberTable,
      );

  @override
  AppTypography lerp(covariant AppTypography? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => _lerpStyle(a, b, t);
    return AppTypography._(
      brightness: t < 0.5 ? brightness : other.brightness,
      display: l(display, other.display),
      h1: l(h1, other.h1),
      h2: l(h2, other.h2),
      h3: l(h3, other.h3),
      title: l(title, other.title),
      body: l(body, other.body),
      bodyStrong: l(bodyStrong, other.bodyStrong),
      label: l(label, other.label),
      caption: l(caption, other.caption),
      overline: l(overline, other.overline),
      numberXl: l(numberXl, other.numberXl),
      numberLg: l(numberLg, other.numberLg),
      numberMd: l(numberMd, other.numberMd),
      numberSm: l(numberSm, other.numberSm),
      numberTable: l(numberTable, other.numberTable),
    );
  }

  static TextStyle _lerpStyle(TextStyle a, TextStyle b, double t) {
    return TextStyle.lerp(a, b, t)!;
  }
}

/// Convenience accessor with a safe fallback, so a missing extension can never
/// crash a widget.
extension AppTypographyX on BuildContext {
  AppTypography get typography {
    final theme = Theme.of(this);
    return theme.extension<AppTypography>() ??
        (theme.brightness == Brightness.dark
            ? AppTypography.dark
            : AppTypography.light);
  }
}
