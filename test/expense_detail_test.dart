import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/models/expense.dart';

/// The expense record now carries whom the money was paid to and who recorded
/// it, so the owner can reconcile the cash drawer. These fields must survive a
/// database round-trip (the LAN mirror ships the row verbatim).
void main() {
  test('expense keeps paidTo / recordedBy through toMap + fromMap', () {
    final e = Expense(
      id: 'e1',
      description: 'Supplier delivery',
      category: 'Supplies',
      amount: 1500.0,
      paidTo: 'Nimal Stores',
      recordedBy: 'Kumari',
      expenseDate: DateTime(2026, 10, 10, 12, 30),
      createdAt: DateTime(2026, 10, 10, 12, 31),
      notes: 'cash from drawer',
    );

    final map = e.toMap();
    expect(map['paidTo'], 'Nimal Stores');
    expect(map['recordedBy'], 'Kumari');

    final back = Expense.fromMap(map);
    expect(back.paidTo, 'Nimal Stores');
    expect(back.recordedBy, 'Kumari');
    expect(back.amount, 1500.0);
    expect(back.description, 'Supplier delivery');
    expect(back.expenseDate, DateTime(2026, 10, 10, 12, 30));
  });

  test('old rows without paidTo default to empty, never throw', () {
    final legacy = {
      'id': 'e2',
      'description': 'Old record',
      'category': 'Other',
      'amount': 100.0,
      'expenseDate': '2026-09-01T00:00:00.000',
      'notes': '',
      'recordedBy': '',
      'createdAt': '2026-09-01T00:00:00.000',
    };
    final e = Expense.fromMap(legacy);
    expect(e.paidTo, '');
    expect(e.recordedBy, '');
  });
}
