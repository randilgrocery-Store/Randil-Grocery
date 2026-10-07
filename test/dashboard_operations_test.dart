import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/main.dart';

/// Renders the REAL admin dashboard (full provider stack, real sqflite engine,
/// real temp database seeded with standard accounts) and verifies the
/// Reload / Repack / Wastage operations row draws.
///
/// Run with a scratch LOCALAPPDATA so the smoke database never touches the
/// client's live data:
///   $env:LOCALAPPDATA = "$env:TEMP\randil_dash_smoke" ; flutter test ...
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  testWidgets('admin dashboard renders the operations overview row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    BackupService.setGithubBackupEnabled(false);

    // Mimic the client's fullscreen window exactly.
    tester.view.physicalSize = const Size(1366, 860);
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

    // The new operations overview must be on screen, all three panels.
    expect(find.text('Reload credit'), findsOneWidget);
    expect(find.text('Repack & production'), findsOneWidget);
    expect(find.text('Wastage'), findsOneWidget);

    // And the KPI blocks inside them.
    expect(find.text('Bought'), findsWidgets);
    expect(find.text('Profit'), findsWidgets);
    expect(find.text('Packed (all time)'), findsWidgets);
    expect(find.text('On hand now'), findsWidgets);
    expect(find.text('Records'), findsWidgets);
    expect(find.text('Worth lost'), findsWidgets);

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