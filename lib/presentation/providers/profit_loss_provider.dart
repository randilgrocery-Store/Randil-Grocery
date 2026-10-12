import 'package:flutter/material.dart';

import '../../data/database/database_service.dart';

/// Feeds the dashboard's Profit & Loss panel with one calculation that covers
/// every part of the shop: billing, goods received, wastage, refunds,
/// expenses and supplier payments.
class ProfitLossProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();

  Map<String, dynamic>? _data;
  bool _loading = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A refresh can still be in flight when the owning dashboard is torn down
  /// (window close, hot restart, or the widget test teardown). Notifying a
  /// disposed [ChangeNotifier] throws, so every async notify is guarded.
  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Map<String, dynamic>? get data => _data;
  bool get loading => _loading;

  /// True while the numbers on screen do not yet match the chosen range.
  bool get isStale {
    if (_data == null || _rangeStart == null || _rangeEnd == null) {
      return true;
    }
    return _rangeStart != _pendingStart || _rangeEnd != _pendingEnd;
  }

  DateTime? _pendingStart;
  DateTime? _pendingEnd;

  double d(String key) => (_data?[key] as num?)?.toDouble() ?? 0;
  int i(String key) => (_data?[key] as num?)?.toInt() ?? 0;

  Map<String, double> get expensesByCategory {
    final raw = _data?['expenseByCategory'];
    if (raw is Map) {
      return raw.map((key, value) =>
          MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0));
    }
    return const {};
  }

  Future<void> load(DateTime start, DateTime end) async {
    _pendingStart = start;
    _pendingEnd = end;
    // Same range already on screen: nothing to recalculate.
    if (_data != null && _rangeStart == start && _rangeEnd == end) {
      return;
    }
    _loading = true;
    _safeNotify();
    try {
      _data = await _dbService.getBusinessProfitLoss(start, end);
      _rangeStart = start;
      _rangeEnd = end;
    } catch (_) {
      _data = null;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Force a recalculation (used by pull-to-refresh).
  Future<void> refresh(DateTime start, DateTime end) async {
    _data = null;
    _rangeStart = null;
    await load(start, end);
  }
}
