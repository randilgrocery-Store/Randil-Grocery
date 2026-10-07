import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Title + optional subtitle + optional trailing action, used above every
/// panel. The legacy `SectionHeader` in `custom_widgets.dart` delegates here.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.action,
    this.icon,
    this.tone,
    this.dense = false,
  });

  final String title;
  final String? subtitle;

  /// Trailing widget (button, link, filter).
  final Widget? action;

  /// Optional leading icon inside a soft chip.
  final IconData? icon;

  /// Tint for the icon chip. Defaults to the neutral tertiary text colour so
  /// headers stay quiet; pass a semantic colour only when the section is an
  /// alert.
  final Color? tone;

  /// Tighter spacing for headers nested inside a card.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final accent = tone ?? colors.textTertiary;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: dense ? t.h3 : t.h2),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle!, style: t.caption),
        ],
      ],
    );

    final Row row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: AppSizes.kpiIconChip,
            height: AppSizes.kpiIconChip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: colors.isDark ? 0.22 : 0.12),
              borderRadius: AppRadius.controlRadius,
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: heading),
        if (action != null) ...[
          const SizedBox(width: AppSpacing.sm),
          action!,
        ],
      ],
    );

    if (!dense) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row,
          const SizedBox(height: AppSpacing.md),
        ],
      );
    }
    return row;
  }
}
