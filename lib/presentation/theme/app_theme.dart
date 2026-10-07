import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Bridges the design system into the app's existing [ThemeData].
///
/// ## Why this does not build a brand-new [ThemeData]
///
/// `ThemeProvider.lightTheme` / `darkTheme` already define the colours, card
/// radius, elevation, button padding and input decoration that every existing
/// screen (POS, Inventory, GRN, Reports, ...) is visually tuned against. If
/// the redesign replaced that ThemeData, all of those screens would restyle
/// at once.
///
/// Instead [of] takes the existing theme and **adds only**:
///   * the Inter font family (Q6 — bundled as an asset, works offline), and
///   * the [AppColors] + [AppTypography] theme extensions.
///
/// Everything else is inherited untouched. Notably `appBarTheme` is
/// deliberately NOT set, because `pos_screen.dart:1038` reads
/// `Theme.of(context).appBarTheme.backgroundColor` and expects the default.
///
/// This is a pure presentation-layer function. It touches no provider.
abstract final class AppTheme {
  AppTheme._();

  /// Merges the design system into [base].
  static ThemeData of(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    return base.copyWith(
      textTheme: _withFont(base.textTheme),
      primaryTextTheme: _withFont(base.primaryTextTheme),
      extensions: <ThemeExtension<dynamic>>[
        dark ? AppColors.dark : AppColors.light,
        dark ? AppTypography.dark : AppTypography.light,
      ],
    );
  }

  static ThemeData ofLight(ThemeData base) =>
      of(base.copyWith(brightness: Brightness.light));

  static ThemeData ofDark(ThemeData base) =>
      of(base.copyWith(brightness: Brightness.dark));

  static TextTheme _withFont(TextTheme theme) =>
      theme.apply(fontFamily: AppType.fontFamily);

  // -------------------------------------------------------------------------
  // Widget-side accessors
  // -------------------------------------------------------------------------

  /// The resolved design-system colours for this context.
  static AppColors colors(BuildContext context) => context.appColors;

  /// The resolved type scale for this context.
  static AppTypography typography(BuildContext context) => context.typography;
}
