import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/wastage.dart';
import '../../data/services/supabase_sync_service.dart';

class WastageProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<Wastage> _wastages = [];
  bool _isLoading = false;

  List<Wastage> get wastages => _wastages;
  bool get isLoading => _isLoading;

  Future<void> loadWastages() async {
    _isLoading = true;
    notifyListeners();
    try {
      _wastages = await _dbService.getAllWastages();
    } catch (e) {
      debugPrint('Error loading wastages: $e');
      _wastages = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Wastage?> addWastage({
    required String productId,
    required String productName,
    required double quantity,
    required String reason,
    String batchId = '',
    String batchNumber = '',
    String notes = '',
    String recordedBy = '',
    DateTime? wastageDate,
  }) async {
    final wastage = await _dbService.recordWastage(
      productId: productId,
      productName: productName,
      quantity: quantity,
      reason: reason,
      batchId: batchId,
      batchNumber: batchNumber,
      notes: notes,
      recordedBy: recordedBy,
      wastageDate: wastageDate,
    );
    await loadWastages();
    SupabaseSyncService.instance.notifyDataChanged();
    return wastage;
  }

  Future<Map<String, dynamic>> getWastageReport(
    DateTime start,
    DateTime end,
  ) async =>
      _dbService.getWastageReport(start, end);
}