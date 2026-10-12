import 'package:flutter_test/flutter_test.dart';

import 'package:randil_grocery_pos/data/models/sale.dart';
import 'package:randil_grocery_pos/presentation/screens/refunds/refund_return_screen.dart';

/// Guards the return-amount maths: a return must refund the share of the bill
/// the customer actually paid. Line-level discounts live on each SaleItem;
/// the whole-bill discount (applied on the gross subtotal in the POS) must be
/// spread across the returned lines, or the shop pays back more money than it
/// received.
void main() {
  group('refundBillDiscountRatio', () {
    test('plain bill without a whole-bill discount pays back face value', () {
      final sale = _sale(
        items: [_item(price: 100, qty: 2, discount: 0)],
        subtotal: 200,
        totalDiscount: 0,
        totalAmount: 200,
      );
      expect(refundBillDiscountRatio(sale), 1.0);
    });

    test('10% whole-bill discount is shared across the lines', () {
      final sale = _sale(
        items: [_item(price: 100, qty: 2, discount: 0)],
        subtotal: 200,
        totalDiscount: 20,
        totalAmount: 180,
      );
      expect(refundBillDiscountRatio(sale), closeTo(0.9, 1e-9));
    });

    test('line discounts are excluded before the bill share is computed', () {
      final sale = _sale(
        items: [
          _item(price: 100, qty: 1, discount: 10), // net 90
          _item(price: 200, qty: 1, discount: 0), //  net 200
        ],
        subtotal: 300,
        totalDiscount: 40, // 10 (line) + 30 (bill @10% of 300)
        totalAmount: 260,
      );
      // linesNet = 290; the customer paid 260 of that -> 260/290.
      final ratio = refundBillDiscountRatio(sale);
      expect(ratio, closeTo(260 / 290, 1e-9));
    });

    test('fully discounted bill refunds nothing', () {
      final sale = _sale(
        items: [_item(price: 100, qty: 1, discount: 0)],
        subtotal: 100,
        totalDiscount: 100,
        totalAmount: 0,
      );
      expect(refundBillDiscountRatio(sale), 0.0);
    });

    test('a fully line-discounted bill never divides by zero', () {
      final sale = _sale(
        items: [_item(price: 100, qty: 1, discount: 100)], // net 0
        subtotal: 100,
        totalDiscount: 0,
        totalAmount: 100,
      );
      expect(refundBillDiscountRatio(sale), 0.0);
    });
  });

  group('refundUnitNet', () {
    test('applies only the line discount', () {
      expect(refundUnitNet(_item(price: 120, qty: 1, discount: 25)),
          closeTo(90, 1e-9));
    });

    test('refunded amount combines line share and bill share', () {
      final item = _item(price: 100, qty: 1, discount: 10);
      final sale = _sale(
        items: [item, _item(price: 200, qty: 1, discount: 0)],
        subtotal: 300,
        totalDiscount: 40,
        totalAmount: 260,
      );
      final refund = refundUnitNet(item) * refundBillDiscountRatio(sale);
      expect(refund, closeTo(90 * (260 / 290), 1e-9));
      // …and the amount handed back can never exceed face value.
      expect(refund, lessThanOrEqualTo(refundUnitNet(item)));
    });
  });
}

SaleItem _item({
  required double price,
  required double qty,
  required double discount,
}) =>
    SaleItem(
      productId: 'p1',
      productName: 'Product',
      price: price,
      quantity: qty,
      discount: discount,
    );

Sale _sale({
  required List<SaleItem> items,
  required double subtotal,
  required double totalDiscount,
  required double totalAmount,
}) =>
    Sale(
      cashierId: 'u1',
      cashierName: 'Cashier',
      items: items,
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalAmount: totalAmount,
      amountReceived: totalAmount,
      balance: 0,
    );