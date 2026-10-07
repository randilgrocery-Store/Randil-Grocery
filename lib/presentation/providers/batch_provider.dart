import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/product_batch.dart';

class BatchProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<ProductBatch> _batches = [];
  ProductBatch? _selectedBatch;
  String? _selectedProductId;

  List<ProductBatch> get batches => _batches;
  ProductBatch? get selectedBatch => _selectedBatch;
  String? get selectedProductId => _selectedProductId;

  Future<void> loadBatchesForProduct(String productId) async {
    _selectedProductId = productId;
    _batches = await _dbService.getBatchesByProductId(productId);
    _selectedBatch = null; // Clear selection when loading new product
    notifyListeners();
  }

  Future<void> createBatch({
    required String productId,
    required String batchNumber,
    required double price,
    required double quantity,
    required DateTime expiryDate,
    required String supplierId,
    double sellingPrice = 0,
  }) async {
    final batch = ProductBatch(
      productId: productId,
      batchNumber: batchNumber,
      price: price,
      sellingPrice: sellingPrice,
      quantity: quantity,
      expiryDate: expiryDate,
      supplierId: supplierId,
    );

    await _dbService.insertProductBatch(batch);
    await loadBatchesForProduct(productId);
  }

  Future<void> updateBatch(ProductBatch batch) async {
    await _dbService.updateProductBatch(batch);
    if (_selectedProductId != null) {
      await loadBatchesForProduct(_selectedProductId!);
    }
  }

  Future<void> deleteBatch(String batchId) async {
    await _dbService.deleteProductBatch(batchId);
    if (_selectedProductId != null) {
      await loadBatchesForProduct(_selectedProductId!);
    }
  }

  Future<void> updateBatchQuantity(
    String batchId,
    double newQuantity,
  ) async {
    final matches = _batches.where((b) => b.id == batchId);
    if (matches.isEmpty) {
      return;
    }
    final batch = matches.first;
    final updatedBatch = batch.copyWith(quantity: newQuantity);
    await _dbService.updateProductBatch(updatedBatch);

    if (_selectedProductId != null) {
      await loadBatchesForProduct(_selectedProductId!);
    }
  }

  Future<void> decrementBatchQuantity(String batchId, double amount) async {
    final matches = _batches.where((b) => b.id == batchId);
    if (matches.isEmpty) {
      return;
    }
    final batch = matches.first;
    final newQuantity =
        (batch.quantity - amount).clamp(0.0, batch.quantity).toDouble();
    await updateBatchQuantity(batchId, newQuantity);
  }

  Future<List<ProductBatch>> getExpiringBatches(
          [int daysThreshold = 7]) async =>
      _dbService.getExpiringBatches(daysUntilExpiry: daysThreshold);

  Future<List<ProductBatch>> getExpiredBatches() async {
    final allBatches = await _dbService.getExpiringBatches(daysUntilExpiry: 0);
    return allBatches
        .where((batch) =>
            batch.expiryDate != null &&
            batch.expiryDate!.isBefore(DateTime.now()))
        .toList();
  }

  void selectBatch(ProductBatch? batch) {
    _selectedBatch = batch;
    notifyListeners();
  }

  // Get total value of all batches for a product
  Future<double> getTotalValueForProduct(String productId) async {
    final productBatches = await _dbService.getBatchesByProductId(productId);
    return productBatches.fold<double>(
      0,
      (sum, batch) => sum + (batch.price * batch.quantity),
    );
  }

  // Get FIFO batch for picking (oldest expiry first)
  Future<ProductBatch?> getNextBatchForPicking(String productId) async {
    final productBatches = await _dbService.getBatchesByProductId(productId);
    if (productBatches.isEmpty) {
      return null;
    }

    // Filter out expired batches
    final validBatches = productBatches
        .where((b) =>
            b.expiryDate != null && b.expiryDate!.isAfter(DateTime.now()))
        .toList();

    if (validBatches.isEmpty) {
      return null;
    }

    // Sort by expiry date (FIFO)
    validBatches.sort((a, b) => (a.expiryDate ?? DateTime.now())
        .compareTo(b.expiryDate ?? DateTime.now()));
    return validBatches.first;
  }
}
