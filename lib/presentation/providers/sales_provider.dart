import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/held_bill.dart';
import '../../data/models/product.dart';
import '../../data/models/sale.dart';
import '../../data/services/network_sync.dart';
import '../../data/services/supabase_sync_service.dart';

class SalesProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<CartItem> _cartItems = [];
  double _discountPercentage = 0;
  final List<HeldBill> _heldBills = [];
  Sale? _lastSale;

  List<CartItem> get cartItems => _cartItems;
  int get itemCount => _cartItems.length;
  double get subtotal =>
      _cartItems.fold<double>(0, (sum, item) => sum + item.subtotal);
  double get totalDiscount =>
      _cartItems.fold<double>(0, (sum, item) => sum + item.discountAmount) +
      ((subtotal * _discountPercentage) / 100);
  double get total => subtotal - totalDiscount;
  double get discountPercentage => _discountPercentage;
  List<HeldBill> get heldBills => _heldBills;
  Sale? get lastSale => _lastSale;

  /// Adds a product to the cart, resolving the price from the oldest stock
  /// batch (FIFO) so goods bought at an older price are sold at that price.
  Future<void> addToCart(Product product, {double quantity = 1}) async {
    if (product.quantity <= 0) {
      return; // Don't add out of stock items
    }

    final existingIndex = _cartItems.indexWhere(
      (item) => item.product.id == product.id,
    );

    final double desiredQuantity;
    if (existingIndex >= 0) {
      final updated = _cartItems[existingIndex];
      final maxAddable = product.quantity - updated.quantity;
      if (maxAddable <= 0) {
        return;
      }
      final add = quantity.clamp(0.0, maxAddable);
      updated.quantity += add;
      desiredQuantity = updated.quantity;
    } else {
      desiredQuantity = quantity.clamp(0.0, product.quantity);
      if (desiredQuantity <= 0) return;
      _cartItems.add(
        CartItem(
          id: product.id,
          product: product,
          quantity: desiredQuantity,
          unitPrice: product.sellingPrice,
        ),
      );
    }

    // Resolve the FIFO price for the whole line. When the line spans several
    // batches with different prices this is the weighted average, exactly what
    // processSale charges.
    final index = _cartItems.indexWhere((i) => i.product.id == product.id);
    if (index >= 0) {
      try {
        final plan = await _dbService.getFifoPlan(product, desiredQuantity);
        _cartItems[index].unitPrice = plan.effectivePrice;
      } catch (_) {
        // Keep the current price if the plan cannot be resolved.
      }
    }

    notifyListeners();
  }

  void removeFromCart(String productId) {
    _cartItems.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  Future<void> updateCartItemQuantity(String productId, double quantity) async {
    final index = _cartItems.indexWhere((item) => item.product.id == productId);
    if (index < 0) {
      return;
    }
    if (quantity <= 0) {
      _cartItems.removeAt(index);
      notifyListeners();
      return;
    }

    final item = _cartItems[index];
    final validQuantity = quantity.clamp(0.0, item.product.quantity);
    item.quantity = validQuantity;

    try {
      final plan = await _dbService.getFifoPlan(item.product, validQuantity);
      item.unitPrice = plan.effectivePrice;
    } catch (_) {
      // Keep the current price if the plan cannot be resolved.
    }

    notifyListeners();
  }

  void updateCartItemDiscount(String productId, double discount) {
    final index = _cartItems.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      _cartItems[index].discount = discount;
      notifyListeners();
    }
  }

  void setGlobalDiscount(double percentage) {
    _discountPercentage = percentage.clamp(0, 100);
    notifyListeners();
  }

  void applyQuickDiscount(double percentage) {
    setGlobalDiscount(percentage);
  }

  void applyCustomDiscount(double amount) {
    if (subtotal > 0) {
      final percentage = (amount / subtotal) * 100;
      setGlobalDiscount(percentage.clamp(0, 100));
    }
  }

  void holdBill({String? customerName, String notes = ''}) {
    if (_cartItems.isEmpty) {
      return;
    }

    final heldBill = HeldBill(
      items: _cartItems.map((item) => item.copyWith()).toList(),
      discountPercentage: _discountPercentage,
      customerName: customerName,
      notes: notes,
    );

    _heldBills.add(heldBill);
    clearCart();
    notifyListeners();
  }

  void resumeBill(HeldBill heldBill) {
    _cartItems = heldBill.items.map((item) => item.copyWith()).toList();
    _discountPercentage = heldBill.discountPercentage;
    _heldBills.removeWhere((bill) => bill.id == heldBill.id);
    notifyListeners();
  }

  void removeHeldBill(String billId) {
    _heldBills.removeWhere((bill) => bill.id == billId);
    notifyListeners();
  }

  void duplicateLastBill() {
    if (_lastSale == null || _lastSale!.items.isEmpty) {
      return;
    }
    notifyListeners();
  }

  void clearCart() {
    _cartItems.clear();
    _discountPercentage = 0.0;
    notifyListeners();
  }

  Future<bool> processSale({
    required String cashierId,
    required String cashierName,
    required double amountReceived,
    required String paymentMethod,
    String notes = '',
    String customerName = '',
    String customerPhone = '',
    double cashAmount = 0,
    double cardAmount = 0,
  }) async {
    if (_cartItems.isEmpty) {
      return false;
    }

    try {
      // Resolve the picking plan for every line so the sale records accurate
      // batch prices and costs.
      final saleItems = <SaleItem>[];
      for (final item in _cartItems) {
        final plan = await _dbService.getFifoPlan(item.product, item.quantity);
        saleItems.add(SaleItem(
          productId: item.product.id,
          productName: item.product.name,
          price: plan.effectivePrice,
          quantity: item.quantity,
          discount: item.discount,
          costPrice: plan.weightedCost,
          batchNumber: plan.batchLabel,
          barcode: item.product.barcode,
          allocations: plan.allocations,
        ));
      }

      final sequence = await _dbService.getNextInvoiceSequence();
      final invoiceNumber = formatInvoiceNumber(sequence);

      final sale = Sale(
        cashierId: cashierId,
        cashierName: cashierName,
        invoiceNumber: invoiceNumber,
        items: saleItems,
        subtotal: subtotal,
        totalDiscount: totalDiscount,
        totalAmount: total,
        amountReceived: amountReceived,
        balance: amountReceived - total,
        paymentMethod: paymentMethod,
        notes: notes,
        customerName: customerName,
        customerPhone: customerPhone,
        cashAmount: cashAmount,
        cardAmount: cardAmount,
      );

      // Save the sale and deduct stock (FIFO) atomically.
      await _dbService.completeSale(sale, List<CartItem>.from(_cartItems));

      _lastSale = sale;

      // Deliver to the admin PC's server when available; otherwise it is
      // queued offline and flushed on the next connection.
      unawaited(ServerSync.instance.enqueueSale(sale.toMap()));

      // Push to the cloud so the Randil Grocery POS phone app sees it live.
      unawaited(SupabaseSyncService.instance.onSaleCompleted(sale));

      // Saving the bill already queued a full safety backup: a copy of the
      // database is written to the temp folder at once and then pushed to
      // Google Drive and GitHub in the background.

      clearCart();

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Sale>> getAllSales() async => _dbService.getAllSales();

  Future<Sale?> getSaleById(String id) async => _dbService.getSaleById(id);
}
