import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/supplier.dart';
import '../../data/models/supplier_payment.dart';
import '../../data/services/supabase_sync_service.dart';

class SupplierProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  final Map<String, double> _outstanding = {};
  List<SupplierPayment> _payments = [];

  List<Supplier> get suppliers => _suppliers;
  Supplier? get selectedSupplier => _selectedSupplier;
  List<SupplierPayment> get payments => _payments;

  /// Money still owed to each supplier (GRN total minus payments made).
  double outstandingFor(String supplierId) =>
      _outstanding[supplierId] ?? 0.0;

  double get totalOutstanding =>
      _outstanding.values.fold(0.0, (a, b) => a + b);

  Future<void> loadSuppliers({bool includeInactive = false}) async {
    _suppliers =
        await _dbService.getAllSuppliers(includeInactive: includeInactive);
    _outstanding
      ..clear()
      ..addEntries(await Future.wait(_suppliers.map((s) async =>
          MapEntry(s.id, await _dbService.getSupplierOutstanding(s.id)))));
    notifyListeners();
  }

  Future<void> loadPayments([String? supplierId]) async {
    _payments = supplierId == null
        ? await _dbService.getAllSupplierPayments()
        : await _dbService.getSupplierPayments(supplierId);
    notifyListeners();
  }

  /// Record a cash or cheque payment made to a supplier.
  Future<void> recordPayment({
    required Supplier supplier,
    required double amount,
    required String method,
    String chequeNumber = '',
    String bankName = '',
    DateTime? chequeDate,
    String note = '',
  }) async {
    final payment = SupplierPayment(
      supplierId: supplier.id,
      supplierName: supplier.name,
      amount: amount,
      method: method,
      chequeNumber: chequeNumber,
      bankName: bankName,
      chequeDate: chequeDate,
      note: note,
    );
    await _dbService.recordSupplierPayment(payment);
    _outstanding[supplier.id] =
        await _dbService.getSupplierOutstanding(supplier.id);
    notifyListeners();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> deletePayment(SupplierPayment payment) async {
    await _dbService.deleteSupplierPayment(payment.id);
    _outstanding[payment.supplierId] =
        await _dbService.getSupplierOutstanding(payment.supplierId);
    notifyListeners();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> addSupplier({
    required String name,
    required String contactPerson,
    required String phone,
    required String email,
    required String address,
    String paymentTerms = 'COD',
    double? creditLimit,
  }) async {
    final supplier = Supplier(
      name: name,
      contactPerson: contactPerson,
      phone: phone,
      email: email,
      address: address,
      paymentTerms: paymentTerms,
      creditLimit: creditLimit,
    );

    await _dbService.insertSupplier(supplier);
    await loadSuppliers();
  }

  Future<void> updateSupplier(Supplier supplier) async {
    await _dbService.updateSupplier(supplier);
    await loadSuppliers();
  }

  Future<void> deleteSupplier(String supplierId) async {
    await _dbService.deleteSupplier(supplierId);
    await loadSuppliers();
  }

  Future<Supplier?> getSupplierById(String id) async => _dbService.getSupplierById(id);

  void selectSupplier(Supplier? supplier) {
    _selectedSupplier = supplier;
    notifyListeners();
  }

  // Update supplier balance after placing/paying for order
  Future<void> updateSupplierBalance(String supplierId, double amount) async {
    final supplier = await getSupplierById(supplierId);
    if (supplier != null) {
      final updatedSupplier = supplier.copyWith(
        currentBalance: supplier.currentBalance + amount,
      );
      await updateSupplier(updatedSupplier);
    }
  }

  // Check if supplier has available credit
  Future<bool> hasAvailableCredit(String supplierId, double amount) async {
    final supplier = await getSupplierById(supplierId);
    if (supplier == null || supplier.creditLimit == null) return false;
    return (supplier.creditLimit! - supplier.currentBalance) >= amount;
  }
}
