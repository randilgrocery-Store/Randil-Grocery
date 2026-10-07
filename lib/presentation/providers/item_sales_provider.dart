import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';

/// Tracks item-wise sales data for the shop.
/// Provides detailed sales tracking per product/item.
class ItemSalesProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<ItemSalesData> _itemSales = [];
  bool _isLoading = false;
  DateTime? _lastUpdated;

  List<ItemSalesData> get itemSales => _itemSales;
  bool get isLoading => _isLoading;
  DateTime? get lastUpdated => _lastUpdated;

  /// Loads item-wise sales data for a specific date range.
  Future<void> loadItemSales(DateTime start, DateTime end) async {
    _isLoading = true;
    notifyListeners();

    try {
      final sales = await _dbService.getSalesByDateRange(start, end);
      final itemMap = <String, ItemSalesData>{};

      for (final sale in sales) {
        for (final item in sale.items) {
          final existing = itemMap[item.productId];
          if (existing != null) {
            existing.addSale(item.quantity, item.total, item.costPrice * item.quantity);
          } else {
            itemMap[item.productId] = ItemSalesData(
              productId: item.productId,
              productName: item.productName,
              barcode: item.barcode,
              totalQuantity: item.quantity,
              totalRevenue: item.total,
              totalCost: item.costPrice * item.quantity,
              saleCount: 1,
            );
          }
        }
      }

      _itemSales = itemMap.values.toList()
        ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

      _lastUpdated = DateTime.now();
    } catch (e) {
      debugPrint('Error loading item sales: $e');
      _itemSales = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Gets today's item-wise sales.
  Future<void> loadTodayItemSales() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    await loadItemSales(start, end);
  }

  /// Gets this month's item-wise sales.
  Future<void> loadMonthItemSales() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    await loadItemSales(start, end);
  }

  /// Gets the top selling items by revenue.
  List<ItemSalesData> getTopSellingItems(int limit) {
    return _itemSales.take(limit).toList();
  }

  /// Gets the top selling items by quantity.
  List<ItemSalesData> getTopSellingByQuantity(int limit) {
    final sorted = List<ItemSalesData>.from(_itemSales)
      ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
    return sorted.take(limit).toList();
  }

  /// Gets total revenue across all items.
  double get totalRevenue =>
      _itemSales.fold(0.0, (sum, item) => sum + item.totalRevenue);

  /// Gets total quantity sold across all items.
  double get totalQuantitySold =>
      _itemSales.fold(0.0, (sum, item) => sum + item.totalQuantity);

  /// Gets total profit across all items.
  double get totalProfit =>
      _itemSales.fold(0.0, (sum, item) => sum + item.profit);
}

/// Represents sales data for a single item/product.
class ItemSalesData {
  final String productId;
  final String productName;
  final String barcode;
  double totalQuantity;
  double totalRevenue;
  double totalCost;
  int saleCount;

  ItemSalesData({
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.totalQuantity,
    required this.totalRevenue,
    required this.totalCost,
    required this.saleCount,
  });

  double get profit => totalRevenue - totalCost;
  double get profitMargin =>
      totalRevenue > 0 ? (profit / totalRevenue) * 100 : 0;
  double get averagePrice =>
      totalQuantity > 0 ? totalRevenue / totalQuantity : 0;

  void addSale(double quantity, double revenue, double cost) {
    totalQuantity += quantity;
    totalRevenue += revenue;
    totalCost += cost;
    saleCount++;
  }
}
