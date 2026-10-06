import 'package:flutter_test/flutter_test.dart';

import 'package:randil_mobile/l10n/labels.dart';
import 'package:randil_mobile/models/daily_routine.dart';
import 'package:randil_mobile/models/sale_row.dart';

void main() {
  test('bilingual labels resolve for both languages', () {
    expect(tr('todayIncome', sinhala: false), "Today's Income");
    expect(tr('todayIncome', sinhala: true), 'අද ආදායම');
    expect(tr('unknown.key', sinhala: false), 'unknown.key');
  });

  test('DailyRoutine parses a real daily_routines row', () {
    final r = DailyRoutine.fromJson({
      'date': '2026-10-06T12:00:00',
      'sales_count': 12,
      'gross': 50000.0,
      'discount': 300.0,
      'net': 49700.0,
      'cash_amt': 20000.0,
      'card_amt': 29700.0,
      'mixed_amt': 0,
      'refunds_amt': 0,
      'expenses_amt': 1000.0,
      'wastage_amt': 0,
      'grn_count': 1,
      'grn_value': 12000.0,
      'top_products': [
        {'name': 'Rice', 'qty': 4.5},
      ],
      'updated_at': '2026-10-06T12:00:00Z',
    });
    expect(r.dateKey, '2026-10-06');
    expect(r.salesCount, 12);
    expect(r.gross, 50000.0);
    expect(r.net, 49700.0);
    expect(r.cashAmt, 20000.0);
    expect(r.cardAmt, 29700.0);
    expect(r.expensesAmt, 1000.0);
    expect(r.grnCount, 1);
    expect(r.topProducts.single.name, 'Rice');
    expect(r.topProducts.single.qty, 4.5);
  });

  test('DailyRoutine handles a string-encoded top_products column', () {
    final r = DailyRoutine.fromJson({
      'date': '2026-10-05',
      'sales_count': 0,
      'gross': 0,
      'discount': 0,
      'net': 0,
      'cash_amt': 0,
      'card_amt': 0,
      'mixed_amt': 0,
      'refunds_amt': 0,
      'expenses_amt': 0,
      'wastage_amt': 0,
      'grn_count': 0,
      'grn_value': 0,
      'top_products': '[{"name":"Sugar","qty":2}]',
      'updated_at': null,
    });
    expect(r.dateKey, '2026-10-05');
    expect(r.topProducts.single.name, 'Sugar');
    expect(r.updatedAt, isNull);
  });

  test('SaleRow parses a real sales_sync row', () {
    final s = SaleRow.fromJson({
      'id': 'sale-001',
      'bill_number': 'B-104',
      'amount': 1250.5,
      'payment_method': 'Cash',
      'items_count': 3,
      'timestamp': '2026-10-06T09:15:00Z',
    });
    expect(s.id, 'sale-001');
    expect(s.billNumber, 'B-104');
    expect(s.amount, 1250.5);
    expect(s.paymentMethod, 'Cash');
    expect(s.itemsCount, 3);
    expect(s.timestamp, isNotNull);
  });
}