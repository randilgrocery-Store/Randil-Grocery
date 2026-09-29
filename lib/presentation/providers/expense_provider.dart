import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/expense.dart';
import '../../data/services/supabase_sync_service.dart';

class ExpenseProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  List<Expense> _expenses = [];
  bool _isLoading = false;

  List<Expense> get expenses => _expenses;
  bool get isLoading => _isLoading;

  Future<void> loadExpenses() async {
    _isLoading = true;
    notifyListeners();
    try {
      _expenses = await _dbService.getAllExpenses();
    } catch (e) {
      debugPrint('Error loading expenses: $e');
      _expenses = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addExpense(Expense expense) async {
    await _dbService.insertExpense(expense);
    await loadExpenses();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<void> deleteExpense(String id) async {
    await _dbService.deleteExpense(id);
    await loadExpenses();
    SupabaseSyncService.instance.notifyDataChanged();
  }

  Future<List<Expense>> getExpensesByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      _dbService.getExpensesByDateRange(start, end);

  Future<Map<String, dynamic>> getProfitReport(
    DateTime start,
    DateTime end,
  ) async =>
      _dbService.getProfitReport(start, end);
}
