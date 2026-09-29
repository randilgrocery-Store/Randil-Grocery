import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/customer.dart';

class CustomerProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  String _searchQuery = '';
  bool _isLoading = false;

  /// When a search is active this returns only the matching customers (which
  /// may legitimately be empty); otherwise it returns everyone.
  List<Customer> get customers =>
      _searchQuery.isEmpty ? _customers : _filteredCustomers;
  List<Customer> get allCustomers => _customers;
  bool get isLoading => _isLoading;

  Future<void> loadCustomers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _customers = await _dbService.getAllCustomers();
      _customers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('Error loading customers: $e');
      _customers = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCustomer(Customer customer) async {
    try {
      await _dbService.insertCustomer(customer);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error adding customer: $e');
      rethrow;
    }
  }

  Future<void> updateCustomer(Customer customer) async {
    try {
      await _dbService.updateCustomer(customer);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error updating customer: $e');
      rethrow;
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await _dbService.deleteCustomer(id);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error deleting customer: $e');
      rethrow;
    }
  }

  Future<Customer?> getCustomerByPhone(String phone) async =>
      _dbService.getCustomerByPhone(phone);

  void searchCustomers(String query) {
    _searchQuery = query.trim();
    if (_searchQuery.isEmpty) {
      _filteredCustomers = [];
    } else {
      _filteredCustomers = _customers
          .where(
            (c) =>
                c.name.toLowerCase().contains(query.toLowerCase()) ||
                c.phone.contains(query) ||
                c.email.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
    notifyListeners();
  }

  int getTotalCustomers() => _customers.length;

  Customer? getCustomerById(String id) {
    try {
      return _customers.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateCustomerAfterSale(String customerId, double amount) async {
    try {
      await _dbService.updateCustomerAfterSale(customerId, amount);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error updating customer after sale: $e');
      rethrow;
    }
  }

  Future<void> adjustCustomerCredit(
    String customerId,
    double amount, {
    bool add = true,
  }) async {
    try {
      await _dbService.adjustCustomerCredit(customerId, amount, add: add);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error adjusting customer credit: $e');
      rethrow;
    }
  }

  Future<void> adjustCustomerLoyaltyPoints(
    String customerId,
    int points,
  ) async {
    try {
      await _dbService.adjustCustomerLoyaltyPoints(customerId, points);
      await loadCustomers();
    } catch (e) {
      debugPrint('Error adjusting loyalty points: $e');
      rethrow;
    }
  }

  Future<void> updateCustomerCreditAndLoyalty({
    required String customerId,
    required double amountSpent,
    required double amountReceived,
    required double creditApplied,
    required int redeemedPoints,
    required int pointsEarned,
  }) async {
    try {
      await _dbService.updateCustomerCreditAndLoyalty(
        customerId: customerId,
        amountSpent: amountSpent,
        amountReceived: amountReceived,
        creditApplied: creditApplied,
        redeemedPoints: redeemedPoints,
        pointsEarned: pointsEarned,
      );
      await loadCustomers();
    } catch (e) {
      debugPrint('Error updating customer credit and loyalty: $e');
      rethrow;
    }
  }
}
