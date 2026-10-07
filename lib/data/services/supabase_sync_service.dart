import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/database_service.dart';
import '../../data/models/customer.dart';
import '../../data/models/expense.dart';
import '../../data/models/goods_received_note.dart';
import '../../data/models/product.dart';
import '../../data/models/refund_return.dart';
import '../../data/models/sale.dart';
import '../../data/models/supplier_payment.dart';
import '../config/cloud_config.dart';

/// Publishes shop data to Supabase so the "Randil Grocery POS" mobile app can
/// show live daily routines, sales, stock, customers, refunds, GRNs and
/// expenses.
///
/// The 15-minute background sync is INCREMENTAL (only rows newer than the last
/// successful sync are pushed) and also upserts one small `daily_routines` row
/// per shop day. A full push only happens on first enable and when "Save &
/// Sync Now" is pressed, which keeps Supabase free-tier egress very low.
///
/// Config lives in SharedPreferences (url + anon key + enabled) and defaults
/// to the project embedded in [CloudConfig].
class SupabaseSyncService {
  SupabaseSyncService._();

  static final SupabaseSyncService instance = SupabaseSyncService._();

  static const _kUrl = 'supabase_url';
  static const _kAnon = 'supabase_anon';
  static const _kEnabled = 'supabase_enabled';
  static const _kTokenBucket = 'supabase_last_sync';
  static const _kLastAttempt = 'supabase_last_attempt';
  static const _kLastError = 'supabase_last_error';

  final DatabaseService _db = DatabaseService();

  String _url = '';
  String _anonKey = '';
  bool _enabled = false;
  bool _syncing = false;
  DateTime? _lastSync;
  String? _lastError;
  Timer? _watcher;

  Dio? _client;

  String get url => _url;
  String get anonKey => _anonKey;
  bool get enabled => _enabled;
  bool get configured => _url.isNotEmpty && _anonKey.isNotEmpty;
  bool get syncing => _syncing;
  DateTime? get lastSync => _lastSync;
  String? get lastError => _lastError;

