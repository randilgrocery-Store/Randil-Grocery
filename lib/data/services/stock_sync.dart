import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_service.dart';
import '../models/cart_item.dart';

/// Tracks how far this terminal's stock has drifted from the server's copy.
///
/// The server owns stock (it is the only machine that moves FIFO batches), so a
/// client never sends an absolute quantity — that would clobber a bill the
/// server rang up in the same second. Instead it keeps a *baseline*: the
/// quantities it last received from the server. Any local movement (wastage,
/// goods received, repack, a refund restock or a manual correction) shows up as
/// a difference from that baseline, and only the difference is forwarded.
///
/// A bill this terminal rang up itself is the one movement the server already
/// applies (through the sale queue), so [noteLocalSale] folds it into the
/// baseline and keeps it out of the delta.
class StockSync {
  StockSync._();

  static const String _baseKey = 'stock_sync_base';
  static const double _epsilon = 0.0001;

  static Future<Map<String, double>> _loadBase() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_baseKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) =>
            MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveBase(Map<String, double> base) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseKey, jsonEncode(base));
  }

  /// Re-anchors the baseline to a fresh catalog pull. Only the products in the
  /// payload move; a locally created product keeps whatever it had.
  static Future<void> setFromCatalog(
    Iterable<Map<String, dynamic>> products,
  ) async {
    final base = await _loadBase();
    var changed = false;
    for (final product in products) {
      final id = product['id'] as String?;
      if (id == null) continue;
      base[id] = (product['quantity'] as num?)?.toDouble() ?? 0;
      changed = true;
    }
    if (changed) await _saveBase(base);
  }

  /// Folds a bill this terminal just rang up into the baseline, so the queue
  /// (which already moves the server's stock) is the only place it counts.
  static Future<void> noteLocalSale(Iterable<CartItem> items) async {
    final base = await _loadBase();
    if (base.isEmpty) return; // No baseline yet; the first pull will set one.
    var changed = false;
    for (final item in items) {
      final current = base[item.product.id];
      if (current == null) continue;
      base[item.product.id] = current - item.stockQuantity;
      changed = true;
    }
    if (changed) await _saveBase(base);
  }

  /// Stock this terminal moved that the server has not been told about yet.
  /// Empty when everything is in step or no catalog has been pulled.
  static Future<List<Map<String, dynamic>>> pendingDeltas() async {
    final base = await _loadBase();
    if (base.isEmpty) return const [];
    final products = await DatabaseService().getAllProducts();
    final deltas = <Map<String, dynamic>>[];
    for (final product in products) {
      final anchor = base[product.id];
      if (anchor == null) continue;
      final delta = product.quantity - anchor;
      if (delta.abs() < _epsilon) continue;
      deltas.add({'id': product.id, 'delta': delta});
    }
    return deltas;
  }

  /// Marks every pending movement as sent, once the server confirmed it.
  static Future<void> commitDeltas() async {
    final products = await DatabaseService().getAllProducts();
    await _saveBase({
      for (final product in products) product.id: product.quantity,
    });
  }
}
