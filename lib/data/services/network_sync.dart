import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pos_client.dart';

/// Connects the POS UI to the [PosClient] when a server is available. Sales
/// are pushed fire-and-forget from the sale flow; anything not yet delivered
/// is persisted to an offline queue and re-sent once the server shows up.
class ServerSync {
  ServerSync._();
  static final ServerSync instance = ServerSync._();

  static const String _pendingKey = 'pending_push_sales';

  PosClient? _client;

  /// Set by the network layer when a server is reachable/unreachable.
  String? baseUrl;
  bool get connected => baseUrl != null;

  String? lastError;

  Future<List<Map<String, dynamic>>> pendingSales() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? const [];
    return raw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> _persistPending(List<Map<String, dynamic>> sales) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _pendingKey,
      sales.map((e) => jsonEncode(e)).toList(),
    );
  }

  /// Register a completed sale for delivery. Sends immediately when a server
  /// is connected, otherwise queues it for the next connection.
  Future<void> enqueueSale(Map<String, dynamic> saleMap) async {
    if (_client != null) {
      final ok = await _tryPush(saleMap);
      if (ok) {
        return;
      }
    }
    final pending = await pendingSales();
    pending.add(saleMap);
    await _persistPending(pending);
  }

  /// Called after (re)connecting so queued sales are delivered.
  Future<void> flushPending({String? url}) async {
    if (url != null) {
      _client = PosClient(url);
      baseUrl = url;
    }
    if (_client == null) {
      return;
    }
    final pending = await pendingSales();
    if (pending.isEmpty) {
      return;
    }
    final remaining = <Map<String, dynamic>>[];
    for (final sale in pending) {
      final ok = await _tryPush(sale);
      if (!ok) {
        remaining.add(sale);
      }
    }
    await _persistPending(remaining);
  }

  void clearConnection() {
    _client = null;
    baseUrl = null;
  }

  Future<bool> _tryPush(Map<String, dynamic> saleMap) async {
    try {
      await _client!.pushSale(saleMap);
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}