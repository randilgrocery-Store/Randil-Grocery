import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Self-contained clock for the dashboard header.
///
/// Ticks once per second while it is actually visible and fires [onMinute]
/// silently at minute boundaries, so the dashboard can refresh its data every
/// 60 seconds without a visible spinner.
///
/// Pausing: the widget stops ticking when it is not on screen via
/// [TickerMode] (used by `Offstage` / tab switches), and it stops completely
/// when its parent is disposed. The shell only mounts the selected screen, so
/// navigating away tears the timer down as well.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key, this.onMinute, this.lastUpdated});

  /// Called silently at minute boundaries — the dashboard's refresh hook.
  /// Never invoked while the clock is paused.
  final VoidCallback? onMinute;

  /// When provided, an `Updated HH:MM:SS` caption is shown under the time.
  final DateTime? lastUpdated;

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  int _lastWholeMinute = -1;

  static final DateFormat _time = DateFormat('HH:mm:ss');
  static final DateFormat _date = DateFormat('EEE, d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _lastWholeMinute = _now.minute;
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    // Respect Offstage / tab visibility: no setState churn, no refresh calls
    // while the clock is not actually on screen.
    if (!TickerMode.of(context)) return;

    final now = DateTime.now();
    final minute = now.minute;
    if (minute != _lastWholeMinute) {
      _lastWholeMinute = minute;
      widget.onMinute?.call();
    }
    setState(() => _now = now);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSizes.kpiIconChip,
          height: AppSizes.kpiIconChip,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primarySoft,
            borderRadius: AppRadius.pillRadius,
          ),
          child: Icon(Icons.schedule, size: 18, color: colors.onPrimarySoft),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _time.format(_now),
              style: typography.numberMd,
            ),
            Text(_date.format(_now), style: typography.caption),
            if (widget.lastUpdated != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 12, color: colors.textTertiary),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Updated ${_time.format(widget.lastUpdated!)}',
                    style: typography.caption.copyWith(
                      fontFeatures: AppType.tabular,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}