import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Semantic accent for a card. Neutral is the default and is used for ~95% of
/// cards; the other tones exist so an alert panel can carry meaning without
/// inventing a new card style.
enum AppCardTone { neutral, primary, success, warning, danger, info }

/// THE card. Every surface in the new shell and dashboard is this widget, and
/// the legacy `GroceryCard` in `custom_widgets.dart` delegates to it, so the
/// app has exactly one card radius, one padding and one shadow.
///
/// A card is a clean neutral surface. It never uses a gradient fill.
class AppCard extends StatefulWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = AppSpacing.card,
    this.onTap,
    this.backgroundColor,
    this.borderRadius,
    this.tone = AppCardTone.neutral,
    this.selected = false,
    this.showBorder = true,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Override the surface colour. Used by the legacy `GroceryCard`, which
  /// tints admin user rows.
  final Color? backgroundColor;

  /// Overrides the shared 16px radius. Only the legacy delegation passes this.
  final BorderRadius? borderRadius;

  final AppCardTone tone;
  final bool selected;
  final bool showBorder;
  final bool clipContent;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  Color? _toneColor(AppColors c) => switch (widget.tone) {
        AppCardTone.neutral => null,
        AppCardTone.primary => c.primary,
        AppCardTone.success => c.success,
        AppCardTone.warning => c.warning,
        AppCardTone.danger => c.danger,
        AppCardTone.info => c.info,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent = _toneColor(colors);
    final clickable = widget.onTap != null;
    final lifted = clickable && _hovered;

    final surface = widget.backgroundColor ??
        (accent == null || !widget.selected
            ? colors.surface
            : Color.alphaBlend(accent.withValues(alpha: 0.06), colors.surface));

    final borderColor = widget.selected && accent != null
        ? accent.withValues(alpha: 0.45)
        : (accent != null
            ? accent.withValues(alpha: 0.28)
            : colors.border);

    final decoration = BoxDecoration(
      color: surface,
      borderRadius: widget.borderRadius ?? AppRadius.cardRadius,
      border: widget.showBorder
          ? Border.all(
              color: lifted ? colors.borderStrong : borderColor,
            )
          : null,
      boxShadow: lifted ? colors.cardShadowHover : colors.cardShadow,
    );

    Widget content = Padding(
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.clipContent) {
      content = ClipRRect(
        borderRadius: widget.borderRadius ?? AppRadius.cardRadius,
        child: content,
      );
    }

    if (!clickable) {
      return AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        decoration: decoration,
        child: content,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          decoration: decoration,
          child: content,
        ),
      ),
    );
  }
}
