import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/sale.dart';

class ReportsProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  Map<String, dynamic>? _dailyReport;
  Map<String, dynamic>? _monthlyReport;

  Map<String, dynamic>? get dailyReport => _dailyReport;
  Map<String, dynamic>? get monthlyReport => _monthlyReport;

  Future<void> generateDailyReport(DateTime date) async {
    try {
      _dailyReport = await _dbService.getDailySalesReport(date);
      notifyListeners();
    } catch (e) {
      debugPrint('Error generating daily report: $e');
      // Set default empty report
      _dailyReport = {
        'date': date,
        'totalRevenue': 0.0,
        'totalTransactions': 0,
        'totalItemsSold': 0,
        'itemsBreakdown': {},
        'sales': [],
      };
      notifyListeners();
    }
  }

  Future<void> generateMonthlyReport(int year, int month) async {
    try {
      _monthlyReport = await _dbService.getMonthlySalesReport(year, month);
      notifyListeners();
    } catch (e) {
      debugPrint('Error generating monthly report: $e');
      // Set default empty report
      _monthlyReport = {
        'year': year,
        'month': month,
        'totalRevenue': 0.0,
        'totalTransactions': 0,
        'totalItemsSold': 0,
        'itemsBreakdown': {},
        'bestSellingItems': <MapEntry<String, int>>[],
        'dailyRevenue': <int, double>{},
        'sales': [],
      };
      notifyListeners();
    }
  }

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async =>
      _dbService.getSalesByDateRange(start, end);

  /// Get top selling products
  List<MapEntry<String, int>> getTopSellingItems(int limit) {
    if (_monthlyReport == null) return [];
    final items = _monthlyReport!['bestSellingItems'] as List? ?? [];
    return items.cast<MapEntry<String, int>>().take(limit).toList();
  }

  /// Get daily revenue for chart
  Map<int, double> getDailyRevenueData() {
    if (_monthlyReport == null) return {};
    return (_monthlyReport!['dailyRevenue'] as Map).cast<int, double>();
  }

  /// Calculate total revenue for date range
  double getTotalRevenue(List<Sale> sales) =>
      sales.fold(0, (sum, sale) => sum + sale.totalAmount);

  /// Calculate average transaction value
  double getAverageTransactionValue(List<Sale> sales) {
    if (sales.isEmpty) return 0;
    return getTotalRevenue(sales) / sales.length;
  }

  /// Get total items sold
  int getTotalItemsSold(List<Sale> sales) => sales.fold(0, (sum, sale) {
        final itemCount =
            sale.items.fold(0, (sum, item) => sum + item.quantity);
        return sum + itemCount;
      });
}
