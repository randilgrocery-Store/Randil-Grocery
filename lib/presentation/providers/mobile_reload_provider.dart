import 'package:flutter/material.dart';

/// Tracks mobile reload events - when data is reloaded from the server
/// or when the mobile app refreshes its data.
class MobileReloadProvider extends ChangeNotifier {
  int _reloadCount = 0;
  DateTime? _lastReloadTime;
  String _lastReloadSource = '';
  final List<MobileReloadEvent> _reloadHistory = [];

  int get reloadCount => _reloadCount;
  DateTime? get lastReloadTime => _lastReloadTime;
  String get lastReloadSource => _lastReloadSource;
  List<MobileReloadEvent> get reloadHistory => List.unmodifiable(_reloadHistory);

  /// Records a mobile reload event.
  void recordReload(String source) {
    _reloadCount++;
    _lastReloadTime = DateTime.now();
    _lastReloadSource = source;

    _reloadHistory.add(MobileReloadEvent(
      timestamp: DateTime.now(),
      source: source,
    ));

    // Keep only the last 100 events
    if (_reloadHistory.length > 100) {
      _reloadHistory.removeAt(0);
    }

    notifyListeners();
  }

  /// Clears the reload history.
  void clearHistory() {
    _reloadCount = 0;
    _lastReloadTime = null;
    _lastReloadSource = '';
    _reloadHistory.clear();
    notifyListeners();
  }
}

/// Represents a single mobile reload event.
class MobileReloadEvent {
  final DateTime timestamp;
  final String source;

  MobileReloadEvent({
    required this.timestamp,
    required this.source,
  });

  @override
  String toString() =>
      'MobileReloadEvent(${timestamp.toIso8601String()}, source: $source)';
}
