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
  Future<List<DailyRoutine>> fetchRoutines({int limit = 31}) async {
    final uri = Uri.parse('$_base/daily_routines').replace(queryParameters: {
      'select': '*',
      'shop_id': 'eq.${CloudConfig.shopId}',
      'order': 'date.desc',
      'limit': '$limit',
    });
    final list = await _getList(uri);
    return [
      for (final row in list) DailyRoutine.fromJson(row),
    ];
  }

  /// The most recent completed bills.
  Future<List<SaleRow>> fetchRecentSales({int limit = 30}) async {
    final uri = Uri.parse('$_base/sales_sync').replace(queryParameters: {
      'select': '*',
      'order': 'timestamp.desc',
      'limit': '$limit',
    });
    final list = await _getList(uri);
    return [for (final row in list) SaleRow.fromJson(row)];
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