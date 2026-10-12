import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end tests for the LAN data mirror — the engine that keeps the admin
/// PC and every cashier terminal showing the same bills, expenses, wastage,
/// reload cards, refunds, repacks, goods received, purchase orders, supplier
/// payments and stock.
///
/// These run against a real (in-memory) SQLite database using the *real* schema
/// created by [DatabaseService], so a schema drift breaks the test instead of
/// silently breaking the shop.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    // Never let a test write real snapshots or start cloud timers.
    BackupService.transactionNotificationsEnabled = false;
    await DatabaseService().debugUseDatabase(db);
  });

  tearDown(() async {
    DatabaseService().debugResetDatabase();
    BackupService.transactionNotificationsEnabled = true;
    await db.close();
  });

  Future<void> insertProduct(String id, double quantity) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('products', {
      'id': id,
      'name': 'Product $id',
      'barcode': 'BC-$id',
      'categoryId': 'cat1',
      'buyingPrice': 10.0,
      'sellingPrice': 20.0,
      'quantity': quantity,
      'soldByWeight': 0,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> insertExpense(String id, double amount,
      {DateTime? at}) async {
    await db.insert('expenses', {
      'id': id,
      'description': 'Expense $id',
      'category': 'Misc',
      'amount': amount,
      'expenseDate': (at ?? DateTime.now()).toIso8601String(),
      'notes': '',
      'recordedBy': 'admin',
    });
  }

  Future<void> insertSale(String id, double total, {DateTime? at}) async {
    await db.insert('sales', {
      'id': id,
      'invoiceNumber': 'INV-$id',
      'cashierId': 'u1',
      'cashierName': 'Cashier',
      // The schema stores this as a JSON *string*; the mirror must ship it
      // verbatim so the other terminal can insert it without re-encoding.
      'items': jsonEncode([
        {
          'id': 'li1',
          'productId': 'p1',
          'productName': 'Milk',
          'price': 100.0,
          'quantity': 1.0,
          'discount': 0.0,
          'costPrice': 50.0,
          'batchNumber': '',
          'barcode': '',
          'allocations': <Object>[],
        }
      ]),
      'subtotal': total,
      'totalDiscount': 0.0,
      'totalAmount': total,
      'amountReceived': total,
      'balance': 0.0,
      'paymentMethod': 'Cash',
      'saleDate': (at ?? DateTime.now()).toIso8601String(),
      'notes': '',
      'customerName': '',
      'customerPhone': '',
      'cashAmount': total,
      'cardAmount': 0.0,
    });
  }

  group('mirrorRowsSince', () {
    test('ships money rows and keeps sales.items as a JSON string', () async {
      await insertSale('s1', 150.0);
      await insertExpense('e1', 25.0);

      final rows = await DatabaseService().mirrorRowsSince(null);

      expect((rows['sales'] as List), hasLength(1));
      expect((rows['expenses'] as List), hasLength(1));
      final sale = (rows['sales'] as List).first as Map;
      expect(sale['items'], isA<String>());
      final decoded = jsonDecode(sale['items'] as String) as List;
      expect(decoded, hasLength(1));
      expect((decoded.first as Map)['productName'], 'Milk');
    });

    test('a new terminal bootstraps full non-sale history, sales last 7 days',
        () async {
      // Old bill (outside the 7-day window) and a fresh one.
      await insertSale('old', 10.0,
          at: DateTime.now().subtract(const Duration(days: 10)));
      await insertSale('new', 20.0);
      // An old expense is still history, so it must come across in full.
      await insertExpense('e-old', 5.0,
          at: DateTime.now().subtract(const Duration(days: 400)));

      final rows = await DatabaseService().mirrorRowsSince(null);

      final saleIds = (rows['sales'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(saleIds, contains('new'));
      expect(saleIds, isNot(contains('old')),
          reason: 'sales bootstrap is capped to the last 7 days');
      expect((rows['expenses'] as List), hasLength(1));
    });

    test('ships only rows at or after the watermark when since is set',
        () async {
      await insertExpense('old', 5.0,
          at: DateTime.now().subtract(const Duration(days: 2)));
      await insertExpense('recent', 7.0);

      final since = DateTime.now().subtract(const Duration(hours: 1));
      final rows = await DatabaseService().mirrorRowsSince(since);
      final ids =
          (rows['expenses'] as List).map((e) => (e as Map)['id']).toSet();

      expect(ids, contains('recent'));
      expect(ids, isNot(contains('old')));
    });

    test('ships batch lots so an expiry typed on one PC reaches the other',
        () async {
      await insertProduct('p1', 10);
      final now = DateTime.now().toIso8601String();
      await db.insert('product_batches', {
        'id': 'b1',
        'productId': 'p1',
        'batchNumber': 'B-001',
        'price': 10.0,
        'sellingPrice': 20.0,
        'expiryDate': '2026-12-01T00:00:00.000',
        'quantity': 10.0,
        'initialQuantity': 10.0,
        'receivedDate': now,
        'supplierId': 'sup1',
        'notes': '',
        'createdAt': now,
      });

      final rows = await DatabaseService().mirrorRowsSince(null);

      expect(rows.containsKey('product_batches'), isTrue,
          reason: 'the mirror payload must carry the batch table');
      final batches = rows['product_batches'] as List;
      expect(batches, hasLength(1));
      expect((batches.single as Map)['expiryDate'], '2026-12-01T00:00:00.000');
    });
  });

  group('financialRevision (the pull trigger)', () {
    test('adding a batch moves the revision so the other PC pulls it',
        () async {
      await insertProduct('p1', 10);
      final before = await DatabaseService().financialRevision();

      final now = DateTime.now().toIso8601String();
      await db.insert('product_batches', {
        'id': 'b1',
        'productId': 'p1',
        'batchNumber': 'B-001',
        'price': 10.0,
        'sellingPrice': 20.0,
        'expiryDate': '2026-12-01T00:00:00.000',
        'quantity': 10.0,
        'initialQuantity': 10.0,
        'receivedDate': now,
        'supplierId': 'sup1',
        'notes': '',
        'createdAt': now,
      });

      final after = await DatabaseService().financialRevision();

      expect(after, isNot(before),
          reason: 'a new expiry date must make the terminal poll-and-pull');
    });
  });

  group('applyMirror', () {
    test('inserts rows from the other terminal', () async {
      await DatabaseService().applyMirror({
        'expenses': [
          {
            'id': 'e1',
            'description': 'Water',
            'category': 'Utility',
            'amount': 300.0,
            'expenseDate': DateTime.now().toIso8601String(),
            'notes': '',
            'recordedBy': 'cashier',
          }
        ],
      });

      final rows = await db.query('expenses');
      expect(rows, hasLength(1));
      expect(rows.first['amount'], 300.0);
    });

    test('replaces an existing row by primary key instead of duplicating it',
        () async {
      await insertExpense('e1', 100.0);

      await DatabaseService().applyMirror({
        'expenses': [
          {
            'id': 'e1',
            'description': 'Corrected',
            'category': 'Misc',
            'amount': 250.0,
            'expenseDate': DateTime.now().toIso8601String(),
            'notes': '',
            'recordedBy': 'admin',
          }
        ],
      });

      final rows = await db.query('expenses');
      expect(rows, hasLength(1));
      expect(rows.first['amount'], 250.0);
      expect(rows.first['description'], 'Corrected');
    });

    test('one malformed row does not block the others', () async {
      final applied = await DatabaseService().applyMirror({
        'expenses': [
          {'id': 'bad', 'amount': 'not-a-number'},
          {
            'id': 'good',
            'description': 'Good',
            'category': 'Misc',
            'amount': 12.5,
            'expenseDate': DateTime.now().toIso8601String(),
            'notes': '',
            'recordedBy': 'admin',
          },
        ],
      });

      expect(applied, 1);
      final rows = await db.query('expenses');
      expect(rows.single['id'], 'good');
    });

    test('a batch lot keeps its local quantity but takes the remote expiry',
        () async {
      final now = DateTime.now().toIso8601String();
      // Local terminal already sold 7 of this lot (10 received, 3 left).
      await db.insert('product_batches', {
        'id': 'b1',
        'productId': 'p1',
        'batchNumber': 'B-001',
        'price': 10.0,
        'sellingPrice': 20.0,
        'expiryDate': '2026-12-01T00:00:00.000',
        'quantity': 3.0,
        'initialQuantity': 10.0,
        'receivedDate': now,
        'supplierId': 'sup1',
        'notes': '',
        'createdAt': now,
      });

      await DatabaseService().applyMirror({
        'product_batches': [
          {
            'id': 'b1',
            'productId': 'p1',
            'batchNumber': 'B-001',
            'price': 10.0,
            'sellingPrice': 20.0,
            // The other terminal corrected the expiry date on this lot.
            'expiryDate': '2026-11-15T00:00:00.000',
            // ... and reports 10 left. That figure must NOT win here.
            'quantity': 10.0,
            'initialQuantity': 10.0,
            'receivedDate': now,
            'supplierId': 'sup1',
            'notes': 'checked',
            'createdAt': now,
          }
        ],
      });

      final row = (await db.query('product_batches')).single;
      expect(row['quantity'], 3.0,
          reason: 'local remaining stock must be preserved');
      expect(row['initialQuantity'], 10.0);
      expect(row['expiryDate'], '2026-11-15T00:00:00.000',
          reason: 'the remote expiry correction must land');
      expect(row['notes'], 'checked');
    });

    test('a batch lot unknown here is inserted in full', () async {
      final now = DateTime.now().toIso8601String();
      await DatabaseService().applyMirror({
        'product_batches': [
          {
            'id': 'b2',
            'productId': 'p1',
            'batchNumber': 'B-002',
            'price': 5.0,
            'sellingPrice': 9.0,
            'expiryDate': '2027-01-01T00:00:00.000',
            'quantity': 7.0,
            'initialQuantity': 7.0,
            'receivedDate': now,
            'supplierId': 'sup1',
            'notes': '',
            'createdAt': now,
          }
        ],
      });

      final row = (await db.query('product_batches')).single;
      expect(row['id'], 'b2');
      expect(row['quantity'], 7.0);
      expect(row['expiryDate'], '2027-01-01T00:00:00.000');
    });
  });

  group('applyStockDeltas', () {
    test('applies a delta instead of an absolute quantity', () async {
      await insertProduct('p1', 10);

      await DatabaseService()
          .applyStockDeltas([{'id': 'p1', 'delta': -3}]);

      final rows = await db.query('products', where: 'id = ?', whereArgs: ['p1']);
      expect(rows.single['quantity'], 7.0);
    });

    test('never drives stock below zero', () async {
      await insertProduct('p1', 2);

      await DatabaseService()
          .applyStockDeltas([{'id': 'p1', 'delta': -100}]);

      final rows = await db.query('products', where: 'id = ?', whereArgs: ['p1']);
      expect(rows.single['quantity'], 0.0);
    });

    test('ignores an unknown product and a zero delta', () async {
      await insertProduct('p1', 5);

      final applied = await DatabaseService().applyStockDeltas([
        {'id': 'missing', 'delta': -1},
        {'id': 'p1', 'delta': 0},
        {'id': 'p1', 'delta': 2},
      ]);

      expect(applied, 1);
      final rows = await db.query('products', where: 'id = ?', whereArgs: ['p1']);
      expect(rows.single['quantity'], 7.0);
    });
  });

  group('reports reset', () {
    test('clears money and reload ledger but keeps products, images and stock',
        () async {
      await insertProduct('p1', 42);
      await db.update('products', {'imagePath': '/img/milk.png'},
          where: 'id = ?', whereArgs: ['p1']);
      await insertSale('s1', 99.0);
      await insertExpense('e1', 10.0);
      await db.insert('wastages', {
        'id': 'w1',
        'productId': 'p1',
        'productName': 'Milk',
        'quantity': 1.0,
        'reason': 'Expired',
        'lossValue': 5.0,
        'batchId': '',
        'batchNumber': '',
        'notes': '',
        'recordedBy': 'admin',
        'wastageDate': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });
      final now = DateTime.now().toIso8601String();
      // The reload value ledger is cleared by the reset ...
      await db.insert('reload_cards', {
        'id': 'rc1',
        'value': 100.0,
        'cost': 95.0,
        'status': 'bought',
        'createdAt': now,
        'usedAt': '',
      });
      // ... but the physical stock layer must survive untouched.
      await db.insert('product_batches', {
        'id': 'b1',
        'productId': 'p1',
        'batchNumber': 'B-001',
        'price': 10.0,
        'sellingPrice': 20.0,
        'quantity': 42.0,
        'initialQuantity': 42.0,
        'receivedDate': now,
        'supplierId': 'sup1',
        'createdAt': now,
      });
      await db.insert('stock_history', {
        'productId': 'p1',
        'productName': 'Milk',
        'quantityChanged': 42.0,
        'reason': 'Opening stock',
        'createdAt': now,
      });

      final cleared = await DatabaseService().clearFinancialHistory();

      expect(cleared['sales'], 1);
      expect(cleared['expenses'], 1);
      expect(cleared['wastages'], 1);
      expect(cleared['reload_cards'], 1);

      expect(await db.query('sales'), isEmpty);
      expect(await db.query('expenses'), isEmpty);
      expect(await db.query('wastages'), isEmpty);
      expect(await db.query('reload_cards'), isEmpty);

      // Products, images, stock quantity, batches and the stock ledger survive.
      final product =
          (await db.query('products', where: 'id = ?', whereArgs: ['p1']))
              .single;
      expect(product['quantity'], 42.0);
      expect(product['imagePath'], '/img/milk.png');
      expect(await db.query('product_batches'), hasLength(1));
      expect(await db.query('stock_history'), hasLength(1));

      expect(await DatabaseService().reportsResetAt(), isNotNull);
    });

    test('the revision carries the reset token so the other PC notices',
        () async {
      final before = await DatabaseService().financialRevision();

      await insertSale('s1', 50.0);
      final afterRow = await DatabaseService().financialRevision();
      expect(afterRow, isNot(before));

      final tokenBefore = await DatabaseService().reportsResetAt();
      expect(tokenBefore, isNull);
      await DatabaseService().clearFinancialHistory();
      final tokenAfter = await DatabaseService().reportsResetAt();
      expect(tokenAfter, isNotNull);
    });
  });
}
