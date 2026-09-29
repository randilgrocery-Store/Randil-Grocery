import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/product.dart';
import '../../data/services/supabase_sync_service.dart';

class ProductProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<String> _categories = ['All'];
  bool _isLoading = false;
  String _sortBy = 'name'; // 'name', 'category', 'barcode', 'price', 'stock'

  bool get hasActiveFilters =>
      _searchQuery.trim().isNotEmpty || _selectedCategory != 'All';
  List<Product> get products =>
      hasActiveFilters ? _filteredProducts : _products;
  List<Product> get allProducts => _products;
  List<String> get categories => _categories;
  String get selectedCategory => _selectedCategory;
  bool get isLoading => _isLoading;
  String get sortBy => _sortBy;

  Future<void> loadProducts() async {
    _isLoading = true;
    notifyListeners();
    try {
      _products = await _dbService.getAllProducts();
      _updateCategories();
      _applyFiltersAndSort(notify: false);
    } catch (e) {
      debugPrint('Error loading products: $e');
      _products = [];
      _filteredProducts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addProduct(Product product) async {
    try {
      // Ensure database is initialized
      await _dbService.database;

      // Insert the product
      await _dbService.insertProduct(product);

      SupabaseSyncService.instance.notifyDataChanged();

      // Reload all products
      await loadProducts();
    } catch (e) {
      debugPrint('Error adding product: $e');
      rethrow;
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      // Ensure database is initialized
      await _dbService.database;

      // Update the product
      await _dbService.updateProduct(product);

      SupabaseSyncService.instance.notifyDataChanged();

      // Reload all products
      await loadProducts();
    } catch (e) {
      debugPrint('Error updating product: $e');
      rethrow;
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _dbService.deleteProduct(id);
      await loadProducts();
      SupabaseSyncService.instance.notifyDataChanged();
    } catch (e) {
      debugPrint('Error deleting product: $e');
      rethrow;
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async =>
      _dbService.getProductByBarcode(barcode);

  /// Looks a product up by barcode, and falls back to its exact name / item
  /// code. Used by the POS scanner so any code the scanner sends works.
  Future<Product?> getProductByCode(String code) async =>
      _dbService.getProductByCode(code);

  void searchProducts(String query) {
    _searchQuery = query.trim();
    _applyFiltersAndSort();
  }

  void filterByCategory(String categoryId) {
    _selectedCategory = categoryId.isEmpty ? 'All' : categoryId;
    _applyFiltersAndSort();
  }

  void clearFilter() {
    _searchQuery = '';
    _selectedCategory = 'All';
    _applyFiltersAndSort();
  }

  void _updateCategories() {
    // Categories are now managed by CategoryProvider
    // Keep 'All' as the first option
    _categories.clear();
    _categories.add('All');
  }

  int getLowStockCount() =>
      _products.where((p) => p.quantity > 0 && p.quantity < 10).length;

  int getOutOfStockCount() => _products.where((p) => p.quantity <= 0).length;

  List<Product> getLowStockProducts() =>
      _products.where((p) => p.quantity > 0 && p.quantity < 10).toList();

  List<Product> getOutOfStockProducts() =>
      _products.where((p) => p.quantity <= 0).toList();

  bool isProductAvailable(String productId) {
    final product = _products.firstWhere((p) => p.id == productId,
        orElse: () => Product(
              name: '',
              barcode: '',
              categoryId: '',
              buyingPrice: 0,
              sellingPrice: 0,
              quantity: 0,
            ));
    return product.quantity > 0;
  }

  void sortByName() {
    _sortBy = 'name';
    _applyFiltersAndSort();
  }

  void sortByCategory() {
    _sortBy = 'category';
    _applyFiltersAndSort();
  }

  void sortByBarcode() {
    _sortBy = 'barcode';
    _applyFiltersAndSort();
  }

  void sortByPrice() {
    _sortBy = 'price';
    _applyFiltersAndSort();
  }

  void sortByStock() {
    _sortBy = 'stock';
    _applyFiltersAndSort();
  }

  int _compareProducts(Product a, Product b) {
    switch (_sortBy) {
      case 'barcode':
        return a.barcode.compareTo(b.barcode);
      case 'category':
        final categoryCompare = a.categoryId.compareTo(b.categoryId);
        if (categoryCompare != 0) {
          return categoryCompare;
        }
        return a.name.compareTo(b.name);
      case 'price':
        return a.sellingPrice.compareTo(b.sellingPrice);
      case 'stock':
        return a.quantity.compareTo(b.quantity);
      case 'name':
      default:
        return a.name.compareTo(b.name);
    }
  }

  void _applyFiltersAndSort({bool notify = true}) {
    _products.sort(_compareProducts);

    if (!hasActiveFilters) {
      _filteredProducts = [];
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final search = _searchQuery.toLowerCase();
    _filteredProducts = _products.where((product) {
      final matchesCategory =
          _selectedCategory == 'All' || product.categoryId == _selectedCategory;
      final matchesSearch = search.isEmpty ||
          product.name.toLowerCase().contains(search) ||
          product.barcode.toLowerCase().contains(search);
      return matchesCategory && matchesSearch;
    }).toList()
      ..sort(_compareProducts);

    if (notify) {
      notifyListeners();
    }
  }
}
