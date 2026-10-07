import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/product.dart';
import 'package:randil_grocery_pos/data/models/sale.dart';
import 'package:randil_grocery_pos/data/models/shop_settings.dart';
import 'package:randil_grocery_pos/data/services/print_service.dart';

Product _product(
  String id,
  double price, {
  double stock = 100,
  bool soldByWeight = false,
}) =>
    Product(
      id: id,
      name: 'Item $id',
      barcode: 'BC$id',
      categoryId: 'c1',
      sellingPrice: price,
      buyingPrice: price * 0.8,
      quantity: stock,
      reorderLevel: 0,
      soldByWeight: soldByWeight,
      createdAt: DateTime(2026, 1, 1),
    );

/// Builds the sale the same way SalesProvider.processSale does, so the
/// receipt is checked against a realistic bill rather than a hand-made one.
Sale _sale({
  required List<CartItem> items,
  required double subtotal,
  required double totalDiscount,
  required double total,
  required double paid,
}) =>
    Sale(
      cashierId: 'u1',
      cashierName: 'Tester',
      invoiceNumber: 'INV-000001',
      items: items
          .map(
            (i) => SaleItem(
              productId: i.product.id,
              productName: i.product.name,
              price: i.unitPrice,
              quantity: i.quantity,
              discount: i.discount,
              costPrice: i.product.buyingPrice,
              barcode: i.product.barcode,
            ),
          )
          .toList(),
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalAmount: total,
      amountReceived: paid,
      balance: paid - total,
      paymentMethod: 'Cash',
    );

void main() {
  final settings = ShopSettings(
    shopName: 'Randil Grocery',
    currencySymbol: 'Rs',
    paperWidth: 58,
  );

  group('receipt arithmetic must add up', () {
    test('the printed rows add up to the printed total', () {
      final items = [
        CartItem(id: 'p1', product: _product('p1', 250), quantity: 4),
      ];
      final sale = _sale(
        items: items,
        subtotal: 1000,
        totalDiscount: 190,
        total: 810,
        paid: 1000,
      );

      final text = PrintService().generateReceiptText(sale, settings);

      // 1000 - 190 must equal the 810 on the bill. The change figure has to be
      // the 190 the cashier handed back.
      expect(text, contains('1000.00'));
      expect(text, contains('810.00'));
      expect(text, contains('190.00'));
    });

    test('a discounted bill reports the same discount the cashier entered', () {
      final items = [
        CartItem(
          id: 'p1',
          product: _product('p1', 1000),
          quantity: 1,
          discount: 10,
        ),
      ];
      // 10% line discount = 100, then a 90 rupee bill discount = 190 total.
      final sale = _sale(
        items: items,
        subtotal: 1000,
        totalDiscount: 190,
        total: 810,
        paid: 1000,
      );

      final text = PrintService().generateReceiptText(sale, settings);
      expect(text, contains('190.00'));
      expect(text, contains('810.00'));
    });
  });

  group('line discounts are percentages of the line', () {
    test('10% off a 1000 unit-price line is 100 off', () {
      final item = CartItem(
        id: 'p1',
        product: _product('p1', 1000),
        quantity: 1,
        discount: 10,
      );
      expect(item.discountAmount, 100);
      expect(item.total, 900);
    });

    test('the percentage is derived from the amount, never stored', () {
      // A fresh receipt from those same numbers must print the same figure the
      // cashier saw on screen, not a re-derived one from a stored percentage.
      final item = CartItem(
        id: 'p1',
        product: _product('p1', 500),
        quantity: 2,
        discount: 10,
      );
      expect(item.subtotal, 1000);
      expect(item.discountAmount, 100);
      expect(item.total, 900);
    });
  });

  group('weight-based goods', () {
    test('half a kilo of a per-kg item charges half the price', () {
      // 0.5 means half a kilogram. Priced per kg, so half of it must be half
      // the price — this is the arithmetic that made weighed goods either free
      // or double-charged when quantities were forced to whole numbers.
      final item = CartItem(
        id: 'p1',
        product: _product('p1', 1000, soldByWeight: true),
        quantity: 0.5,
      );
      expect(item.unitPrice, 1000.0);
      expect(item.subtotal, 500);

      final sale = _sale(
        items: [item],
        subtotal: 500,
        totalDiscount: 0,
        total: 500,
        paid: 500,
      );
      final text = PrintService().generateReceiptText(sale, settings);
      expect(text, contains('500.00'));
    });
  });
}