import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/database/database_service.dart';
import '../../data/models/reload_card.dart';

/// Value ledger for reload (top-up) credit.
///
/// The shop buys reload value from an ISP ("Buy") and sells it to customers in
/// any amount ("Sell"). Every row in [cards] is one transaction: status
/// `bought` for purchases, status `sold` for sales (which link back to the
/// purchase batch via [ReloadCard.batchId]). Remaining value and profit are
/// derived, never stored, so they can never drift out of sync.
class ReloadCardProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  List<ReloadCard> _cards = [];
  bool _isLoading = false;

  List<ReloadCard> get cards => _cards;
  bool get isLoading => _isLoading;

  // ---- Ledger totals (derived) ----

  List<ReloadCard> get boughtCards =>
      _cards.where((c) => c.status == 'bought').toList();
  List<ReloadCard> get soldCards =>
      _cards.where((c) => c.status == 'sold').toList();

  /// Total reload value bought from the ISP.
  double get totalBoughtValue =>
      _round(_bought.fold(0, (sum, c) => sum + c.value));

  /// Total reload value sold to customers.
  double get totalSoldValue =>
      _round(_sold.fold(0, (sum, c) => sum + c.value));

  /// Still-available value = bought minus sold.
  double get remainingValue =>
      _round(totalBoughtValue - totalSoldValue);

  /// Profit on reload = selling value minus the cost of that sold value.
  double get totalProfit => _round(
      _sold.fold(0, (sum, c) => sum + (c.value - c.cost)));

  /// What the shop actually paid for all the reload bought so far.
  double get totalPurchaseCost =>
      _round(_bought.fold(0, (sum, c) => sum + c.cost));

  int get boughtCount => _bought.length;
  int get soldCount => _sold.length;

  List<ReloadCard> get _bought => boughtCards;
  List<ReloadCard> get _sold => soldCards;

  /// Reload value still available inside a specific bought batch.
  double remainingFor(ReloadCard batch) {
    final soldFromBatch = _sold
        .where((c) => c.batchId == batch.id)
        .fold(0.0, (sum, c) => sum + c.value);
    return _round(batch.value - soldFromBatch);
  }

  /// Bought batches that still have value left to sell.
  List<ReloadCard> get availableBatches =>
      _bought.where((c) => remainingFor(c) > 0.005).toList();

  bool isSoldOut(ReloadCard batch) => remainingFor(batch) <= 0.005;

  /// Wastage/description helper for the screen: sold-off batches shown as used.
  bool get hasAnyCards => _cards.isNotEmpty;

  // ---- Actions ----

  Future<void> loadCards() async {
    _isLoading = true;
    notifyListeners();
    try {
      _cards = await _db.getAllReloadCards();
    } catch (e) {
      debugPrint('Error loading reload cards: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Records buying reload value from the ISP.
  Future<ReloadCard> buyReload({
    required String supplier,
    required double value,
    required double cost,
    String? cardNumber,
    String? notes,
  }) async {
    final card = ReloadCard(
      id: const Uuid().v4(),
      cardNumber: (cardNumber ?? '').trim().isNotEmpty
          ? cardNumber!.trim()
          : 'BUY-${_serial()}',
      supplier: supplier.trim(),
      value: _round(value),
      cost: _round(cost),
      status: 'bought',
      createdAt: DateTime.now(),
      notes: notes,
    );
    await _db.insertReloadCard(card);
    _cards.insert(0, card);
    notifyListeners();
    return card;
  }

  /// Records selling reload value to a customer, deducting it from [batch].
  ///
  /// The sale's cost basis is the batch's weighted cost, so
  /// [totalProfit] stays exact even when only part of a purchase is sold.
  Future<ReloadCard> sellReload({
    required ReloadCard batch,
    required double amount,
    String? customerPhone,
    String? customerName,
    String? notes,
  }) async {
    if (batch.status != 'bought') {
      throw StateError('You can only sell from a bought reload batch.');
    }
    final remaining = remainingFor(batch);
    if (amount <= 0) {
      throw ArgumentError('Enter a valid amount to sell.');
    }
    if (amount > remaining + 0.005) {
      throw StateError(
          'Only ${remaining.toStringAsFixed(2)} reload value is left in this '
          'batch. Sold amount cannot exceed it.');
    }
    final allocatedCost =
        batch.value > 0 ? batch.cost * (amount / batch.value) : 0.0;
    final sale = ReloadCard(
      id: const Uuid().v4(),
      cardNumber: batch.cardNumber,
      batchId: batch.id,
      supplier: batch.supplier,
      value: _round(amount),
      cost: _round(allocatedCost),
      status: 'sold',
      customerPhone: customerPhone,
      customerName: customerName,
      createdAt: DateTime.now(),
      usedAt: DateTime.now(),
      notes: notes,
    );
    await _db.insertReloadCard(sale);
    _cards.insert(0, sale);
    notifyListeners();
    return sale;
  }

  Future<void> deleteCard(String id) async {
    await _db.deleteReloadCard(id);
    _cards.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  static double _round(double v) =>
      (v * 100).roundToDouble() / 100.0;

  /// A short, collision-free serial for receipts/records: date + counter.
  static String _serial() {
    final now = DateTime.now();
    final stamp = '${now.year % 100}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return stamp;
  }
}