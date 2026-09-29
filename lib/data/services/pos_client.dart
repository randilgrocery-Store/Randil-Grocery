import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin HTTP client for talking to the admin PC's POS server.
class PosClient {
  PosClient(this.baseUrl);

  String baseUrl;

  static const Duration _timeout = Duration(seconds: 6);

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
      };

  Uri _url(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await http.get(_url(path)).timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error ${response.statusCode}: ${response.body}');
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final response = await http
        .post(_url(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception('Server error ${response.statusCode}: ${response.body}');
  }

  /// Returns the shop name on the server, or throws if unreachable/invalid.
  Future<(String shopName, String address, String phone)> fetchHealth() async {
    final json = await _get('/api/health');
    if (json['ok'] != true) {
      throw Exception('Server reports unhealthy');
    }
    return (
      json['shopName'] as String? ?? 'POS Server',
      json['shopAddress'] as String? ?? '',
      json['phone'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> fetchCatalog() async => _get('/api/catalog');

  Future<Map<String, dynamic>> fetchDailyReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromIso = Uri.encodeQueryComponent(from.toIso8601String());
    final toIso = Uri.encodeQueryComponent(to.toIso8601String());
    return _get('/api/report/daily?from=$fromIso&to=$toIso');
  }

  /// Pushes a completed sale (sale.toMap()) to the server. Idempotent server
  /// side: re-pushing the same sale id is harmless.
  Future<void> pushSale(Map<String, dynamic> saleMap) async =>
      _post('/api/sales', saleMap);
}