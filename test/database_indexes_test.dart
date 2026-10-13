import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The report/history screens and the 2-PC mirror scan large tables by a date
/// column; these indexes keep those scans fast as the shop's data grows all
/// year. Without them every report is a full table scan. This guards against a
/// future edit dropping the index list or misspelling a column name.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    await DatabaseService().debugUseDatabase(db);
  });

  tearDown(() async {
    DatabaseService().debugResetDatabase();
    await db.close();
  });

  test('the hot-path indexes are created', () async {
    final rows =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
    final names = rows.map((r) => r['name'] as String).toSet();

    // A representative slice covering every table the reports and mirror scan.
    for (final expected in const [
      'idx_sales_sale_date',
      'idx_stock_history_product',
      'idx_products_category',
      'idx_batches_product',
      'idx_batches_expiry',
      'idx_refunds_status',
      'idx_expenses_date',
      'idx_wastages_created',
      'idx_grn_received',
      'idx_po_order_date',
      'idx_reload_created',
      'idx_productions_produced',
      'idx_bag_usage_created',
      'idx_customers_updated',
      'idx_suppliers_updated',
    ]) {
      expect(names, contains(expected), reason: 'missing index $expected');
    }
  });

  test('index creation is idempotent across re-opens', () async {
    // debugUseDatabase runs _createTables again; the CREATE INDEX IF NOT EXISTS
    // statements must not throw or duplicate an index.
    await DatabaseService().debugUseDatabase(db);

    final rows = await db.rawQuery(
      "SELECT COUNT(*) c FROM sqlite_master "
      "WHERE type = 'index' AND name = 'idx_sales_sale_date'",
    );
    expect(rows.first['c'], 1);
  });
}
