import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:randil_grocery_pos/presentation/widgets/date_range_filter_bar.dart';

/// The date/month filter shared by the reload, wastage, shopping bag and
/// refund screens. These tests guard the window maths — every preset must
/// produce an inclusive, gap-free range that `includes()` treats sanely.
void main() {
  group('DateRangeFilterBar windows', () {
    test('all-time window has no bounds and includes any moment', () {
      final w = DateRangeFilterBar.windowFor(DateRangePreset.all);
      expect(w.isAll, isTrue);
      expect(w.start, isNull);
      expect(w.end, isNull);
      expect(w.includes(DateTime(1999, 1, 1)), isTrue);
      expect(w.includes(DateTime.now()), isTrue);
    });

    test('today window is one full day ending at 23:59:59', () {
      final w = DateRangeFilterBar.windowFor(DateRangePreset.today);
      final now = DateTime.now();
      expect(w.isAll, isFalse);
      expect(w.start, DateTime(now.year, now.month, now.day));
      expect(w.end, DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      expect(w.includes(DateTime(now.year, now.month, now.day, 12)), isTrue);
      expect(
          w.includes(DateTime(now.year, now.month, now.day)
              .add(const Duration(days: 1))),
          isFalse);
    });

    test('this month is the whole current calendar month', () {
      final w = DateRangeFilterBar.windowFor(DateRangePreset.thisMonth);
      final now = DateTime.now();
      expect(w.start, DateTime(now.year, now.month, 1));
      expect(w.end, DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999));
      expect(w.includes(DateTime(now.year, now.month, 15, 23, 59)), isTrue);
      expect(w.includes(DateTime(now.year, now.month + 1, 1)), isFalse);
      expect(w.includes(DateTime(now.year, now.month - 1, 28)), isFalse);
    });

    test('last month is the whole previous calendar month', () {
      final w = DateRangeFilterBar.windowFor(DateRangePreset.lastMonth);
      final now = DateTime.now();
      expect(w.start, DateTime(now.year, now.month - 1, 1));
      expect(w.end, DateTime(now.year, now.month, 0, 23, 59, 59, 999));
    });

    test('custom range is inclusive through the last second of the last day',
        () {
      final custom = DateTimeRange(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 8),
      );
      final w = DateRangeFilterBar.windowFor(
        DateRangePreset.custom,
        custom: custom,
      );
      expect(w.start, DateTime(2026, 10, 5));
      expect(w.end, DateTime(2026, 10, 8, 23, 59, 59, 999));
      expect(w.includes(DateTime(2026, 10, 5, 0, 0, 0)), isTrue);
      expect(w.includes(DateTime(2026, 10, 8, 23, 59, 59, 999)), isTrue);
      expect(w.includes(DateTime(2026, 10, 9)), isFalse);
      expect(w.includes(DateTime(2026, 10, 4, 23, 59, 59, 999)), isFalse);
    });

    test('effectiveStart/effectiveEnd widen an empty window to cover all', () {
      final all = DateRangeFilterBar.windowFor(DateRangePreset.all);
      expect(all.effectiveStart, DateTime(2000));
      expect(all.effectiveEnd.year, 2100);

      final today = DateRangeFilterBar.windowFor(DateRangePreset.today);
      expect(today.effectiveStart, today.start);
      expect(today.effectiveEnd, today.end);
    });
  });
}