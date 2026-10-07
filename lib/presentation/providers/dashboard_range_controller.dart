import 'package:flutter/foundation.dart';

/// Time-range presets shared by the dashboard KPI row, revenue chart, range
/// picker and Profit & Loss panel, plus the [custom] picker mode.
///
/// Lives here (not in a screen) so the shell's range picker, the dashboard and
/// the profit-and-loss panel all agree on the same values.
enum DashboardRange { today, last7Days, last30Days, custom }

/// Owns the dashboard's selected time range and derives every date boundary
/// the dashboard needs from it.
///
/// A [ChangeNotifier] so the range picker, the KPI row and the Profit & Loss
/// card stay in sync without prop drilling. The "previous period" boundaries
/// are computed here too, so a "vs previous period" comparison always measures
/// like against like — even for [DashboardRange.custom].
class DashboardRangeController extends ChangeNotifier {
  DashboardRange _selected = DashboardRange.last7Days;
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();

  DashboardRange get selected => _selected;

  bool get isCustom => _selected == DashboardRange.custom;

  /// The custom picker's chosen start, normalised to midnight.
  DateTime get customStart => _customStart;

  /// The custom picker's chosen end, normalised to 23:59:59.
  DateTime get customEnd => _customEnd;

  /// Compact chip label: `Today` / `7D` / `30D` / `Custom`.
  String get shortLabel => _label(short: true);

  /// Sentence-style label for panel headers: `Last 7 days` / `Custom range`.
  String get fullLabel => _label(short: false);

  /// Length of the selected period in days. [DashboardRange.custom] reports
  /// its true span.
  int get days => isCustom
      ? _customEnd.difference(_customStart).inDays + 1
      : _presetDays(_selected);

  /// Selects a preset range. Bare [DashboardRange.custom] selections are
  /// refused — use [selectCustom] so a picker can never leave an empty range.
  void select(DashboardRange range) {
    if (range == DashboardRange.custom) return;
    if (_selected == range) return;
    _selected = range;
    notifyListeners();
  }

  /// Applies the custom picker range and switches to it.
  ///
  /// The start is clamped to midnight and the end to the last second of its
  /// day, so a hand-picked range always covers whole days. Ranges shorter
  /// than one full day are rejected.
  void selectCustom(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59);
    if (!s.isBefore(e)) return;
    _customStart = s;
    _customEnd = e;
    _selected = DashboardRange.custom;
    notifyListeners();
  }

  /// First instant of the selected period.
  DateTime rangeStart(DateTime now) {
    if (isCustom) return _customStart;
    final startOfDay = DateTime(now.year, now.month, now.day);
    return switch (_presetDays(_selected)) {
      1 => startOfDay,
      7 => startOfDay.subtract(const Duration(days: 6)),
      30 => startOfDay.subtract(const Duration(days: 29)),
      _ => startOfDay,
    };
  }

  /// Last instant (inclusive) of the selected period.
  DateTime rangeEnd(DateTime now) {
    if (isCustom) return _customEnd;
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  /// First instant of the period immediately before the selected one, the
  /// same length. Backs every "vs previous period" readout.
  DateTime previousPeriodStart(DateTime now) {
    if (isCustom) {
      final span = _customEnd.difference(_customStart) +
          const Duration(seconds: 1);
      return _customStart.subtract(span);
    }
    return rangeStart(now).subtract(Duration(days: _presetDays(_selected)));
  }

  /// Last instant (inclusive) of the previous period.
  DateTime previousPeriodEnd(DateTime now) =>
      rangeStart(now).subtract(const Duration(milliseconds: 1));

  String _label({required bool short}) {
    if (isCustom) return short ? 'Custom' : 'Custom range';
    return switch (_selected) {
      DashboardRange.today => short ? 'Today' : 'Today',
      DashboardRange.last7Days => short ? '7D' : 'Last 7 days',
      DashboardRange.last30Days => short ? '30D' : 'Last 30 days',
      DashboardRange.custom => short ? 'Custom' : 'Custom range',
    };
  }

  int _presetDays(DashboardRange range) => switch (range) {
        DashboardRange.today => 1,
        DashboardRange.last7Days => 7,
        DashboardRange.last30Days => 30,
        DashboardRange.custom => 1,
      };
}