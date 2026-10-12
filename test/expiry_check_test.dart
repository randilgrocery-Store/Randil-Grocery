import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/models/product_batch.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Expiry queries backing the Expiry screen, the POS "Exp: X days" badge and
/// the FIFO picker, exercised against a real (in-memory) SQLite database using
/// the exact SQL shipped in [DatabaseService].
///
/// Two things matter:
///  * the same product received on several dates has several batches with
///    different expiry dates — normal, and every query must surface the lots
///    separately instead of flattening them into one product-level date;
///  * expired stock must never be picked for sale.
Future<Database> openExpiryTestDb() async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      // A fresh in-memory database per open; without this, tests in the same
      // isolate silently share one `:memory:` connection.
      singleInstance: false,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE NOT NULL,
            categoryId TEXT NOT NULL,
            buyingPrice REAL NOT NULL,
            sellingPrice REAL NOT NULL,
            quantity REAL NOT NULL,
            expiryDate TEXT,
            supplierId TEXT,
            reorderLevel INTEGER,
            imagePath TEXT,
            soldByWeight INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE product_batches (
            id TEXT PRIMARY KEY,
            productId TEXT NOT NULL,
            batchNumber TEXT NOT NULL,
            price REAL NOT NULL,
            sellingPrice REAL NOT NULL DEFAULT 0,
            expiryDate TEXT,
            quantity REAL NOT NULL,
            initialQuantity REAL NOT NULL DEFAULT 0,
            receivedDate TEXT NOT NULL,
            supplierId TEXT NOT NULL,
            notes TEXT,
            createdAt TEXT NOT NULL,
            UNIQUE(productId, batchNumber)
          )
        ''');
      },
    ),
  );
}

String isoDaysFromNow(int days) =>
    DateTime.now().add(Duration(days: days)).toIso8601String();

Future<void> insertProduct(Database db, String id, String name, String code) {
  return db.insert('products', {
    'id': id,
    'name': name,
    'barcode': code,
    'categoryId': 'cat',
    'buyingPrice': 1.0,
    'sellingPrice': 2.0,
    'quantity': 10,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
  });
}

Future<void> insertBatch(
  Database db, {
  required String id,
  required String productId,
  required String number,
  String? expiry,
  required double qty,
}) {
  return db.insert('product_batches', {
    'id': id,
    'productId': productId,
    'batchNumber': number,
    'price': 1.0,
    'sellingPrice': 2.0,
    'expiryDate': expiry,
    'quantity': qty,
    'initialQuantity': 10,
    'receivedDate': '2026-09-01T00:00:00.000Z',
    'supplierId': 'sup',
    'notes': '',
    'createdAt': '2026-09-01T00:00:00.000Z',
  });
}

/// Mirrors DatabaseService.getExpiryOverview.
Future<List<(ProductBatch, String)>> overview(Database db) async {
  final rows = await db.rawQuery('''
    SELECT pb.*, p.name AS productName
    FROM product_batches pb
    INNER JOIN products p ON p.id = pb.productId
    WHERE pb.expiryDate IS NOT NULL
    ORDER BY pb.expiryDate ASC
  ''');
  return [
    for (final row in rows)
      (ProductBatch.fromMap(row), (row['productName'] as String?) ?? ''),
  ];
}

/// Mirrors DatabaseService.getBatchExpirySignals (positional record:
/// (soonest future expiry, newest expiry)).
Future<Map<String, (DateTime?, DateTime?)>> expirySignals(
    Database db) async {
  final rows = await db.rawQuery('''
    SELECT productId,
           MIN(CASE WHEN expiryDate > ? THEN expiryDate END) AS next,
           MAX(expiryDate) AS latest
    FROM product_batches
    WHERE expiryDate IS NOT NULL AND quantity > 0
    GROUP BY productId
  ''', [DateTime.now().toIso8601String()]);
  return {
    for (final row in rows)
      row['productId'] as String: (
        row['next'] == null ? null : DateTime.parse(row['next'] as String),
        row['latest'] == null
            ? null
            : DateTime.parse(row['latest'] as String),
      ),
  };
}

/// Mirrors the expiry rule now used by DatabaseService._fifoBatches: expired
/// lots are never offered for sale; undated lots remain sellable.
Future<List<String>> fifoPickableIds(Database db, String productId) async {
  final rows = await db.query(
    'product_batches',
    columns: ['id'],
    where:
        'productId = ? AND quantity > 0 AND (expiryDate IS NULL OR expiryDate > ?)',
    whereArgs: [productId, DateTime.now().toIso8601String()],
  );
  return rows.map((r) => r['id'] as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overview lists every dated batch separately, soonest first, with name',
      () async {
    final db = await openExpiryTestDb();
    await insertProduct(db, 'p-banana', 'Banana', '10001');
    await insertProduct(db, 'p-yogurt', 'Yogurt', '10002');
    await insertBatch(db,
        id: 'b1', productId: 'p-banana', number: 'G1', expiry: '2026-10-25T00:00:00.000Z', qty: 4);
    await insertBatch(db,
        id: 'b2', productId: 'p-banana', number: 'G2', expiry: '2026-11-02T00:00:00.000Z', qty: 6);
    await insertBatch(db,
        id: 'b3', productId: 'p-yogurt', number: 'G3', expiry: null, qty: 5);
    await insertBatch(db,
        id: 'b4', productId: 'p-yogurt', number: 'G4', expiry: '2026-10-20T00:00:00.000Z', qty: 0);

    final rows = await overview(db);

    expect(rows.length, 3); // undated lot excluded
    expect(rows.map((r) => r.$1.id).toList(), ['b4', 'b1', 'b2']);
    expect(rows[0].$2, 'Yogurt');
    expect(rows[1].$2, 'Banana');
    expect(rows[2].$2, 'Banana');
    expect(rows[2].$1.quantity, 6);
  });

  test(
      'expiry signals: next = soonest future lot, latest = newest lot; a '
      'zero-quantity lot is ignored', () async {
    final db = await openExpiryTestDb();
    await insertProduct(db, 'p-mix', 'Mixed', '20001');
    await insertProduct(db, 'p-dead', 'AllExpired', '20002');
    await insertProduct(db, 'p-empty', 'Empty', '20003');

    // Mixed: one expired lot + one future lot -> not fully expired.
    await insertBatch(db,
        id: 'm1', productId: 'p-mix', number: 'M1', expiry: isoDaysFromNow(-5), qty: 3);
    await insertBatch(db,
        id: 'm2', productId: 'p-mix', number: 'M2', expiry: isoDaysFromNow(20), qty: 4);
    // Only an expired lot -> fully expired (latest in the past, next null).
    await insertBatch(db,
        id: 'd1', productId: 'p-dead', number: 'D1', expiry: isoDaysFromNow(-2), qty: 5);
    // Dated but no stock left -> ignored entirely.
    await insertBatch(db,
        id: 'e1', productId: 'p-empty', number: 'E1', expiry: isoDaysFromNow(3), qty: 0);

    final signals = await expirySignals(db);

    final mix = signals['p-mix']!;
    expect(mix.$2!.isAfter(DateTime.now()), isTrue); // latest still future
    expect(mix.$1, isNotNull); // has a future lot to sell
    expect(mix.$1!.isAfter(DateTime.now()), isTrue);

    final dead = signals['p-dead']!;
    expect(dead.$2!.isBefore(DateTime.now()), isTrue); // latest already past
    expect(dead.$1, isNull); // nothing future left

    expect(signals.containsKey('p-empty'), isFalse);
  });

  test('FIFO picker excludes expired lots and keeps undated ones', () async {
    final db = await openExpiryTestDb();
    await insertProduct(db, 'p', 'Item', '30001');
    await insertBatch(db,
        id: 'expired', productId: 'p', number: 'X1', expiry: isoDaysFromNow(-1), qty: 9);
    await insertBatch(db,
        id: 'fresh', productId: 'p', number: 'X2', expiry: isoDaysFromNow(10), qty: 9);
    await insertBatch(db,
        id: 'undated', productId: 'p', number: 'X3', expiry: null, qty: 9);
    await insertBatch(db,
        id: 'emptyFresh', productId: 'p', number: 'X4', expiry: isoDaysFromNow(10), qty: 0);

    final pickable = await fifoPickableIds(db, 'p');

    expect(pickable, contains('fresh'));
    expect(pickable, contains('undated'));
    expect(pickable, isNot(contains('expired')));
    expect(pickable, isNot(contains('emptyFresh')));
  });
}
