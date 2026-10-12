import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/product_batch.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/presentation/providers/wastage_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the v1.1.12 fixes: wastage edit/delete, and the LAN-mirror clocks
/// for edited batches (expiry corrections) and received purchase orders.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
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

  test('editing a wastage moves stock by the difference and re-syncs',
      () async {
    await insertProduct('p1', 10);
    final created = await DatabaseService().recordWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 2,
      reason: 'Expired',
    );
    expect(created, isNotNull);

    var product =
        (await db.query('products', where: 'id = ?', whereArgs: ['p1'])).first;
    expect((product['quantity'] as num).toDouble(), 8);

    final updated = await DatabaseService().updateWastage(
      id: created!.id,
      quantity: 6,
      reason: 'Damaged',
      notes: 'spilled pallet',
    );
    expect(updated, isNotNull);
    expect(updated!.quantity, 6);
    expect(updated.reason, 'Damaged');
    expect(updated.lossValue, closeTo(60, 0.001)); // 10 cost × 6 units

    product =
        (await db.query('products', where: 'id = ?', whereArgs: ['p1'])).first;
    expect((product['quantity'] as num).toDouble(), 4);

    // The mirror ships the edited row: its clock moved to the edit time.
    final rows = await DatabaseService()
        .mirrorRowsSince(DateTime.now().subtract(const Duration(minutes: 1)));
    final wastageRows = (rows['wastages'] as List)
        .cast<Map<String, dynamic>>();
    expect(wastageRows, hasLength(1));
    expect(wastageRows.first['quantity'], 6);
    expect(await DatabaseService().financialRevision(), isNotEmpty);
  });

  test('deleting a wastage restores the units to stock', () async {
    await insertProduct('p1', 10);
    final created = await DatabaseService().recordWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 3,
      reason: 'Damaged',
    );
    expect(created, isNotNull);

    final ok = await DatabaseService().deleteWastage(created!.id);
    expect(ok, isTrue);
    expect(await DatabaseService().getAllWastages(), isEmpty);

    final product =
        (await db.query('products', where: 'id = ?', whereArgs: ['p1'])).first;
    expect((product['quantity'] as num).toDouble(), 10);
  });

  test('provider deleteWastage refreshes the visible list', () async {
    await insertProduct('p1', 10);
    final provider = WastageProvider();
    final created = await provider.addWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 1,
      reason: 'Expired',
    );
    expect(provider.wastages, hasLength(1));

    await provider.deleteWastage(created!.id);
    expect(provider.wastages, isEmpty);
  });

  test('an in-place batch expiry edit travels through the mirror', () async {
    await insertProduct('p1', 10);
    final batch = ProductBatch(
      productId: 'p1',
      batchNumber: 'B-1',
      price: 10.0,
      quantity: 5,
      supplierId: 's1',
      expiryDate: DateTime(2027, 1, 1),
      receivedDate: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );
    await DatabaseService().insertProductBatch(batch);

    // Receiving terminal gets the batch row.
    final before = await DatabaseService()
        .mirrorRowsSince(DateTime.now().subtract(const Duration(minutes: 1)));
    expect((before['product_batches'] as List), hasLength(1));

    // Correct the expiry date later on this PC.
    await DatabaseService().updateProductBatch(batch.copyWith(
      expiryDate: DateTime(2026, 11, 1),
      updatedAt: DateTime.now(),
    ));

    // The edit bumped the updatedAt clock, so the row is offered on the next
    // push and the revision fingerprint moves.
    final after = await DatabaseService()
        .mirrorRowsSince(DateTime.now().subtract(const Duration(minutes: 1)));
    final rows = (after['product_batches'] as List)
        .cast<Map<String, dynamic>>();
    expect(rows, hasLength(1));
    expect(rows.first['expiryDate'], startsWith('2026-11-01'));
  });

  test('applyMirror refreshes batch metadata but keeps local quantity',
      () async {
    await insertProduct('p1', 10);
    final oldStamp = DateTime(2026, 10, 1).toIso8601String();
    await DatabaseService().insertProductBatch(
      ProductBatch(
        productId: 'p1',
        batchNumber: 'B-2',
        price: 10.0,
        quantity: 7,
        supplierId: 's1',
        expiryDate: DateTime(2027, 1, 1),
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    );

    final freshStamp = DateTime.now().toIso8601String();
    await DatabaseService().applyMirror({
      'product_batches': [
        {
          'id': (await db
                  .query('product_batches', limit: 1))
              .first['id'],
          'productId': 'p1',
          'batchNumber': 'B-2',
          'price': 12.0,
          'sellingPrice': 22.0,
          'expiryDate': '2026-11-01T00:00:00.000',
          'supplierId': 's1',
          'notes': 'Expiry corrected on admin PC',
          'receivedDate': '2026-10-01T00:00:00.000',
          'createdAt': oldStamp,
          'updatedAt': freshStamp,
          'quantity': 3, // the other PC's FIFO remnant — must be ignored
        }
      ],
    });

    final maps = await db.query('product_batches');
    expect(maps, hasLength(1));
    expect((maps.first['quantity'] as num).toDouble(), 7,
        reason: 'local quantity is never clobbered by a mirrored value');
    expect(maps.first['expiryDate'], startsWith('2026-11-01'));
    expect(maps.first['updatedAt'], freshStamp,
        reason: 'the later edit stamp is kept');
    expect(maps.first['notes'], 'Expiry corrected on admin PC');
  });

  test('a purchase order received the same day still travels (midnight date)',
      () async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    // Legacy row: received at midnight (what the date picker returns) but
    // entered on this machine "now" — before the fix its COALESCE clock sat at
    // midnight, which sorts before the push watermark and never travels.
    await db.insert('purchase_orders', {
      'id': 'po1',
      'orderNumber': 'PO-TEST-1',
      'supplierId': 's1',
      'supplierName': 'Supplier 1',
      'items': '[]',
      'subtotal': 0,
      'total': 0,
      'status': 'Received',
      'notes': '',
      'orderDate': midnight.toIso8601String(),
      'receivedDate': midnight.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });

    final rows = await DatabaseService()
        .mirrorRowsSince(DateTime.now().subtract(const Duration(minutes: 1)));
    final pos = (rows['purchase_orders'] as List);
    expect(pos, hasLength(1));
    expect((pos.first as Map)['id'], 'po1');
    expect(await DatabaseService().financialRevision(), isNotEmpty);
  });
}