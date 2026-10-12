import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/presentation/providers/auth_provider.dart';
import 'package:randil_grocery_pos/presentation/providers/batch_provider.dart';
import 'package:randil_grocery_pos/presentation/providers/product_provider.dart';
import 'package:randil_grocery_pos/presentation/providers/wastage_provider.dart';
import 'package:randil_grocery_pos/presentation/screens/inventory/wastage_management_screen.dart';
import 'package:randil_grocery_pos/presentation/theme/app_theme.dart';

/// Diagnostic: loads a COPY of the client's live database and checks that the
/// wastage screen renders the stored wastage rows.
void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('live wastage rows render on the wastage screen',
      (tester) async {
    final path = Platform.environment['WAS_REPRO_DB'];
    expect(path, isNotNull, reason: 'set WAS_REPRO_DB to the copied db path');

    BackupService.transactionNotificationsEnabled = false;
    final db = await databaseFactoryFfi.openDatabase(path!,
        options: OpenDatabaseOptions(version: 1));
    await DatabaseService().debugUseDatabase(db);

    final wastage = WastageProvider();
    await wastage.loadWastages();
    // ignore: avoid_print
    print('WAS_REPRO count=${wastage.wastages.length}');
    for (final w in wastage.wastages) {
      // ignore: avoid_print
      print('WAS_REPRO row -> ${w.productName} | ${w.reason} | '
          '${w.wastageDate} | ${w.createdAt}');
    }

    tester.view.physicalSize = const Size(1366, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(ThemeData.light()),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: wastage),
            ChangeNotifierProvider(create: (_) => ProductProvider()),
            ChangeNotifierProvider(create: (_) => BatchProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: const Scaffold(body: WastageManagementScreen()),
        ),
      ),
    );

    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }

    final exception = tester.takeException();
    // ignore: avoid_print
    print('WAS_REPRO exception=$exception');
    for (final w in wastage.wastages) {
      // ignore: avoid_print
      print('WAS_REPRO visible(${w.productName})='
          '${find.textContaining(w.productName).evaluate().isNotEmpty}');
    }
    // ignore: avoid_print
    print('WAS_REPRO empty-state='
        '${find.text('No Wastage Recorded').evaluate().isNotEmpty}');
    expect(exception, isNull, reason: 'the wastage screen must not throw');
  }, skip: Platform.environment['WAS_REPRO_DB'] == null);
}
