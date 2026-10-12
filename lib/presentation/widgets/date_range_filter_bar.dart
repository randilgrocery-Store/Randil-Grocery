import 'package:flutter/material.dart';

/// Quick date windows for viewing a ledger: all time, today, yesterday, this
/// week, this month, last month, or any custom range.
///
/// Used by the reload, wastage, shopping bag and refund screens so every
/// feature can be sorted/filtered by date and month — the same filter the
/// shop owner expects to find everywhere.
enum DateRangePreset {
  all,
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  custom,
}

/// A resolved, *inclusive* date window. [start] is the first moment of the
/// first day and [end] is the last second of the last day; both are null for
/// "all time".
class DateWindow {
  const DateWindow({this.start, this.end, required this.label});

  final DateTime? start;
  final DateTime? end;
  final String label;

  bool get isAll => start == null && end == null;

  /// True when [moment] falls inside this window.
  bool includes(DateTime moment) {
    if (isAll) return true;
    final s = start;
    final e = end;
    if (s != null && moment.isBefore(s)) return false;
    if (e != null && moment.isAfter(e)) return false;
    return true;
  }

  /// The window widened to cover everything (for a total/overall number that
  /// must never be blank).
  DateTime get effectiveStart => start ?? DateTime(2000);
  DateTime get effectiveEnd => end ?? DateTime(2100);
}

/// Horizontal strip of FilterChips offering every [DateRangePreset]. Selecting
/// "Custom…" opens a date-range picker. The parent keeps [selectedPreset] and
/// [customRange] and derives the actual [DateWindow] with [windowFor].
class DateRangeFilterBar extends StatelessWidget {
  const DateRangeFilterBar({
    required this.selectedPreset,
    required this.customRange,
    required this.onSelected,
    super.key,
  });

  final DateRangePreset selectedPreset;
  final DateTimeRange? customRange;
  final void Function(DateRangePreset preset, DateTimeRange? custom) onSelected;

  /// Midnight of [d].
  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The last moment of [day] ('day' can itself be a date created via day 0
  /// arithmetic), including milliseconds so a record saved mid-last-second is
  /// still inside the window.
  static DateTime _endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

  /// Resolves a preset (+ an optional custom range) into an inclusive window.
  static DateWindow windowFor(DateRangePreset preset, {DateTimeRange? custom}) {
    final now = DateTime.now();
    switch (preset) {
      case DateRangePreset.all:
        return const DateWindow(label: 'All time');
      case DateRangePreset.today:
        final s = dayOf(now);
        return DateWindow(start: s, end: _endOfDay(s), label: 'Today');
      case DateRangePreset.yesterday:
        final s = dayOf(now.subtract(const Duration(days: 1)));
        return DateWindow(start: s, end: _endOfDay(s), label: 'Yesterday');
      case DateRangePreset.thisWeek:
        final monday = dayOf(now).subtract(Duration(days: now.weekday - 1));
        return DateWindow(
          start: monday,
          end: _endOfDay(monday.add(const Duration(days: 6))),
          label: 'This week',
        );
      case DateRangePreset.thisMonth:
        final s = DateTime(now.year, now.month, 1);
        return DateWindow(
          start: s,
          // Day 0 of next month = the last day of this month.
          end: _endOfDay(DateTime(now.year, now.month + 1, 0)),
          label: 'This month',
        );
      case DateRangePreset.lastMonth:
        final s = DateTime(now.year, now.month - 1, 1);
        return DateWindow(
          start: s,
          end: _endOfDay(DateTime(now.year, now.month, 0)),
          label: 'Last month',
        );
      case DateRangePreset.custom:
        if (custom == null) return const DateWindow(label: 'Custom range');
        final start = dayOf(custom.start);
        final end = dayOf(custom.end);
        return DateWindow(
          start: start,
          end: _endOfDay(end),
          label: '${_fmt(start)} – ${_fmt(end)}',
        );
    }
  }

  static String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange:
          customRange ?? DateTimeRange(start: dayOf(now), end: dayOf(now)),
      helpText: 'Pick a date range',
      saveText: 'Apply',
    );
    if (picked != null) {
      onSelected(DateRangePreset.custom, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = <(DateRangePreset, String)>[
      (DateRangePreset.all, 'All time'),
      (DateRangePreset.today, 'Today'),
      (DateRangePreset.yesterday, 'Yesterday'),
      (DateRangePreset.thisWeek, 'This week'),
      (DateRangePreset.thisMonth, 'This month'),
      (DateRangePreset.lastMonth, 'Last month'),
      (DateRangePreset.custom, customRange == null
          ? 'Custom…'
          : windowFor(DateRangePreset.custom, custom: customRange).label),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (preset, label) in entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: selectedPreset == preset,
                onSelected: (_) {
                  if (preset == DateRangePreset.custom) {
                    _pickCustom(context);
                  } else {
                    onSelected(preset, null);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}