import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/held_bill.dart';
import '../../data/models/product.dart';
import '../../data/models/sale.dart';
import '../../data/models/shopping_bag.dart';
import '../../data/services/network_sync.dart';
import '../../data/services/stock_sync.dart';
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
  ///
  /// [loose] adds single pieces taken from the box (a product whose only
  /// barcode is printed on the box) at the per-piece price instead of whole
  /// boxes. A box line and a loose line for the same product are kept apart in
  /// the cart.
  Future<void> addToCart(
    Product product, {
    double quantity = 1,
    bool loose = false,
  }) async {
    if (product.quantity <= 0) {
      return; // Don't add out of stock items
    }

    final ppb = product.piecesPerBox > 0 ? product.piecesPerBox : 1;
    final isLoose = loose && ppb > 1;
    final lineId = isLoose ? '${product.id}#loose' : product.id;

    final existingIndex = _cartItems.indexWhere((item) => item.id == lineId);

    // Whole boxes and single pieces are always whole: a box line can never hold
    // a fraction of a box, and a loose line can never hold a fraction of a
    // piece (stock is snapped onto piece boundaries after each sale).
    double capToWhole(double qty) =>
        product.isBreakBulk ? qty.floorToDouble() : qty;

    final double desiredQuantity;
    if (existingIndex >= 0) {
      final updated = _cartItems[existingIndex];
      // Stock left for this line, converted back to the line's selling unit.
      final maxAddable = capToWhole(isLoose
          ? (product.quantity - updated.stockQuantity) * ppb
          : product.quantity - updated.stockQuantity);
      if (maxAddable <= 0) {
        return;
      }
      final add = quantity.clamp(0.0, maxAddable);
      updated.quantity += add;
      desiredQuantity = updated.quantity;
    } else {
      final maxAddable = capToWhole(
          isLoose ? product.quantity * ppb : product.quantity);
      desiredQuantity = quantity.clamp(0.0, maxAddable);
      if (desiredQuantity <= 0) return;
      _cartItems.add(
        CartItem(
          id: lineId,
          product: product,
          quantity: desiredQuantity,
          unitPrice: isLoose ? product.loosePrice : product.sellingPrice,
          loose: isLoose,
          piecesPerBox: ppb,
        ),
      );
    }

    // Resolve the FIFO price for the whole line. When the line spans several
    // batches with different prices this is the weighted average, exactly what
    // processSale charges. A loose line keeps the per-piece price the shop set,
    // so it is not re-priced from the box batches.
    final index = _cartItems.indexWhere((i) => i.id == lineId);
    if (index >= 0 && !_cartItems[index].loose) {
      try {
        final plan =
            await _dbService.getFifoPlan(product, _cartItems[index].stockQuantity);
        _cartItems[index].unitPrice = plan.effectivePrice;
      } catch (_) {
        // Keep the current price if the plan cannot be resolved.
      }
    }

    notifyListeners();
  }

  /// Adds a shopping-bag line at the bag's set price (Rs 3 / 5 / 10 / 20...).
  ///
  /// Bags are not grocery products: the line carries a lightweight stub product
  /// purely so the cart, bill, reports and LAN mirror treat it like any other
  /// line, while the bag's own stock / usage is handled by the
  /// `shopping_bags` / `shopping_bag_usage` tables (see
  /// `DatabaseService.completeSale`). The price charged is always the bag's
  /// price [bag.price], never a batch/FIFO price.
  Future<void> addBagToCart(ShoppingBag bag, double quantity) async {
    if (bag.quantity <= 0 || quantity <= 0) return;
    final lineId = 'bag:${bag.id}';

    final index = _cartItems.indexWhere((i) => i.id == lineId);
    if (index >= 0) {
      final updated = _cartItems[index];
      final maxAddable =
          (bag.quantity - updated.quantity).clamp(0.0, double.infinity);
      if (maxAddable <= 0) return;
      final add = quantity.clamp(0.0, maxAddable);
      if (add <= 0) return;
      updated.quantity += add;
      notifyListeners();
      return;
    }

    final add = quantity.clamp(0.0, bag.quantity);
    if (add <= 0) return;

    final stub = Product(
      name: bag.label,
      barcode: 'BAG-${bag.id}',
      categoryId: '',
      buyingPrice: bag.buyingPrice,
      sellingPrice: bag.price,
      quantity: bag.quantity,
    );
    _cartItems.add(CartItem(
      id: lineId,
      product: stub,
      quantity: add,
      unitPrice: bag.price,
      isBag: true,
      bagId: bag.id,
      bagPrice: bag.price,
      bagCost: bag.buyingPrice,
    ));
    notifyListeners();
  }

  void removeFromCart(String lineId) {
    _cartItems.removeWhere((item) => item.id == lineId);
    notifyListeners();
  }

  Future<void> updateCartItemQuantity(String lineId, double quantity) async {
    final index = _cartItems.indexWhere((item) => item.id == lineId);
    if (index < 0) {
      return;
    }
    if (quantity <= 0) {
      _cartItems.removeAt(index);
      notifyListeners();
      return;
    }

    final item = _cartItems[index];
    // Stock left for this line, after what the other cart lines already hold.
    var otherStock = 0.0;
    for (final other in _cartItems) {
      if (other.id != lineId && other.product.id == item.product.id) {
        otherStock += other.stockQuantity;
      }
    }
    final stockLeft = item.product.quantity - otherStock;
    final ppb = item.piecesPerBox > 0 ? item.piecesPerBox : 1;
    final rawMax = item.loose ? stockLeft * ppb : stockLeft;
    // Break-bulk lines are always expressed in whole boxes / whole pieces.
    final maxLine = item.product.isBreakBulk ? rawMax.floorToDouble() : rawMax;
    final validQuantity =
        maxLine <= 0 ? 0.0 : quantity.clamp(0.0, maxLine);
    if (validQuantity <= 0) {
      _cartItems.removeAt(index);
      notifyListeners();
      return;
    }
    item.quantity = validQuantity;

    if (item.loose) {
      item.unitPrice = item.product.loosePrice;
    } else {
      try {
        final plan =
            await _dbService.getFifoPlan(item.product, item.stockQuantity);
        item.unitPrice = plan.effectivePrice;
      } catch (_) {
        // Keep the current price if the plan cannot be resolved.
      }
    }

    notifyListeners();
  }

  void updateCartItemDiscount(String lineId, double discount) {
    final index = _cartItems.indexWhere((item) => item.id == lineId);
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
        if (item.isBag) {
          // Shopping-bag line: charged at the bag price, costed at the bag's
          // buying price. No FIFO plan - the bag owns its own stock table.
          saleItems.add(SaleItem(
            productId: 'bag:${item.bagId}',
            productName: item.product.name,
            price: item.unitPrice,
            quantity: item.quantity,
            discount: item.discount,
            costPrice: item.bagCost,
            batchNumber: '',
            barcode: item.product.barcode,
            piecesPerBox: 1,
          ));
          continue;
        }
        final plan =
            await _dbService.getFifoPlan(item.product, item.stockQuantity);
        // FIFO gives the cost of a whole box; a loose line records the cost of
        // the single piece it actually took.
        final costPerUnit = item.loose && item.piecesPerBox > 0
            ? plan.weightedCost / item.piecesPerBox
            : plan.weightedCost;
        saleItems.add(SaleItem(
          productId: item.product.id,
          productName: item.product.name,
          price: item.unitPrice,
          quantity: item.quantity,
          discount: item.discount,
          costPrice: costPerUnit,
          batchNumber: plan.batchLabel,
          barcode: item.product.barcode,
          allocations: plan.allocations,
          loose: item.loose,
          piecesPerBox: item.piecesPerBox,
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

      // Keep this bill out of the LAN stock delta: the queue below already
      // moves the server's stock, so forwarding it again would double-count.
      unawaited(StockSync.noteLocalSale(_cartItems));

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
