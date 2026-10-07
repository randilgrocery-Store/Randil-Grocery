import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Responsive "design canvas" used to make the POS render correctly on any
/// display resolution (small VGA panels up to 1920x1080+ POS terminals such
/// as the XPrinter TP-1615N).
///
/// The whole UI is authored against a fixed [designWidth] x [designHeight]
/// logical canvas (the resolution the screens were originally built for).
/// [scaleFor] computes a single uniform factor that makes that canvas fill
/// the actual window. Because the scale is applied to the *entire* render
/// tree, nothing can ever overflow or clip regardless of the monitor's
/// resolution or aspect ratio, and touch targets grow proportionally on
/// larger screens.
class UiScaler {
  UiScaler._();

  /// The logical canvas the POS screens were designed against.
  ///
  /// 16:9 (1536x864). A 1920x1080 terminal (the TP-1615N) maps to exactly
  /// 1.25x, a 1536x864 display to 1.0x, a 1366x768 display to ~0.89x —
  /// always fills edge-to-edge with no letterbox bars on common panels.
  static const double designWidth = 1536;
  static const double designHeight = 864;

  /// Safety bounds so a degenerate or absurd window size can never produce
  /// an unusable scale.
  static const double _minScale = 0.4;
  static const double _maxScale = 3.0;

  /// Uniform scale that fits [window] onto the design canvas, letterboxing
  /// (centering) when the aspect ratios differ.
  static double scaleFor(Size window) {
    if (window.width <= 0 || window.height <= 0) {
      return 1.0;
    }
    final raw = math.min(
      window.width / designWidth,
      window.height / designHeight,
    );
    return raw.clamp(_minScale, _maxScale);
  }

  /// Wraps the app's navigator (and everything inside it, including dialogs,
  /// menus and snackbars) in the scaling canvas. The subtree is given the
  /// design-size viewport via a MediaQuery override so every screen behaves
  /// exactly as it was designed, then the whole painted result is scaled to
  /// fill the window. [background] is the letterbox colour shown when the
  /// window's aspect ratio differs from the canvas.
  static Widget wrap(
    Widget child,
    MediaQueryData mq,
    double scale, {
    Color background = const Color(0xFFF5F6FA),
  }) {
    return ColoredBox(
      color: background,
      child: Center(
        child: SizedBox(
          width: designWidth * scale,
          height: designHeight * scale,
          child: Transform.scale(
            scale: scale,
            child: MediaQuery(
              data: mq.copyWith(
                size: const Size(designWidth, designHeight),
                // The canvas already adapts the effective size; ignore any
                // OS "make text bigger" setting so layouts stay deterministic.
                textScaler: TextScaler.noScaling,
              ),
              child: OverflowBox(
                maxWidth: designWidth,
                maxHeight: designHeight,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}