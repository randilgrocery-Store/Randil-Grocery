import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';

/// Diagnostic: exercises the mirror engine against a COPY of the live client
/// database. Not a normal test — prints the results for the field investigation.
void main() {
  setUpAll(sqfliteFfiInit);

  test('mirror engine works on the live database', () async {
    final path = Platform.environment['WAS_LIVE_DB'];
    expect(path, isNotNull, reason: 'set WAS_LIVE_DB to the copied db path');

    BackupService.transactionNotificationsEnabled = false;
    final db = await databaseFactoryFfi.openDatabase(path!,
        options: OpenDatabaseOptions(version: 1));
    await DatabaseService().debugUseDatabase(db);

    final svc = DatabaseService();

    // 1. mirrorRowsSince(null) — the shapes every table pushes.
    final tables = await svc.mirrorRowsSince(null);
    for (final spec in [
      'sales',
      'expenses',
      'wastages',
      'reload_cards',
      'refund_returns',
      'productions',
      'production_components',
      'recipes',
      'recipe_items',
      'goods_received_notes',
      'purchase_orders',
      'supplier_payments',
      'customers',
      'suppliers',
      'product_batches',
    ]) {
      final rows = tables[spec];
      // ignore: avoid_print
      print('PROBE rows[$spec]=${rows is List ? rows.length : 'MISSING'}');
      if (rows is List && rows.isNotEmpty) {
        final sample = rows.first;
        // ignore: avoid_print
        print('PROBE sample[$spec].keys=${sample.keys.join(',')}');
      }
    }

    // 2. financialRevision must compute without throwing (the client compares
    //    this against the server every heartbeat).
    String? revision;
    Object? revError;
    try {
      revision = await svc.financialRevision();
    } catch (e) {
      revError = e;
    }
    // ignore: avoid_print
    print('PROBE financialRevision=$revision');
    // ignore: avoid_print
    print('PROBE financialRevisionError=$revError');

    // 3. applyMirror: a brand-new customer row must land.
    final customerId = 'probe-customer-${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    await svc.applyMirror({
      'customers': [
        {
          'id': customerId,
          'name': 'Probe Customer',
          'phone': '',
          'email': '',
          'address': '',
          'totalSpent': 0.0,
          'totalTransactions': 0,
          'creditBalance': 0.0,
          'loyaltyPoints': 0,
          'createdAt': now,
          'lastPurchaseDate': now,
          'isActive': 1,
          'updatedAt': now,
        }
      ],
      'suppliers': [],
      'product_batches': [],
    });
    final customers = await svc.getAllCustomers();
    // ignore: avoid_print
    print('PROBE customerApplied=${customers.any((c) => c.id == customerId)} '
        'totalCustomers=${customers.length}');

    // 4. applyMirror: an expiry edit on an existing batch must refresh metadata.
    final batchMaps = await db.query('product_batches', limit: 1);
    if (batchMaps.isNotEmpty) {
      final batchId = batchMaps.first['id'];
      await svc.applyMirror({
        'product_batches': [
          {
            'id': batchId,
            'productId': batchMaps.first['productId'],
            'batchNumber': batchMaps.first['batchNumber'],
            'price': batchMaps.first['price'],
            'sellingPrice': batchMaps.first['sellingPrice'],
            'expiryDate': '2027-01-01T00:00:00.000',
            'supplierId': batchMaps.first['supplierId'] ?? '',
            'notes': 'PROBE-EDIT',
            'receivedDate': batchMaps.first['receivedDate'],
            'createdAt': batchMaps.first['createdAt'],
          }
        ],
      });
      final after = await db.query('product_batches',
          columns: ['expiryDate', 'notes'], where: 'id = ?', whereArgs: [batchId]);
      // ignore: avoid_print
      print('PROBE batchEdited=${after.first}');

      // 5. Does the edited batch row travel? Simulate the other PC pulling
      //    rows since "two seconds ago" — the edited batch's clock did not
      //    change, so it must NOT appear (confirms the missing-updatedAt gap).
      final later = await svc.mirrorRowsSince(
          DateTime.now().subtract(const Duration(seconds: 2)));
      final batchRows = later['product_batches'] as List;
      final travelled = batchRows.any((b) => b['id'] == batchId);
      // ignore: avoid_print
      print('PROBE editedBatchTravelled=$travelled');
    }

    // 6. Wastage rows load fine.
    final wastages = await svc.getAllWastages();
    // ignore: avoid_print
    print('PROBE wastages=${wastages.length} '
        '${wastages.map((w) => w.productName).join(' | ')}');
  }, skip: Platform.environment['WAS_LIVE_DB'] == null);
}