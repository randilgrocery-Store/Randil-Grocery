import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'category_provider.dart';
import 'customer_provider.dart';
import 'product_provider.dart';
import 'reports_provider.dart';
import 'supplier_provider.dart';

/// Global reload system that refreshes all data across the app.
/// Provides a single point to trigger a full data reload from the database.
class ReloadProvider extends ChangeNotifier {
  bool _isReloading = false;
  DateTime? _lastReloadTime;
  int _reloadCount = 0;

  bool get isReloading => _isReloading;
  DateTime? get lastReloadTime => _lastReloadTime;
  int get reloadCount => _reloadCount;

  /// Reloads all data from the database across all providers.
  /// This is the main entry point for the reload system.
  Future<void> reloadAll(BuildContext context) async {
    if (_isReloading) return;

    _isReloading = true;
    notifyListeners();

    try {
      // Reload all core data providers
      await Future.wait([
        context.read<ProductProvider>().loadProducts(),
        context.read<CategoryProvider>().loadCategories(),
        context.read<CustomerProvider>().loadCustomers(),
        context.read<SupplierProvider>().loadSuppliers(),
        context.read<ReportsProvider>().generateDailyReport(DateTime.now()),
      ]);

      _lastReloadTime = DateTime.now();
      _reloadCount++;
    } catch (e) {
      debugPrint('Error during reload: $e');
    } finally {
      _isReloading = false;
      notifyListeners();
    }
  }

  /// Reloads only product-related data (faster for POS screen).
  Future<void> reloadProducts(BuildContext context) async {
    if (_isReloading) return;

    _isReloading = true;
    notifyListeners();

    try {
      await context.read<ProductProvider>().loadProducts();
      _lastReloadTime = DateTime.now();
      _reloadCount++;
    } catch (e) {
      debugPrint('Error reloading products: $e');
    } finally {
      _isReloading = false;
      notifyListeners();
    }
  }

  /// Resets the reload statistics.
  void resetStats() {
    _reloadCount = 0;
    _lastReloadTime = null;
    notifyListeners();
  }
}
