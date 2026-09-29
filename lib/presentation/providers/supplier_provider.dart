import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/supplier.dart';

class SupplierProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;

  List<Supplier> get suppliers => _suppliers;
  Supplier? get selectedSupplier => _selectedSupplier;

  Future<void> loadSuppliers({bool includeInactive = false}) async {
    _suppliers =
        await _dbService.getAllSuppliers(includeInactive: includeInactive);
    notifyListeners();
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
