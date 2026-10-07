import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/product.dart';

/// Manages the "No Barcode" category and its items.
/// This provides a dedicated section for items without barcodes,
/// making it easy to add them during billing without scanning.
class NoBarcodeProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  static const String noBarcodeCategoryId = 'no_barcode_category';
  static const String noBarcodeCategoryName = 'No Barcode';

  List<Product> _noBarcodeProducts = [];
  bool _isLoading = false;

  List<Product> get products => _noBarcodeProducts;
  bool get isLoading => _isLoading;

  /// Loads all products that belong to the "No Barcode" category.
  Future<void> loadNoBarcodeProducts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final allProducts = await _dbService.getAllProducts();
      _noBarcodeProducts = allProducts
          .where((p) => p.categoryId == noBarcodeCategoryId)
          .toList();
    } catch (e) {
      debugPrint('Error loading no-barcode products: $e');
      _noBarcodeProducts = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new product to the "No Barcode" category.
  Future<void> addNoBarcodeProduct(Product product) async {
    try {
      final noBarcodeProduct = product.copyWith(
        categoryId: noBarcodeCategoryId,
        barcode: product.barcode.isEmpty
            ? 'NOBARCODE_${DateTime.now().millisecondsSinceEpoch}'
            : product.barcode,
      );
      await _dbService.insertProduct(noBarcodeProduct);
      await loadNoBarcodeProducts();
    } catch (e) {
      debugPrint('Error adding no-barcode product: $e');
      rethrow;
    }
  }

  /// Updates a product in the "No Barcode" category.
  Future<void> updateNoBarcodeProduct(Product product) async {
    try {
      await _dbService.updateProduct(product);
      await loadNoBarcodeProducts();
    } catch (e) {
      debugPrint('Error updating no-barcode product: $e');
      rethrow;
    }
  }

  /// Deletes a product from the "No Barcode" category.
  Future<void> deleteNoBarcodeProduct(String id) async {
    try {
      await _dbService.deleteProduct(id);
      await loadNoBarcodeProducts();
    } catch (e) {
      debugPrint('Error deleting no-barcode product: $e');
      rethrow;
    }
  }

  /// Ensures the "No Barcode" category exists in the database.
  Future<void> ensureCategoryExists() async {
    try {
      final db = await _dbService.database;
      final existing = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: [noBarcodeCategoryId],
      );
      if (existing.isEmpty) {
        await db.insert('categories', {
          'id': noBarcodeCategoryId,
          'name': noBarcodeCategoryName,
          'description': 'Items without barcodes for quick billing',
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error ensuring no-barcode category: $e');
    }
  }
}