  /// Loads settings and kicks off the periodic background sync.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _url = prefs.getString(_kUrl) ?? CloudConfig.url;
    _anonKey = prefs.getString(_kAnon) ?? CloudConfig.anonKey;
    _enabled = prefs.getBool(_kEnabled) ?? true;
    _lastSync = _parse(prefs.getString(_kTokenBucket));
    _buildClient();
    _watcher?.cancel();
    _watcher = Timer.periodic(const Duration(minutes: 15), (_) {
      unawaited(syncAll());
    });
    if (_enabled && configured) {
      unawaited(syncAll());
    }
  }

  static DateTime? _parse(String? s) {
    if (s == null) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  Future<void> configure({
    required String url,
    required String anonKey,
    required bool enabled,
  }) async {
    _url = (url.trim().isEmpty ? CloudConfig.url : url.trim())
        .replaceAll(RegExp(r'\/+$'), '');
    _anonKey = anonKey.trim().isEmpty ? CloudConfig.anonKey : anonKey.trim();
    _enabled = enabled;
    _lastError = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUrl, _url);
    await prefs.setString(_kAnon, _anonKey);
    await prefs.setBool(_kEnabled, _enabled);
    _buildClient();
    if (_enabled && configured) {
      await syncAll(full: true);
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  void _buildClient() {
    if (!configured) {
      _client = null;
      return;
    }
    _client = Dio(
      BaseOptions(
        baseUrl: _url,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'apikey': _anonKey,
          'Authorization': 'Bearer $_anonKey',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  /// Called right after a sale is finalized in [SalesProvider.processSale].
  Future<void> onSaleCompleted(Sale sale) async {
    if (!_enabled || !configured) return;
    try {
      await _pushRows('sales_sync', [_saleRow(sale)]);
      await _pushDailyRoutines();
      await _setLastSync();
    } catch (e) {
      debugPrint('Supabase sale push failed: $e');
    }
  }

  /// Manual full sync (used by "Save & Sync Now"). Pushes everything and the
  /// current daily-route summary.
  Future<void> syncNow() => syncAll(full: true);

  Timer? _notifyTimer;

  /// Called whenever shop data changes (a GRN, expense, refund or wastage is
  /// saved). Coalesces bursts of writes into a single lightweight incremental
  /// push ~20s later, so the phone app sees stock and today's routine nearly
  /// in real time without spamming the network on every keystroke.
  void notifyDataChanged() {
    if (!_enabled || !configured) return;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(seconds: 20), () {
      unawaited(syncAll());
    });
  }

  /// Background sync (startup + every 15 minutes).
  ///
  /// When [full] is false only rows changed since the last successful sync
  /// are pushed (plus a 1-row `daily_routines` upsert), keeping free-tier
  /// egress to a minimum. The first run has no "last sync" marker so it pushes
  /// everything automatically.
  Future<void> syncAll({bool full = false}) async {
    if (!_enabled || !configured || _syncing) return;
    _syncing = true;
    _lastError = null;
    try {
      // Diagnostics that survive restarts, so a failed sync can be inspected
      // from the prefs file even when nobody is looking at the Settings UI.
      final attemptPrefs = await SharedPreferences.getInstance();
      await attemptPrefs
          .setString(_kLastAttempt, DateTime.now().toIso8601String());
      final since = full ? null : _lastSync;
      await _pushProducts(since: since, pushAllCustomers: full);
      await _pushRefunds(since: since);
      await _pushGrns(since: since);
      await _pushExpenses(since: since);
      await _pushSupplierPayments(since: since);
      await _pushSales(since: since);
      await _pushDailyRoutines();
      await _setLastSync();
      final okPrefs = await SharedPreferences.getInstance();
      await okPrefs.remove(_kLastError);
    } catch (e) {
      _lastError = e.toString();
      final errPrefs = await SharedPreferences.getInstance();
      await errPrefs.setString(_kLastError, _lastError!);
      debugPrint('Supabase syncAll failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _setLastSync() async {
    _lastSync = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenBucket, _lastSync!.toIso8601String());
  }

  // ── Daily routines ──────────────────────────────────────────────────────
  //
  // One small row per shop day, so the phone app can show the whole routine
  // (sales, payments, refunds, expenses, wastage, GRNs, top products) instead
  // of downloading every record. This is the main low-egress saving.

  Future<void> _pushDailyRoutines() async {
    final now = DateTime.now();
    // Push the last 7 days (not only today/yesterday) so the phone's 7-day
    // trend and week totals are complete even after days the POS was not
    // running. Rows upsert on (shop_id, date), so re-pushing is idempotent
    // and each empty day costs one tiny zero row.
    final rows = <Map<String, dynamic>>[];
    for (var i = 6; i >= 0; i--) {
      rows.add(await _buildDayRoutine(now.subtract(Duration(days: i))));
    }
    await _pushRows('daily_routines', rows);
  }

  Future<Map<String, dynamic>> _buildDayRoutine(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final next = start.add(const Duration(days: 1));
    bool inDay(DateTime t) =>
        !t.isBefore(start) && t.isBefore(next);

    var count = 0;
    var gross = 0.0, discount = 0.0, net = 0.0;
    var cash = 0.0, card = 0.0, mixed = 0.0;
    final byProduct = <String, double>{};

    for (final s in (await _db.getAllSales())) {
      if (!inDay(s.saleDate)) continue;
      count++;
      net += s.totalAmount;
      discount += s.totalDiscount;
      gross = net + discount;
      final m = s.paymentMethod.toLowerCase();
      if (m.contains('cash') && m.contains('card')) {
        mixed += s.totalAmount;
      } else if (m.contains('card')) {
        card += s.totalAmount;
      } else {
        cash += s.totalAmount;
      }
      for (final i in s.items) {
        byProduct[i.productName] =
            (byProduct[i.productName] ?? 0) + i.quantity;
      }
    }

    var refundSum = 0.0;
    for (final r in (await _db.getAllRefunds())) {
      if (inDay(r.requestDate)) refundSum += r.totalRefundAmount;
    }

    var expenseSum = 0.0;
    for (final e in (await _db.getAllExpenses())) {
      if (inDay(e.expenseDate)) expenseSum += e.amount;
    }

    var wastageSum = 0.0;
    for (final w in (await _db.getAllWastages())) {
      if (inDay(w.wastageDate)) wastageSum += w.lossValue;
    }

    var grnCount = 0;
    var grnValue = 0.0;
    for (final g in (await _db.getAllGoodsReceivedNotes())) {
      if (inDay(g.receivedDate)) {
        grnCount++;
        grnValue += g.total;
      }
    }

    final top = byProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final date = '${start.year}-${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';

    return {
      'shop_id': CloudConfig.shopId,
      'date': date,
      'sales_count': count,
      'gross': gross,
      'discount': discount,
      'net': net,
      'cash_amt': cash,
      'card_amt': card,
      'mixed_amt': mixed,
      'refunds_amt': refundSum,
      'expenses_amt': expenseSum,
      'wastage_amt': wastageSum,
      'grn_count': grnCount,
      'grn_value': grnValue,
      'top_products': jsonEncode([
        for (final e in top.take(5)) {'name': e.key, 'qty': e.value},
      ]),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  // ── Payload builders ─────────────────────────────────────────────────────

  Map<String, dynamic> _saleRow(Sale s) => {
        'id': s.id,
        'bill_number': s.invoiceNumber,
        'amount': s.totalAmount,
        'discount': s.totalDiscount,
        'tax': 0.0,
        'payment_method': s.paymentMethod,
        'items_count': s.items.length,
        'items_json': jsonEncode([
          for (final i in s.items)
            {
              'name': i.productName,
              'qty': i.quantity,
              'price': i.price,
              'line_total': i.total,
            }
        ]),
        'cashier': s.cashierName,
        'timestamp': s.saleDate.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _productRow(Product p, Map<String, String> catNames) => {
        'id': p.id,
        'name': p.name,
        'barcode': p.barcode,
        'category': catNames[p.categoryId] ?? '',
        'price': p.sellingPrice,
        'cost': p.buyingPrice,
        'stock': p.quantity,
        'unit': p.soldByWeight ? 'kg' : '',
        'low_stock_threshold': p.reorderLevel ?? 0,
        'updated_at': p.updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _customerRow(Customer c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'email': c.email,
        'loyalty_points': 0,
        'total_spend': c.totalSpent,
        'visits': c.totalTransactions,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> _grnRow(GoodsReceivedNote g) => {
        'id': g.id,
        'grn_number': g.grnNumber,
        'supplier_name': g.supplierName,
        'amount': g.total,
        'items_count': g.totalItems.round(),
        'items_json': jsonEncode([
          for (final i in g.items)
            {'name': i.productName, 'qty': i.quantity, 'cost': i.costPrice}
        ]),
        'created_by': g.receivedBy,
        'timestamp': g.receivedDate.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _expenseRow(Expense e) => {
        'id': e.id,
        'category': e.category,
        'amount': e.amount,
        'description': e.description.isEmpty ? e.notes : e.description,
        'payment_method': 'Cash',
        'created_by': e.recordedBy,
        'timestamp': e.expenseDate.toUtc().toIso8601String(),
      };

  Map<String, dynamic> _refundRow(RefundReturn r) => {
        'id': r.id,
        'original_bill': r.invoiceNumber,
        'amount': r.totalRefundAmount,
        'reason': r.items.isNotEmpty
            ? r.items.first.reason
            : r.notes,
        'refund_type': r.refundMethod,
        'cashier': r.requesterName,
        'status': r.status,
        'timestamp': r.requestDate.toUtc().toIso8601String(),
      };

  // ── Dataset pushes (incremental unless `since` is null) ──────────────────

  Future<void> _pushProducts({
    DateTime? since,
    required bool pushAllCustomers,
  }) async {
    final products =
        since == null ? await _db.getAllProducts() : await _changedProducts(since);
    final categories = await _db.getAllCategories();
    final catNames = <String, String>{
      for (final c in categories) c.id: c.name,
    };
    await _pushRows(
        'products_snapshot', products.map((p) => _productRow(p, catNames)));
    if (pushAllCustomers || since == null) {
      final customers = await _db.getAllCustomers();
      await _pushRows(
          'customers_sync', customers.map(_customerRow).toList(growable: false));
    }
  }

  Future<List<Product>> _changedProducts(DateTime since) async {
    final all = await _db.getAllProducts();
    return all.where((p) => p.updatedAt.isAfter(since)).toList();
  }

  Future<void> _pushSales({DateTime? since}) async {
    final sales = await _db.getAllSales();
    final rows = since == null
        ? sales
        : sales.where((s) => s.saleDate.isAfter(since));
    await _pushRows(
        'sales_sync', rows.map(_saleRow).toList(growable: false));
  }

  Future<void> _pushRefunds({DateTime? since}) async {
    final refunds = await _db.getAllRefunds();
    final rows = since == null
        ? refunds
        : refunds.where((r) => r.requestDate.isAfter(since));
    await _pushRows(
        'refunds_sync', rows.map(_refundRow).toList(growable: false));
  }

  Future<void> _pushGrns({DateTime? since}) async {
    final grns = await _db.getAllGoodsReceivedNotes();
    final rows = since == null
        ? grns
        : grns.where((g) => g.receivedDate.isAfter(since));
    await _pushRows(
        'supplier_grns_sync', rows.map(_grnRow).toList(growable: false));
  }

  Future<void> _pushExpenses({DateTime? since}) async {
    final expenses = await _db.getAllExpenses();
    final rows = since == null
        ? expenses
        : expenses.where((e) => e.expenseDate.isAfter(since));
    await _pushRows(
        'expenses_sync', rows.map(_expenseRow).toList(growable: false));
  }

  Future<void> _pushSupplierPayments({DateTime? since}) async {
    final payments = await _db.getAllSupplierPayments();
    final rows = since == null
        ? payments
        : payments.where((p) => p.paymentDate.isAfter(since));
    await _pushRows('supplier_payments_sync',
        rows.map(_supplierPaymentRow).toList(growable: false));
  }

  Map<String, dynamic> _supplierPaymentRow(SupplierPayment p) => {
        'id': p.id,
        'supplier_name': p.supplierName,
        'amount': p.amount,
        'method': p.method,
        'cheque_number': p.chequeNumber,
        'bank_name': p.bankName,
        'note': p.note,
        'timestamp': p.paymentDate.toUtc().toIso8601String(),
      };

  Future<void> _pushRows(String table, Iterable<Map<String, dynamic>> rows) async {
    final list = rows.toList(growable: false);
    if (list.isEmpty) return;
    final client = _client;
    if (client == null) return;
    try {
      await client.post(
        '/rest/v1/$table',
        data: list,
        options: Options(
          headers: const {'Prefer': 'resolution=merge-duplicates'},
        ),
      );
    } on DioException catch (e) {
      final detail = e.response == null
          ? 'Supabase $table push failed: $e'
          : 'Supabase $table push failed: HTTP ${e.response?.statusCode}: '
              '${e.response?.data}';
      throw StateError(detail);
    }
  }
}