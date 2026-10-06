import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/cloud_config.dart';
import '../models/daily_routine.dart';
import '../models/sale_row.dart';

/// Thin REST client for the shop's Supabase project.
///
/// Uses the publishable anon key (same one the desktop POS is pre-configured
/// with). The schema grants anon read on the dashboard tables, so the owner's
/// phone reads real data with zero login friction.
class SupabaseClient {
  SupabaseClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _base = '${CloudConfig.url}/rest/v1';

  Map<String, String> get _headers => {
        'apikey': CloudConfig.anonKey,
        'Authorization': 'Bearer ${CloudConfig.anonKey}',
        'Accept': 'application/json',
      };

  static const _timeout = Duration(seconds: 20);

  /// The shop's daily summaries, newest first.
  ///
  /// Only the columns the dashboard actually renders are selected instead of
  /// `*`, which keeps a full phone refresh well under 10 KB.
  Future<List<DailyRoutine>> fetchRoutines({int limit = 14}) async {
    final uri = Uri.parse('$_base/daily_routines').replace(queryParameters: {
      'select': _routineColumns,
      'shop_id': 'eq.${CloudConfig.shopId}',
      'order': 'date.desc',
      'limit': '$limit',
    });
    final list = await _getList(uri);
    return [
      for (final row in list) DailyRoutine.fromJson(row),
    ];
  }

  /// The routine columns the dashboard needs. Deliberately narrow: the phone
  /// never downloads rows it does not paint.
  static const String _routineColumns =
      'date,sales_count,gross,discount,net,cash_amt,card_amt,mixed_amt,'
      'refunds_amt,expenses_amt,wastage_amt,grn_count,grn_value,top_products';

  /// The most recent completed bills — light rows only. The per-item JSON is
  /// the biggest chunk of every `sales_sync` row, so it is fetched on demand
  /// in [fetchSaleDetail] only when the owner taps a bill.
  Future<List<SaleRow>> fetchRecentSales({int limit = 15}) async {
    final uri = Uri.parse('$_base/sales_sync').replace(queryParameters: {
      'select': 'id,bill_number,amount,payment_method,items_count,timestamp',
      'order': 'timestamp.desc',
      'limit': '$limit',
    });
    final list = await _getList(uri);
    return [for (final row in list) SaleRow.fromJson(row)];
  }

  /// Everything about one bill (its item lines + cashier). One tiny row,
  /// fetched only when the owner opens a bill.
  Future<Map<String, dynamic>?> fetchSaleDetail(String id) async {
    final uri = Uri.parse('$_base/sales_sync').replace(queryParameters: {
      'select': 'items_json,cashier',
      'id': 'eq.$id',
      'limit': '1',
    });
    final list = await _getList(uri);
    return list.isEmpty ? null : list.first;
  }

  /// Releases the underlying HTTP client's pooled connections.
  void close() => _client.close();

  Future<List<Map<String, dynamic>>> _getList(Uri uri) async {
    final response = await _client.get(uri, headers: _headers).timeout(_timeout);
    if (response.statusCode != 200) {
      throw SupabaseException(
        'Supabase ${response.statusCode}: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const SupabaseException('Unexpected Supabase response shape');
    }
    return [for (final e in decoded) e as Map<String, dynamic>];
  }
}

class SupabaseException implements Exception {
  const SupabaseException(this.message);

  final String message;

  @override
  String toString() => 'SupabaseException: $message';
}

/// True when the failure is likely "no internet / server unreachable".
bool isNetworkError(Object error) =>
    error is SocketException ||
    error is http.ClientException ||
    error is SupabaseException && error.message.contains('SocketException');