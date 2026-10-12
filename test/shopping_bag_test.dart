import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/product.dart';
import 'package:randil_grocery_pos/data/models/sale.dart';

/// Shopping bags live in their own table with their own stock and a usage
/// ledger (customer_sell / shop_use / restock). These tests guard the
/// database rules that keep bag stock honest and the dashboard numbers right.
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

  test('default tiers Rs 3 / 5 / 10 / 20 are seeded once', () async {
    final first = await db.ensureDefaultShoppingBags();
    expect(first.length, 4);
    expect(first.map((b) => b.price).toSet(), {3.0, 5.0, 10.0, 20.0});

    // Calling again must not duplicate the tiers.
    final again = await db.ensureDefaultShoppingBags();
    expect(again.length, 4);
  });

  test('restock and shop-use move bag stock and update the summary', () async {
    final bags = await db.ensureDefaultShoppingBags();
    final bag = bags.firstWhere((b) => b.price == 5.0);

    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: 100, type: 'restock'), true);

    var current = await db.getShoppingBagById(bag.id);
    expect(current!.quantity, 100);

    // Take 3 for the shop's own packing.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: -3, type: 'shop_use'), true);
    current = await db.getShoppingBagById(bag.id);
    expect(current!.quantity, 97);

    // Cannot go below zero.
    expect(await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: -1000, type: 'shop_use'), false);
    current = await db.getShoppingBagById(bag.id);
    expect(current!.quantity, 97);

    final now = DateTime.now();
    final summary = await db.getShoppingBagSummary(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    expect(summary['usedQty'], 3.0);
  });

  test('selling a bag through the POS deducts bag stock and logs a sale',
      () async {
    final bags = await db.ensureDefaultShoppingBags();
    final bag = bags.firstWhere((b) => b.price == 10.0);
    await db.recordShoppingBagMovement(
        bagId: bag.id, quantity: 50, type: 'restock');

    // A bag cart line carries a lightweight stub product; the bag's own stock
    // lives in shopping_bags and must move inside the same transaction.
    final stub = Product(
      name: bag.label,
      barcode: 'BAG-${bag.id}',
      categoryId: '',
      buyingPrice: bag.buyingPrice,
      sellingPrice: bag.price,
      quantity: bag.quantity,
    );
    final items = [
      CartItem(
        id: 'bag:${bag.id}',
        product: stub,
        quantity: 2,
        unitPrice: bag.price,
        isBag: true,
        bagId: bag.id,
        bagPrice: bag.price,
        bagCost: bag.buyingPrice,
      ),
    ];

    final sale = Sale(
      cashierId: 'tester',
      cashierName: 'Test',
      items: [
        SaleItem(
          productId: 'bag:${bag.id}',
          productName: bag.label,
          price: bag.price,
          quantity: 2,
          costPrice: bag.buyingPrice,
        ),
      ],
      subtotal: bag.price * 2,
      totalDiscount: 0,
      totalAmount: bag.price * 2,
      amountReceived: bag.price * 2,
      balance: 0,
    );
    await db.completeSale(sale, items);

    final after = await db.getShoppingBagById(bag.id);
    expect(after!.quantity, 48);

    final now = DateTime.now();
    final summary = await db.getShoppingBagSummary(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    expect(summary['soldQty'], 2.0);
    expect(summary['soldValue'], bag.price * 2);
  });

  test('shopping-bag tables ride the LAN mirror', () async {
    final bags = await db.getShoppingBags();
    expect(bags, isEmpty);

    await db.ensureDefaultShoppingBags();
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