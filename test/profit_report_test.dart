import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the one honest bottom line: Net Profit must fold in bills, the cost
/// of what sold, expenses, wastage, refunds paid out **and** the reload margin
/// earned — on both the Profit & Expenses report and the dashboard P&L.
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

  Future<void> insertSale(String id, double total, double cost) async {
    await db.insert('sales', {
      'id': id,
      'invoiceNumber': 'INV-$id',
      'cashierId': 'u1',
      'cashierName': 'Cashier',
      'items': jsonEncode([
        {
          'id': 'li1',
          'productId': 'p1',
          'productName': 'Milk',
          'price': total,
          'quantity': 1.0,
          'discount': 0.0,
          'costPrice': cost,
          'batchNumber': '',
          'barcode': '',
          'allocations': <Object>[],
        }
      ]),
      'subtotal': total,
      'totalDiscount': 0.0,
      'totalAmount': total,
      'amountReceived': total,
      'balance': 0.0,
      'paymentMethod': 'Cash',
      'saleDate': DateTime.now().toIso8601String(),
      'notes': '',
      'customerName': '',
      'customerPhone': '',
      'cashAmount': total,
      'cardAmount': 0.0,
    });
  }

  Future<void> insertExpense(String id, double amount) async {
    await db.insert('expenses', {
      'id': id,
      'description': 'Expense $id',
      'category': 'Misc',
      'amount': amount,
      'expenseDate': DateTime.now().toIso8601String(),
      'notes': '',
      'recordedBy': 'admin',
    });
  }

  Future<void> insertWastage(String id, double loss) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('wastages', {
      'id': id,
      'productId': 'p1',
      'productName': 'Milk',
      'quantity': 1.0,
      'reason': 'Expired',
      'lossValue': loss,
      'batchId': '',
      'batchNumber': '',
      'notes': '',
      'recordedBy': 'admin',
      'wastageDate': now,
      'createdAt': now,
    });
  }

  Future<void> insertRefund(String id, double amount, String status) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('refund_returns', {
      'id': id,
      'originalSaleId': 's1',
      'invoiceNumber': 'INV-s1',
      'items': '[]',
      'totalRefundAmount': amount,
      'refundMethod': 'Cash',
      'status': status,
      'notes': '',
      'requesterId': '',
      'requesterName': '',
      'requestDate': now,
      'createdAt': now,
    });
  }

  Future<void> insertReload(
      String id, double value, double cost, String status) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('reload_cards', {
      'id': id,
      'value': value,
      'cost': cost,
      'status': status,
      'createdAt': now,
      'usedAt': status == 'sold' ? now : '',
    });
  }

  test('net profit folds in wastage, refunds and reload margin', () async {
    await insertSale('s1', 100.0, 60.0); // gross = 40
    await insertExpense('e1', 10.0);
    await insertWastage('w1', 5.0);
    await insertRefund('r1', 20.0, 'Processed');
    await insertRefund('r2', 7.0, 'Pending'); // not paid yet -> ignored
    await insertReload('rc1', 100.0, 95.0, 'sold'); // +5 margin
    await insertReload('rc2', 200.0, 190.0, 'bought'); // purchase, not income

    final start = DateTime.now().subtract(const Duration(days: 1));
    final end = DateTime.now().add(const Duration(days: 1));

    final report = await DatabaseService().getProfitReport(start, end);
    expect(report['totalRevenue'], 100.0);
    expect(report['totalCogs'], 60.0);
    expect(report['totalExpenses'], 10.0);
    expect(report['totalWastage'], 5.0);
    expect(report['totalRefunds'], 20.0);
    expect(report['reloadProfit'], 5.0);
    // 40 - 10 - 5 - 20 + 5
    expect(report['netProfit'], 10.0);

    final pl = await DatabaseService().getBusinessProfitLoss(start, end);
    expect(pl['reloadProfit'], 5.0);
    expect(pl['reloadSoldValue'], 100.0);
    expect(pl['reloadSoldCount'], 1);
    expect(pl['refundLoss'], 20.0);
    // 100 + 5 - (60 + 5 + 20 + 10)
    expect(pl['netProfit'], 10.0);
  });

  test('reload margin only counts sold value inside the window', () async {
    await insertReload('old', 100.0, 90.0, 'sold');
    // Backdate it well outside the window.
    await db.update(
      'reload_cards',
      {
        'usedAt':
            DateTime.now().subtract(const Duration(days: 40)).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: ['old'],
    );
    await insertReload('fresh', 50.0, 45.0, 'sold');

    final summary = await DatabaseService().getReloadSummary(
      DateTime.now().subtract(const Duration(days: 1)),
      DateTime.now().add(const Duration(days: 1)),
    );
    expect(summary['profit'], 5.0);
    expect(summary['soldValue'], 50.0);
    expect(summary['count'], 1);
  });

  test('processed refund counts on the day it was paid, not requested',
      () async {
    final now = DateTime.now();
    await db.insert('refund_returns', {
      'id': 'r-late',
      'originalSaleId': 's1',
      'invoiceNumber': 'INV-s1',
      'items': '[]',
      'totalRefundAmount': 30.0,
      'refundMethod': 'Cash',
      'status': 'Processed',
      'notes': '',
      'requesterId': '',
      'requesterName': '',
      'requestDate': now
          .subtract(const Duration(days: 10))
          .toIso8601String(),
      'processedDate': now.toIso8601String(),
      'createdAt':
          now.subtract(const Duration(days: 10)).toIso8601String(),
    });

    final todayReport = await DatabaseService().getProfitReport(
      now.subtract(const Duration(hours: 1)),
      now.add(const Duration(hours: 1)),
    );
    expect(todayReport['totalRefunds'], 30.0);

    final oldReport = await DatabaseService().getProfitReport(
      now.subtract(const Duration(days: 11)),
      now.subtract(const Duration(days: 9)),
    );
    expect(oldReport['totalRefunds'], 0.0);
  });
}
