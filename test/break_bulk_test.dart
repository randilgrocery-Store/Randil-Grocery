import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/product.dart';
import 'package:randil_grocery_pos/data/models/product_batch.dart';
import 'package:randil_grocery_pos/data/models/sale.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers break-bulk selling: a product whose only barcode is on the box, sold
/// both whole and as loose single pieces. Stock stays in boxes, so a loose line
/// must take only `quantity / piecesPerBox` of a box.
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

  Product boxProduct({double quantity = 3}) => Product(
        id: 'cig',
        name: 'Cigarettes',
        barcode: 'BOX-1',
        categoryId: 'cat1',
        buyingPrice: 80, // per box
        sellingPrice: 100, // per box
        quantity: quantity,
        piecesPerBox: 10,
        singlePrice: 12, // per stick
      );

  Future<void> seed({double quantity = 3}) async {
    await db.insert('products', boxProduct(quantity: quantity).toMap());
    await DatabaseService().insertProductBatch(
      ProductBatch(
        productId: 'cig',
        batchNumber: 'B1',
        price: 80, // cost per box
        sellingPrice: 100, // per box
        quantity: quantity,
        supplierId: 's1',
        receivedDate: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    );
  }

  Future<double> productQty() async {
    final row =
        (await db.query('products', where: 'id = ?', whereArgs: ['cig'])).first;
    return (row['quantity'] as num).toDouble();
  }

  Future<double> batchQty() async {
    final row = (await db.query('product_batches')).first;
    return (row['quantity'] as num).toDouble();
  }

  Future<void> sell(List<CartItem> lines) async {
    final sale = Sale(
      cashierId: 'c1',
      cashierName: 'Cashier',
      items: const [],
      subtotal: 0,
      totalDiscount: 0,
      totalAmount: 0,
      amountReceived: 0,
      balance: 0,
    );
    await DatabaseService().completeSale(sale, lines);
  }

  test('new columns round-trip through the model', () {
    final p = boxProduct();
    expect(p.isBreakBulk, isTrue);
    expect(p.loosePrice, 12, reason: 'uses the explicit single price');
    final back = Product.fromMap(p.toMap());
    expect(back.piecesPerBox, 10);
    expect(back.singlePrice, 12);
    expect(back.isBreakBulk, isTrue);
  });

  test('an ordinary product stays a single unit', () {
    final p = Product(
      id: 'x',
      name: 'Soap',
      barcode: 'S1',
      categoryId: 'cat1',
      buyingPrice: 50,
      sellingPrice: 60,
      quantity: 5,
    );
    expect(p.isBreakBulk, isFalse);
    expect(p.loosePrice, 60);
  });

  test('stockLabel shows boxes plus loose pieces', () {
    final p = boxProduct();
    expect(p.stockLabel(3), '3 boxes');
    expect(p.stockLabel(1), '1 box');
    expect(p.stockLabel(2.7), '2 boxes + 7 pieces');
    expect(p.stockLabel(0.4), '4 pieces');
  });

  test('selling a whole box deducts one box from stock and the batch',
      () async {
    await seed(quantity: 3);
    await sell([
      CartItem(
        id: 'cig',
        product: boxProduct(),
        quantity: 1,
        loose: false,
        piecesPerBox: 10,
      ),
    ]);
    expect(await productQty(), 2);
    expect(await batchQty(), 2);
  });

  test('selling loose pieces deducts only a fraction of a box', () async {
    await seed(quantity: 3);
    await sell([
      CartItem(
        id: 'cig#loose',
        product: boxProduct(),
        quantity: 3, // three single sticks
        loose: true,
        piecesPerBox: 10,
      ),
    ]);
    expect(await productQty(), closeTo(2.7, 1e-9));
    expect(await batchQty(), closeTo(2.7, 1e-9));
  });

  test('a whole box and loose pieces on the same bill deduct correctly',
      () async {
    await seed(quantity: 3);
    await sell([
      CartItem(
        id: 'cig',
        product: boxProduct(),
        quantity: 1,
        loose: false,
        piecesPerBox: 10,
      ),
      CartItem(
        id: 'cig#loose',
        product: boxProduct(),
        quantity: 5, // five single sticks
        loose: true,
        piecesPerBox: 10,
      ),
    ]);
    expect(await productQty(), closeTo(1.5, 1e-9));
    expect(await batchQty(), closeTo(1.5, 1e-9));
  });

  test('SaleItem keeps the loose flag so the server PC deducts the same stock',
      () async {
    final original = SaleItem(
      productId: 'cig',
      productName: 'Cigarettes',
      price: 12,
      quantity: 4,
      loose: true,
      piecesPerBox: 10,
    );
    final restored = SaleItem.fromMap(original.toMap());
    expect(restored.loose, isTrue);
    expect(restored.piecesPerBox, 10);
    expect(restored.stockQuantity, closeTo(0.4, 1e-9));

    // An ordinary line still deducts its own quantity.
    final normal = SaleItem(
      productId: 'soap',
      productName: 'Soap',
      price: 60,
      quantity: 2,
    );
    expect(normal.stockQuantity, 2);
  });

  test(
      'wastage of loose pieces deducts a fraction of a box, restores on delete',
      () async {
    await seed(quantity: 3);
    final batchId =
        ((await db.query('product_batches')).first)['id'] as String;

    // Three sticks of a 10-per-box product are damaged → 0.3 boxes.
    final w = await DatabaseService().recordWastage(
      productId: 'cig',
      productName: 'Cigarettes',
      quantity: 3 / 10,
      reason: 'Damaged',
      batchId: batchId,
      batchNumber: 'B1',
    );
    expect(w, isNotNull);
    expect(await productQty(), closeTo(2.7, 1e-9));
    expect(await batchQty(), closeTo(2.7, 1e-9));
    expect(w!.lossValue, closeTo(80 * 0.3, 1e-9));
    // Reads back as loose pieces, never as a 0.3 "units" figure.
    expect(boxProduct().stockLabel(w.quantity), '3 pieces');

    // Damaged more later: now 5 sticks → another 0.2 of a box gone.
    final updated = await DatabaseService().updateWastage(
      id: w.id,
      quantity: 5 / 10,
    );
    expect(updated, isNotNull);
    expect(await productQty(), closeTo(2.5, 1e-9));
    expect(await batchQty(), closeTo(2.5, 1e-9));

    // Removing the record restores the fraction taken.
    expect(await DatabaseService().deleteWastage(w.id), isTrue);
    expect(await productQty(), closeTo(3.0, 1e-9));
    expect(await batchQty(), closeTo(3.0, 1e-9));
  });
}
