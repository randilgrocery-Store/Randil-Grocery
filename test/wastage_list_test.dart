import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/models/customer.dart';
import 'package:randil_grocery_pos/data/models/expense.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/presentation/providers/wastage_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reproduces the "added wastage does not appear on the wastage screen" report.
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

  Future<void> insertProduct(String id, double quantity) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('products', {
      'id': id,
      'name': 'Product $id',
      'barcode': 'BC-$id',
      'categoryId': 'cat1',
      'buyingPrice': 10.0,
      'sellingPrice': 20.0,
      'quantity': quantity,
      'soldByWeight': 0,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  test('recordWastage then getAllWastages returns the row', () async {
    await insertProduct('p1', 10);
    final created = await DatabaseService().recordWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 2,
      reason: 'Expired',
    );
    expect(created, isNotNull);

    final all = await DatabaseService().getAllWastages();
    expect(all, hasLength(1));
    expect(all.first.productName, 'Product p1');
  });

  test('provider shows the row after addWastage', () async {
    await insertProduct('p1', 10);
    final provider = WastageProvider();
    await provider.addWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 3,
      reason: 'Damaged',
    );
    expect(provider.wastages, hasLength(1));
    expect(provider.isLoading, isFalse);
  });

  test('a wastage dated at midnight still syncs on the push watermark',
      () async {
    await insertProduct('p1', 10);
    // The date picker returns midnight; a row created "now" but dated midnight
    // must still be shipped or the other PC never sees it.
    await DatabaseService().recordWastage(
      productId: 'p1',
      productName: 'Product p1',
      quantity: 1,
      reason: 'Expired',
      wastageDate: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      ),
    );
    final since = DateTime.now().subtract(const Duration(minutes: 1));
    final rows = await DatabaseService().mirrorRowsSince(since);
    expect(
      (rows['wastages'] as List).length,
      1,
      reason: 'midnight-dated wastage must be included in the push',
    );
    // The revision must still be computable with the expression clock.
    expect(await DatabaseService().financialRevision(), isNotEmpty);
  });

  test('a back-dated expense still syncs on the push watermark', () async {
    await DatabaseService().insertExpense(Expense(
      description: 'Back-dated rent',
      category: 'Rent',
      amount: 1000,
      expenseDate: DateTime.now().subtract(const Duration(days: 5)),
    ));
    final since = DateTime.now().subtract(const Duration(minutes: 1));
    final rows = await DatabaseService().mirrorRowsSince(since);
    expect((rows['expenses'] as List).length, 1);
  });

  test('customers and suppliers travel through the mirror both ways',
      () async {
    // A row pushed from the other PC lands here ...
    final applied = await DatabaseService().applyMirror({
      'customers': [
        {
          'id': 'c1',
          'name': 'Nimal',
          'phone': '0770000000',
          'email': '',
          'address': '',
          'totalSpent': 0.0,
          'totalTransactions': 0,
          'createdAt': DateTime.now().toIso8601String(),
          'lastPurchaseDate': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isActive': 1,
        }
      ],
      'suppliers': [
        {
          'id': 'sup1',
          'name': 'Distributor',
          'contactPerson': '',
          'phone': '',
          'email': '',
          'address': '',
          'paymentTerms': 'COD',
          'creditLimit': null,
          'currentBalance': 0.0,
          'isActive': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        }
      ],
    });
    expect(applied, 2);
    expect(await DatabaseService().getAllCustomers(), hasLength(1));
    expect(await DatabaseService().getAllSuppliers(), hasLength(1));

    // ... and a locally added customer is shipped on the next push.
    await DatabaseService()
        .insertCustomer(Customer(name: 'Kamal', phone: '0711111111'));
    final rows = await DatabaseService()
        .mirrorRowsSince(DateTime.now().subtract(const Duration(minutes: 1)));
    final customerNames = (rows['customers'] as List)
        .map((e) => (e as Map)['name'])
        .toSet();
    expect(customerNames, containsAll(<String>{'Nimal', 'Kamal'}));
    expect((rows['suppliers'] as List), hasLength(1));
  });
}
