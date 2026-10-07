import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Barcode lookup rules used by both the POS scanner and the GRN stock
/// scanner, exercised against a real (in-memory) SQLite database.
///
/// The rule that matters: whatever can be received by scanning must also be
/// sellable by scanning, because the counter and the stock screen run the same
/// lookup.
Future<Database> openTestDb() async {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
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
            quantity INTEGER NOT NULL,
            expiryDate TEXT,
            supplierId TEXT,
            reorderLevel INTEGER,
            imagePath TEXT,
            sellType TEXT NOT NULL DEFAULT 'piece',
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
      },
    ),
  );
}

/// Mirrors DatabaseService.getProductByCode so the matching rules can be
/// verified without booting the whole singleton app stack.
Future<Map<String, Object?>?> lookupByCode(DatabaseExecutor db, String code) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return null;

  final exact = await db.query(
    'products',
    where: 'barcode = ?',
    whereArgs: [trimmed],
    limit: 1,
  );
  if (exact.isNotEmpty) return exact.first;

  final lowered = trimmed.toLowerCase();
  final insensitive = await db.query(
    'products',
    where: 'LOWER(barcode) = ?',
    whereArgs: [lowered],
    limit: 1,
  );
  if (insensitive.isNotEmpty) return insensitive.first;

  final byName = await db.query(
    'products',
    where: 'LOWER(name) = ?',
    whereArgs: [lowered],
    limit: 1,
  );
  if (byName.isNotEmpty) return byName.first;
  return null;
}

Future<void> insertProduct(
  Database db, {
  required String id,
  required String name,
  required String barcode,
  int quantity = 10,
}) async {
  final now = DateTime.now().toIso8601String();
  await db.insert('products', {
    'id': id,
    'name': name,
    'barcode': barcode,
    'categoryId': 'cat1',
    'buyingPrice': 10.0,
    'sellingPrice': 20.0,
    'quantity': quantity,
    'createdAt': now,
    'updatedAt': now,
  });
}

void main() {
  late Database db;

  setUp(() async {
    db = await openTestDb();
  });

  tearDown(() async => db.close());

  group('scanner code lookup', () {
    test('finds a product by its exact barcode', () async {
      await insertProduct(db, id: 'p1', name: 'Milk 1L', barcode: '4801234567890');

      final found = await lookupByCode(db, '4801234567890');

      expect(found, isNotNull);
      expect(found!['name'], 'Milk 1L');
    });

    test('ignores whitespace a scanner or paste may add', () async {
      await insertProduct(db, id: 'p1', name: 'Milk 1L', barcode: '4801234567890');

      final found = await lookupByCode(db, '  4801234567890\n');

      expect(found!['name'], 'Milk 1L');
    });

    test('finds a product when the scanned case differs', () async {
      await insertProduct(db, id: 'p1', name: 'Bread', barcode: 'ABC-123');

      // The GRN screen already matched case-insensitively; the counter did not,
      // so stock received by scanning could not be sold by scanning.
      final lower = await lookupByCode(db, 'abc-123');
      final upper = await lookupByCode(db, 'ABC-123');

      expect(lower!['name'], 'Bread');
      expect(upper!['name'], 'Bread');
    });

    test('falls back to an exact name match', () async {
      await insertProduct(db, id: 'p1', name: 'Sugar 1kg', barcode: '111222333');

      final found = await lookupByCode(db, 'Sugar 1kg');

      expect(found!['name'], 'Sugar 1kg');
    });

    test('name matching ignores case', () async {
      await insertProduct(db, id: 'p1', name: 'Sugar 1kg', barcode: '111222333');

      final found = await lookupByCode(db, 'sugar 1kg');

      expect(found!['name'], 'Sugar 1kg');
    });

    test('returns nothing for an unknown code', () async {
      await insertProduct(db, id: 'p1', name: 'Milk 1L', barcode: '4801234567890');

      final found = await lookupByCode(db, '9999999999999');

      expect(found, isNull);
    });

    test('returns nothing for empty input', () async {
      expect(await lookupByCode(db, ''), isNull);
      expect(await lookupByCode(db, '   '), isNull);
    });

    test('prefers the barcode over a same-named product', () async {
      await insertProduct(db, id: 'p1', name: 'Cola', barcode: '111');
      await insertProduct(db, id: 'p2', name: 'Cola', barcode: '999');

      // The barcode is what was scanned, so that is what must be sold.
      final found = await lookupByCode(db, '111');

      expect(found!['id'], 'p1');
    });
  });

  group('stock added by GRN is sellable by scanning', () {
    test('a product received with mixed-case barcode scans at the counter',
        () async {
      // Received as "abc-123"...
      await insertProduct(db, id: 'p1', name: 'Butter', barcode: 'abc-123');

      // ...and the cashier's scanner sends "ABC-123". This must resolve, or the
      // item cannot be sold even though stock exists.
      final found = await lookupByCode(db, 'ABC-123');

      expect(found, isNotNull);
      expect((found!['quantity'] as int), 10);
    });
  });
}