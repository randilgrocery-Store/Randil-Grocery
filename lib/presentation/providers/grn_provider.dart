import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';
import '../../data/models/goods_received_note.dart';
import '../../data/services/supabase_sync_service.dart';

class GrnProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  List<GoodsReceivedNote> _notes = [];
  bool _isLoading = false;

  List<GoodsReceivedNote> get notes => _notes;
  bool get isLoading => _isLoading;

  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();
    try {
      _notes = await _dbService.getAllGoodsReceivedNotes();
    } catch (e) {
      debugPrint('Error loading GRNs: $e');
      _notes = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> nextGrnNumber() => _dbService.getNextGrnNumber();

  Future<void> saveGrn(GoodsReceivedNote grn) async {
    await _dbService.receiveGoodsNote(grn);
    await loadNotes();
    SupabaseSyncService.instance.notifyDataChanged();
  }
}
