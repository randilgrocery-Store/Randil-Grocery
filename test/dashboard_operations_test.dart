import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/main.dart';

/// Renders the REAL admin dashboard (full provider stack, real sqflite engine,
/// real temp database seeded with standard accounts) and verifies:
///   * the Reload / Repack / Wastage operations row draws,
///   * the Revenue-trend + Profit&Loss cards line up top-and-bottom on wide
///     windows (no empty slot below the chart),
///   * the layout survives every window size from small to full HD with zero
///     exceptions or RenderFlex overflows.
///
/// Only ONE app instance is pumped per process: re-pumping the full app in a
/// second testWidgets in the same process trips "ThemeProvider was used after
/// being disposed" because real-async work from the first test outlives it. So
/// every resolution is exercised on the same instance by resizing the view.
///
/// Run with a scratch LOCALAPPDATA so the smoke database never touches the
/// client's live data:
///   $env:LOCALAPPDATA = "$env:TEMP\randil_dash_smoke" ; flutter test ...
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets(
      'admin dashboard renders fully and gap-free at every window size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    BackupService.setGithubBackupEnabled(false);

    // Capture FULL diagnostics for any layout error (the RenderFlex creator
    // chain is only available at report time, not from takeException).
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('RES-BUG-SEEN:\n${details.toString()}');
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    const sizes = <Size>[
      Size(1024, 768), // stacked layout (below minSupportedWidth)
      Size(1280, 720), // row layout, KPI wraps 2-up, short single-touch POS
      Size(1366, 860), // client baseline fullscreen window
      Size(1920, 1080), // large desktop / full HD
    ];

    // Mimic the client's fullscreen window exactly.
    tester.view.physicalSize = sizes[2];
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const RandilGroceryPOS());
    await tester.pump(const Duration(milliseconds: 1100));

    // Bootstrapping futz: let the real (isolate) DB work complete.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    // Login as the seeded default admin.
    await tester.enterText(find.byType(TextField).at(0), 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'admin123');
    await tester.tap(find.text('Login'));
    await tester.pump();

    // Let login + dashboard data load run against the real engine.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    // The dashboard must be present with the full operations overview.
    expect(find.text('Revenue trend'), findsOneWidget);
    expect(find.text('Profit & Loss'), findsOneWidget);
    expect(find.text('Recent bills'), findsOneWidget);
    expect(find.text('Reload credit'), findsOneWidget);
    expect(find.text('Repack & production'), findsOneWidget);
    expect(find.text('Wastage'), findsWidgets);
    expect(find.text('Bought'), findsWidgets);
    expect(find.text('Profit'), findsWidgets);
    expect(find.text('Packed (all time)'), findsWidgets);
    expect(find.text('On hand now'), findsWidgets);
    expect(find.text('Records'), findsWidgets);
    expect(find.text('Worth lost'), findsWidgets);

    for (final size in sizes) {
      // Resize the "window" and let the dashboard re-layout at this resolution.
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final revFinder = find.byKey(const ValueKey('dashboard-revenue-chart'));
      final plFinder = find.byKey(const ValueKey('dashboard-pl-panel'));
      final revBox = tester.renderObject<RenderBox>(revFinder);
      final plBox = tester.renderObject<RenderBox>(plFinder);

      final revTop = tester.getTopLeft(revFinder).dy;
      final revBottom = revTop + revBox.size.height;
      final plTop = tester.getTopLeft(plFinder).dy;
      final plBottom = plTop + plBox.size.height;

      if ((plTop - revTop).abs() < 200) {
        // Side-by-side layout: identical top AND bottom edges => no empty
        // slot under the revenue trend chart.
        expect(revTop, closeTo(plTop, 0.5),
            reason: 'cards must share a top edge at $size');
        expect(revBottom, closeTo(plBottom, 0.5),
            reason: 'no empty slot under the revenue chart at $size');
      } else {
        // Stacked layout: the chart card sits above the P&L card.
        expect(plTop, greaterThan(revBottom - 1),
            reason: 'cards must stack cleanly at $size');
      }

      // No RenderFlex overflow or any other layout exception at this size.
      expect(tester.takeException(), isNull,
          reason: 'layout must not crash at $size');
    }

    // Let the deferred dashboard refresh (products, reports, P&L, and the three
    // unawaited operations loads) finish so nothing notifies after disposal.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Tear the tree down so polling/clock timers are disposed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}