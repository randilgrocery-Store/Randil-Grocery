import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/purchase_order.dart';

class PurchaseOrderProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<PurchaseOrder> _orders = [];
  bool _isLoading = false;

  List<PurchaseOrder> get orders => _orders;
  List<PurchaseOrder> get pendingOrders =>
      _orders.where((o) => !o.isReceived && !o.isCancelled).toList();
  List<PurchaseOrder> get receivedOrders =>
      _orders.where((o) => o.isReceived).toList();
  bool get isLoading => _isLoading;

  Future<void> loadOrders() async {
    _isLoading = true;
    notifyListeners();
    try {
      _orders = await _dbService.getAllPurchaseOrders();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createOrder({
    required String supplierId,
    required String supplierName,
    required List<PurchaseOrderItem> items,
    String notes = '',
  }) async {
    final order = PurchaseOrder(
      supplierId: supplierId,
      supplierName: supplierName,
      items: items,
      notes: notes.trim(),
    );
    await _dbService.insertPurchaseOrder(order);
    await loadOrders();
  }

  Future<void> receiveOrder(PurchaseOrder order) async {
    await _dbService.receivePurchaseOrder(order);
    await loadOrders();
  }

  Future<void> cancelOrder(String id) async {
    await _dbService.cancelPurchaseOrder(id);
    await loadOrders();
  }
}