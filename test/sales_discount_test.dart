import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/models/cart_item.dart';
import 'package:randil_grocery_pos/data/models/held_bill.dart';
import 'package:randil_grocery_pos/data/models/product.dart';

/// Product priced per unit, quantity available. Kept minimal because these tests
/// exercise the discount arithmetic, not the product model.
Product _product(String id, double price, {double stock = 100}) => Product(
      id: id,
      name: 'Item $id',
      barcode: 'BC$id',
      categoryId: 'c1',
      sellingPrice: price,
      buyingPrice: price * 0.8,
      quantity: stock,
      reorderLevel: 0,
      createdAt: DateTime(2026, 1, 1),
    );

/// The discount arithmetic as plain model getters, mirroring what the POS
/// screen charges. The models themselves are the production code under test:
/// CartItem.discount is a per-line percentage, HeldBill holds a bill-level
/// percentage that is applied after the line discounts.
void main() {
  group('line discount', () {
    test('10% off a 1000.00 line is 100.00', () {
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

    test('the discount is stored as a percentage, the amount is derived', () {
      // Re-pinning the exact relationship so a change to the discount field
      // semantics is caught here first.
      final item = CartItem(
        id: 'p1',
        product: _product('p1', 250),
        quantity: 4,
        discount: 20,
      );
      expect(item.subtotal, 1000);
      expect(item.discountAmount, 200);
      expect(item.total, 800);
    });

    test('a zero discount leaves the line unchanged', () {
      final item = CartItem(
        id: 'p1',
        product: _product('p1', 1000),
        quantity: 1,
      );
      expect(item.discountAmount, 0);
      expect(item.total, 1000);
    });
  });

  group('line discount then bill discount', () {
    test('the bill percentage applies to the full subtotal, not the residue', () {
      // A 10% line discount plus a 10% bill discount on 1000.00:
      //   line discount   = 10% of 1000 = 100
      //   bill discount   = 10% of the full 1000 subtotal = 100
      //   total discount  = 200, total = 800
      //
      // This is the shipped behaviour: the bill percentage is a flat percent
      // off the whole bill, and line discounts are additional. Keep it pinned
      // so a change to either side of the arithmetic is caught here first.
      final bill = HeldBill(
        items: [
          CartItem(
            id: 'p1',
            product: _product('p1', 500),
            quantity: 2,
            discount: 10,
          ),
        ],
        discountPercentage: 10,
      );
      expect(bill.subtotal, 1000);
      expect(bill.totalDiscount, 200);
      expect(bill.total, 800);
    });

    test('10% bill plus a 10% line discount is 20% overall', () {
      final bill = HeldBill(
        items: [
          CartItem(
            id: 'p1',
            product: _product('p1', 1000),
            quantity: 1,
            discount: 10,
          ),
        ],
        discountPercentage: 10,
      );
      expect(bill.totalDiscount, 200);
      expect(bill.totalDiscount / bill.subtotal * 100, closeTo(20, 0.001));
    });

    test('a bill discount on an undiscounted bill is a flat percentage', () {
      final bill = HeldBill(
        items: [
          CartItem(id: 'p1', product: _product('p1', 1000), quantity: 1),
        ],
        discountPercentage: 15,
      );
      expect(bill.totalDiscount, 150);
      expect(bill.total, 850);
    });
  });

  group('empty cart', () {
    test('every figure is zero and no division blows up', () {
      final bill = HeldBill(items: [], discountPercentage: 10);
      expect(bill.subtotal, 0);
      expect(bill.totalDiscount, 0);
      expect(bill.total, 0);
    });
  });

  group('HeldBill carries a percentage and survives serialization', () {
    test('stores the percentage and the totals follow the same math', () {
      final bill = HeldBill(
        items: [
          CartItem(
            id: 'p1',
            product: _product('p1', 1000),
            quantity: 1,
            discount: 10,
          ),
        ],
        discountPercentage: 10,
        customerName: 'Nimal',
      );
      expect(bill.discountPercentage, 10);
      expect(bill.totalDiscount, 200);
      expect(bill.total, 800);
    });

    test('round-trips the bill-level percentage and customer through a map', () {
      final original = HeldBill(
        items: [
          CartItem(id: 'p1', product: _product('p1', 1000), quantity: 1),
        ],
        discountPercentage: 12.5,
        customerName: 'Kasun',
        notes: 'held at the counter',
      );
      final restored = HeldBill.fromMap(original.toMap());
      expect(restored.discountPercentage, 12.5);
      expect(restored.customerName, 'Kasun');
      expect(restored.notes, 'held at the counter');
    });
  });
}