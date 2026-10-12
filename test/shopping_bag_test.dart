import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/product.dart';
import 'package:randil_grocery_pos/data/models/sale.dart';
import 'package:randil_grocery_pos/data/models/shopping_bag.dart';

/// Shopping bags are bought, stocked, used and sold as whole BULK bundles and
/// live in their own table with their own stock and usage ledger
/// (customer_sell / shop_use / restock). These tests guard the database rules
/// that keep bundle stock honest, the dashboard numbers right, and the POS
/// retail bag charge independent of the bulk stock.
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
    db.debugResetDatabase();
    await conn.close();
  });

  test('bulk bags are created by hand and start with no stock', () async {
    expect(await db.getShoppingBags(), isEmpty);

    await db.upsertShoppingBag(ShoppingBag(
      label: 'Big bag bundle',
      price: 120,
      buyingPrice: 100,
    ));

    final bags = await db.getShoppingBags();
    expect(bags.length, 1);
    expect(bags.first.label, 'Big bag bundle');
    expect(bags.first.quantity, 0);
    expect(bags.first.profitPerBundle, 20);
  });

  test('restock, shop use and a customer sale move bundle stock and totals',
      () async {
    await db.upsertShoppingBag(ShoppingBag(
      label: 'Big bundle',
      price: 120,
      buyingPrice: 100,
    ));
    final bag = (await db.getShoppingBags()).first;

    // Buy 20 bundles.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: 20, type: 'restock'), true);
    expect((await db.getShoppingBagById(bag.id))!.quantity, 20);

    // Take 3 bundles for the shop's own use.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: -3, type: 'shop_use'), true);
    // Sell 5 bundles to a customer.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: -5, type: 'customer_sell'), true);

    // Cannot go below zero.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: -1000, type: 'shop_use'), false);
    expect((await db.getShoppingBagById(bag.id))!.quantity, 12);

    final now = DateTime.now();
    final summary = await db.getShoppingBagSummary(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    expect(summary['soldQty'], 5.0);
    expect(summary['soldValue'], 600.0);
    expect(summary['soldCost'], 500.0);
    expect(summary['soldProfit'], 100.0);
    expect(summary['usedQty'], 3.0);
    expect(summary['usedCost'], 300.0);
    expect(summary['restockQty'], 20.0);
  });

  test('POS retail bag charge never touches the bulk bag stock', () async {
    await db.upsertShoppingBag(ShoppingBag(
      label: 'Big bundle',
      price: 120,
      buyingPrice: 100,
    ));
    final bag = (await db.getShoppingBags()).first;
    await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: 20, type: 'restock');

    // Rs 5 retail bags rung on the bill as an ordinary charge line.
    final stub = Product(
      name: 'Shopping Bag (Rs 5)',
      barcode: 'BAG-5',
      categoryId: '',
      buyingPrice: 0,
      sellingPrice: 5,
      quantity: 0,
    );
    final items = [
      CartItem(
        id: 'bag-charge:5.00',
        product: stub,
        quantity: 4,
        unitPrice: 5,
        isBag: true,
        bagId: '5.00',
        bagPrice: 5,
        bagCost: 0,
      ),
    ];
    final sale = Sale(
      cashierId: 'tester',
      cashierName: 'Test',
      items: [
        SaleItem(
          productId: 'bag:5.00',
          productName: 'Shopping Bag (Rs 5)',
          price: 5,
          quantity: 4,
          costPrice: 0,
        ),
      ],
      subtotal: 20,
      totalDiscount: 0,
      totalAmount: 20,
      amountReceived: 20,
      balance: 0,
    );
    await db.completeSale(sale, items);

    // Bulk stock is untouched and no bulk movement was logged.
    expect((await db.getShoppingBagById(bag.id))!.quantity, 20);
    final now = DateTime.now();
    final summary = await db.getShoppingBagSummary(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    expect(summary['soldQty'], 0.0);
    expect(summary['usedQty'], 0.0);
  });

  test('shopping-bag tables ride the LAN mirror', () async {
    await db.upsertShoppingBag(ShoppingBag(
      label: 'Big bundle',
      price: 120,
      buyingPrice: 100,
    ));
    await db.recordShoppingBagMovement(
      bagId: (await db.getShoppingBags()).first.id,
      quantity: 10,
      type: 'restock',
    );

    final tables = await db.mirrorRowsSince(null);
    expect(tables['shopping_bags'], isA<List>());
    expect((tables['shopping_bags'] as List), isNotEmpty);
    expect(tables['shopping_bag_usage'], isA<List>());
    expect((tables['shopping_bag_usage'] as List), isNotEmpty);
  });
}
