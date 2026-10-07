import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_money.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// A single headline metric.
///
/// Deliberately a **clean neutral surface** with a small icon chip — never a
/// full-gradient block. The value string is supplied already formatted (use
/// [AppMoney.format] / [AppMoney.compact]) so this widget never has to guess a
/// currency.
///
/// The trend chip is ALWAYS rendered. When there is no usable previous period
/// it says "no prior data" rather than silently disappearing, so an absent
/// comparison is never mistaken for a flat one.
class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.label,
    required this.value,
    super.key,
    this.icon,
    this.tone = StatusTone.neutral,
    this.trend,
    this.trendCaption,
    this.secondary,
    this.sparkline,
    this.onTap,
    this.tooltip,
  });

  final String label;

  /// Pre-formatted headline figure, e.g. `Rs 14,770.00`.
  final String value;

  final IconData? icon;
  final StatusTone tone;

  /// Relative change as a **fraction** from [AppMoney.trend] (0.20 == +20%).
  /// `null` renders the "no prior data" chip.
  final double? trend;

  /// e.g. "vs previous 7 days". Shown under the trend chip when supplied.
  final String? trendCaption;

  /// Small secondary line, typically today's figure.
  final Widget? secondary;

  /// Optional sparkline. Used only on Total Sales and Net Profit.
  final Widget? sparkline;

  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final accent = tone.fg(colors);

    Widget card = AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: AppSizes.kpiIconChip,
                  height: AppSizes.kpiIconChip,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.bg(colors),
                    borderRadius: AppRadius.controlRadius,
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: t.numberMd,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _TrendChip(trend: trend, caption: trendCaption),
          if (secondary != null) ...[
            const SizedBox(height: AppSpacing.xs),
            secondary!,
          ],
          if (sparkline != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(height: AppSizes.sparklineHeight, child: sparkline),
          ],
        ],
      ),
    );

    if (tooltip == null) return card;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: card,
    );
  }
}

/// Always-visible trend indicator.
class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.trend, this.caption});

  final double? trend;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;

    if (trend == null) {
      return Row(
        children: [
          Icon(Icons.remove, size: 13, color: colors.textTertiary),
          const SizedBox(width: 3),
          Text('no prior data', style: t.caption),
          if (caption != null) ...[
            const SizedBox(width: AppSpacing.xs - 2),
            Text('• $caption', style: t.caption),
          ],
        ],
      );
    }

    final up = trend! > 0.005;
    final down = trend! < -0.005;
    final tone = up
        ? StatusTone.success
        : down
            ? StatusTone.danger
            : StatusTone.neutral;
    final fg = tone.fg(colors);

    return Row(
      children: [
        Icon(
          up
              ? Icons.trending_up
              : down
                  ? Icons.trending_down
                  : Icons.trending_flat,
          size: 14,
          color: fg,
        ),
        const SizedBox(width: 3),
        Text(
          AppMoney.signedPercent(trend!),
          style: t.label.copyWith(
            color: fg,
            fontWeight: FontWeight.w700,
            fontFeatures: AppType.tabular,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(width: AppSpacing.xs - 2),
          Flexible(
            child: Text(
              '• $caption',
              style: t.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
