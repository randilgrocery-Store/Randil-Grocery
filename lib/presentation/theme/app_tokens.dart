import 'package:flutter/material.dart';

/// Design tokens for the Randil Grocery POS presentation layer.
///
/// Pure values only — no widgets, no colours, no state. Colours live in
/// [AppColors] and the type scale lives in [AppTypography]; both are
/// `ThemeExtension`s so light and dark mode share one set of tokens.
///
/// These are the ONLY spacing / radius / duration values the new dashboard and
/// shell are allowed to use, so the whole UI stays on a single rhythm.

// ---------------------------------------------------------------------------
// Spacing — the 4 / 8 / 12 / 16 / 24 / 32 scale
// ---------------------------------------------------------------------------

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Inner padding of a standard card.
  static const EdgeInsets card = EdgeInsets.all(md);

  /// Inner padding of a dense panel (tables, lists).
  static const EdgeInsets panel = EdgeInsets.all(sm);

  /// Gutter used between sibling cards in a row.
  static const double gutter = md;
}

// ---------------------------------------------------------------------------
// Radii — one card radius for the entire app
// ---------------------------------------------------------------------------

abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;

  /// THE card radius. Matches the radius already used by the existing
  /// `ThemeProvider` card theme (16) so old and new surfaces line up.
  static const double lg = 16;

  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius controlRadius =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius pillRadius =
      BorderRadius.all(Radius.circular(pill));
}

// ---------------------------------------------------------------------------
// Motion — subtle, 150–300ms
// ---------------------------------------------------------------------------

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

// ---------------------------------------------------------------------------
// Sizes — layout constants for the shell and dashboard
// ---------------------------------------------------------------------------

abstract final class AppSizes {
  /// Minimum click target. POS terminals are touch screens.
  static const double minTapTarget = 44;

  static const double topBarHeight = 60;

  static const double sidebarExpanded = 236;
  static const double sidebarCollapsed = 64;

  static const double kpiIconChip = 36;
  static const double statusDot = 8;

  static const double tableHeaderHeight = 40;
  static const double tableRowHeight = minTapTarget;

  static const double chartHeight = 240;
  static const double sparklineHeight = 28;
}

// ---------------------------------------------------------------------------
// Breakpoints — desktop-first. The POS is never a phone.
// ---------------------------------------------------------------------------

abstract final class AppBreakpoints {
  /// Below this the dashboard degrades to a scrolling single/double column.
  static const double minSupportedWidth = 1100;

  /// Sidebar starts collapsed under this window width.
  static const double sidebarAutoCollapseBelow = 1500;

  /// Enough room for the 6 KPI cards in one non-wrapping row.
  static const double kpiRowFits = 1180;

  static const double wide = 1600;
  static const double ultraWide = 1920;
}

// ---------------------------------------------------------------------------
// Type — Inter, bundled as an asset so LAN / offline terminals get it.
// ---------------------------------------------------------------------------

abstract final class AppType {
  /// Family name declared in `pubspec.yaml`.
  static const String fontFamily = 'Inter';

  /// OpenType `tnum`. Applied to every number so columns of money line up
  /// and animated counters do not jitter as digits change width. Verified
  /// present in all four bundled weights.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}
