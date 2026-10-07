import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Pure-Flutter shimmer. **No animation package is used** — just an
/// [AnimationController] driving a [LinearGradient] through a [ShaderMask].
///
/// Set `MediaQuery.disableAnimations` (the OS "reduce motion" setting) and it
/// stops animating and renders a static block, which keeps it usable for
/// motion-sensitive users.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    required this.child,
    super.key,
    this.borderRadius,
  });

  /// The shape to fill. Its own colour is discarded; the shimmer gradient
  /// supplies the pixels.
  final Widget child;

  final BorderRadius? borderRadius;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final shape = Container(
      color: colors.skeletonBase,
      child: widget.child,
    );

    if (reduceMotion) {
      return _clip(shape);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-2.0 + 4.0 * t, 0),
            end: Alignment(0.0 + 4.0 * t, 0),
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: shape,
        );
      },
    );
  }

  Widget _clip(Widget child) =>
      widget.borderRadius == null ? child : ClipRRect(borderRadius: widget.borderRadius!, child: child);
}

// ---------------------------------------------------------------------------
// Shape helpers — these are what callers compose into "loading" layouts.
// ---------------------------------------------------------------------------

/// A plain shimmering block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = AppRadius.controlRadius,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) => SkeletonLoader(
        borderRadius: borderRadius,
        child: SizedBox(width: width, height: height),
      );
}

/// One shimmering text line.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 11,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SkeletonLoader(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: width, height: height),
      );
}

/// Stacked lines of decreasing width — a generic "text block".
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.lines = 3, this.lineGap = AppSpacing.xs});

  final int lines;
  final double lineGap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) SizedBox(height: lineGap),
            // Last line is short, the way real text wraps.
            SkeletonLine(width: i == lines - 1 ? 140 : null),
          ],
        ],
      );
}

/// Placeholder for a KPI tile.
class SkeletonKpi extends StatelessWidget {
  const SkeletonKpi({super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          SkeletonBox(height: 36, width: 36, borderRadius: AppRadius.controlRadius),
          SizedBox(height: AppSpacing.sm),
          SkeletonLine(width: 92, height: 18),
          SizedBox(height: AppSpacing.xs),
          SkeletonLine(width: 64, height: 11),
        ],
      );
}

/// Placeholder for a list: [rows] lines each with a leading dot and two lines
/// of text.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5, this.rowGap = AppSpacing.sm});

  final int rows;
  final double rowGap;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) SizedBox(height: rowGap),
            Row(
              children: [
                const SkeletonBox(
                  height: 32,
                  width: 32,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(width: 150 + (i.isEven ? 0 : 60)),
                      const SizedBox(height: AppSpacing.xxs),
                      SkeletonLine(width: 90 + (i.isOdd ? 0 : 40), height: 9),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
}

/// Placeholder for a data table: a header band plus [rows] striped rows.
class SkeletonTable extends StatelessWidget {
  const SkeletonTable({
    super.key,
    this.rows = 6,
    this.columns = 5,
    this.rowHeight = AppSizes.tableRowHeight,
  });

  final int rows;
  final int columns;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(
            height: AppSizes.tableHeaderHeight,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var r = 0; r < rows; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: c == 0 ? 3 : 2,
                      child: SkeletonLine(
                        height: 10,
                        width: double.infinity,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
}

/// A shimmering block that fills whatever space it is given — used for charts.
class SkeletonChart extends StatelessWidget {
  const SkeletonChart({super.key, this.height = AppSizes.chartHeight});

  final double height;

  @override
  Widget build(BuildContext context) => SkeletonLoader(
        borderRadius: AppRadius.controlRadius,
        child: SizedBox(width: double.infinity, height: height),
      );
}
