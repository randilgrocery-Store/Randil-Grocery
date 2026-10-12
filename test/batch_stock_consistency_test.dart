import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/product.dart';
import 'package:randil_grocery_pos/data/models/product_batch.dart';
import 'package:randil_grocery_pos/data/models/sale.dart';

/// Batches are the FIFO spine of the POS, and their quantity is real stock.
/// These tests guard the rule that creating/editing/deleting a batch ALWAYS
/// moves the product's on-hand total by the same amount, so the batch sum and
/// the product count can never disagree (a mismatch would make the shelf and
/// the screen tell different stories).
void main() {
  setUpAll(sqfliteFfiInit);
  late Database conn;
  late DatabaseService db;

  setUp(() async {
    conn = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    db = DatabaseService();
    await db.debugUseDatabase(conn);
  });

  tearDown(() async {
    await conn.close();
  });

  Product makeProduct(String name) => Product(
        name: name,
        barcode: name,
        categoryId: 'cat-1',
        buyingPrice: 50,
        sellingPrice: 80,
        quantity: 0,
      );

  test('creating a batch adds its quantity to the product total', () async {
    await db.insertProduct(makeProduct('Cigarette'));
    final product = (await db.getAllProducts()).first;

    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'B-1',
      price: 50,
      quantity: 20,
      supplierId: '',
    ));

    final reloaded = (await db.getAllProducts()).first;
    expect(reloaded.quantity, 20);
    expect((await db.getBatchesByProductId(product.id)).first.quantity, 20);
  });

  test('editing a batch quantity moves the product total by the difference',
      () async {
    await db.insertProduct(makeProduct('Dhal'));
    final product = (await db.getAllProducts()).first;
    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'B-1',
      price: 200,
      quantity: 10,
      supplierId: '',
    ));

    final batch = (await db.getBatchesByProductId(product.id)).first;
    await db.updateProductBatch(batch.copyWith(quantity: 7));

    final reloaded = (await db.getAllProducts()).first;
    expect(reloaded.quantity, 7);

    await db.updateProductBatch(batch.copyWith(quantity: 12));
    expect((await db.getAllProducts()).first.quantity, 12);
  });

  test('re-entering the same lot number edits it, never double-adds stock',
      () async {
    await db.insertProduct(makeProduct('Sugar'));
    final product = (await db.getAllProducts()).first;

    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'LOT-A',
      price: 150,
      quantity: 10,
      supplierId: '',
    ));
    // Same lot number received again with a different remaining count.
    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'LOT-A',
      price: 150,
      quantity: 4,
      supplierId: '',
    ));

    final productAfter = (await db.getAllProducts()).first;
    final batches = await db.getBatchesByProductId(product.id);
    expect(batches.length, 1);
    expect(batches.first.quantity, 4);
    expect(productAfter.quantity, 4); // 10, not 14 — never double-added
  });

  test('deleting a batch subtracts its remaining stock from the product total',
      () async {
    await db.insertProduct(makeProduct('Flour'));
    final product = (await db.getAllProducts()).first;
    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'B-9',
      price: 90,
      quantity: 8,
      supplierId: '',
    ));
    expect((await db.getAllProducts()).first.quantity, 8);

    await db.deleteProductBatch(
        (await db.getBatchesByProductId(product.id)).first.id);
    expect((await db.getAllProducts()).first.quantity, 0);
  });

  test('a sale consumes batches and product total together (FIFO) so they '
      'never drift apart', () async {
    await db.insertProduct(makeProduct('Rice'));
    final product = (await db.getAllProducts()).first;
    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'OLD',
      price: 90,
      quantity: 5,
      supplierId: '',
    ));
    await db.insertProductBatch(ProductBatch(
      productId: product.id,
      batchNumber: 'NEW',
      price: 110,
      quantity: 3,
      supplierId: '',
    ));
    expect((await db.getAllProducts()).first.quantity, 8);

    // Sell 6 from the oldest batch first.
    final plan = await db.getFifoPlan(product, 6);
    expect(plan.allocations.first.batchNumber, 'OLD');
    expect(plan.allocations.first.quantity, 5);
    expect(plan.allocations[1].batchNumber, 'NEW');
    expect(plan.weightedCost, closeTo((90 * 5 + 110 * 1) / 6, 0.001));

    // Run the sale and confirm product total and batches stay consistent.
    final items = [
      CartItem(
        id: product.id,
        product: product.copyWith(quantity: 8),
        quantity: 6,
        unitPrice: 130,
      ),
    ];
    await db.completeSale(
      Sale(
        cashierId: 'tester',
        cashierName: 'Test',
        items: [
          SaleItem(
            productId: product.id,
            productName: product.name,
            price: 130,
            quantity: 6,
            costPrice: plan.weightedCost,
            batchNumber: plan.batchLabel,
            allocations: plan.allocations,
          ),
        ],
        subtotal: 780,
        totalDiscount: 0,
        totalAmount: 780,
        amountReceived: 780,
        balance: 0,
      ),
      items,
    );

    final after = (await db.getAllProducts()).first;
    final leftover = await db.getBatchesByProductId(product.id);
    final batchSum = leftover.fold<double>(0, (s, b) => s + b.quantity);
    expect(after.quantity, 2);
    expect(batchSum, 2);
    final oldBatch =
        leftover.firstWhere((b) => b.batchNumber == 'OLD');
    final newBatch =
        leftover.firstWhere((b) => b.batchNumber == 'NEW');
    expect(oldBatch.quantity, 0); // oldest lot consumed first
    expect(newBatch.quantity, 2); // newest lot still has 2
  });
}