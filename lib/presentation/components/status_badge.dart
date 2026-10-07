import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Meaning carried by a [StatusBadge]. Semantic tones are for meaning only;
/// `neutral` is the default and is what the payment badges use so Cash / Card /
/// Split do not read as a rainbow.
enum StatusTone { neutral, primary, success, warning, danger, info }

extension StatusToneX on StatusTone {
  Color fg(AppColors c) => switch (this) {
        StatusTone.neutral => c.textSecondary,
        StatusTone.primary => c.onPrimarySoft,
        StatusTone.success => c.success,
        StatusTone.warning => c.warning,
        StatusTone.danger => c.danger,
        StatusTone.info => c.info,
      };

  Color bg(AppColors c) => switch (this) {
        StatusTone.neutral => c.surfaceMuted,
        StatusTone.primary => c.primarySoft,
        StatusTone.success => c.successSoft,
        StatusTone.warning => c.warningSoft,
        StatusTone.danger => c.dangerSoft,
        StatusTone.info => c.infoSoft,
      };
}

/// A small pill used for statuses, counts and payment methods.
///
/// Every badge in the app uses this one widget, so padding, radius, type size
/// and colours can never drift apart.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dense = false,
    this.showDot = false,
  });

  /// Builds a badge that only shows a coloured dot plus text.
  const StatusBadge.dot({
    required this.label,
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dense = false,
    this.showDot = true,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool dense;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final fg = tone.fg(colors);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.xs : AppSpacing.sm,
        vertical: dense ? 2 : AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: tone.bg(colors),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: AppSizes.statusDot - 2,
              height: AppSizes.statusDot - 2,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs - 2),
          ] else if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            const SizedBox(width: AppSpacing.xs - 3),
          ],
          Text(
            label,
            style: (dense ? t.caption : t.label).copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              fontFeatures: AppType.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// Just the dot, for dense table cells where a full pill is too heavy.
class StatusDot extends StatelessWidget {
  const StatusDot({required this.tone, super.key, this.size = AppSizes.statusDot});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tone.fg(context.appColors),
          shape: BoxShape.circle,
        ),
      );
}
