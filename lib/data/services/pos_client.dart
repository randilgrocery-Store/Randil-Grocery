import 'dart:convert';
import 'dart:typed_data';

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

  /// Same as [_post] but returns the decoded response body.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(_url(path), headers: _jsonHeaders, body: jsonEncode(body))
        .timeout(_timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const <String, dynamic>{};
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Server error ${response.statusCode}: ${response.body}');
  }

  /// Cheap catalog fingerprint. Clients compare this to their last saved value
  /// to decide whether a full catalog re-pull is worth the bandwidth.
  Future<String> fetchCatalogRevision() async {
    final json = await _get('/api/catalog/revision');
    return json['revision'] as String? ?? '';
  }

  /// Downloads one product image by filename. Callers save the bytes into the
  /// local `product_images` folder so images are cached machine-side.
  Future<Uint8List> downloadImage(String name) async {
    // Encode: legacy filenames can contain spaces, brackets or non-ASCII,
    // and an unescaped `#`/`?`/space silently turns into a 404 (or a throw),
    // which is how a product ends up with a permanent grey placeholder.
    final response = await http
        .get(_url('/api/images/${Uri.encodeComponent(name)}'))
        .timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    throw Exception('Image error ${response.statusCode}');
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

  /// Cheap fingerprint of the shop's billing, expenses and wastage.
  Future<String> fetchFinancialRevision() async {
    final json = await _get('/api/mirror/revision');
    return json['revision'] as String? ?? '';
  }

  /// Billing/expenses/wastage rows written at or after [since]. Omit [since]
  /// and the server sends its bootstrap window (the last 7 days).
  Future<Map<String, dynamic>> fetchFinancialMirror(DateTime? since) async {
    final path = since == null
        ? '/api/mirror'
        : '/api/mirror?since=${Uri.encodeQueryComponent(since.toIso8601String())}';
    return _get(path);
  }

  /// Sends this machine's own records and its stock movements up to the shop
  /// server so its reports and quantities count them too. Matched by id (and
  /// applied as a delta for stock), so re-sending is harmless.
  ///
  /// [resetToken] is the report-reset stamp this PC last saw. If it is older
  /// than the server's, the server refuses the push (so a terminal that has not
  /// yet caught up with a reset cannot resurrect the wiped history) and the
  /// client pulls the reset before re-sending.
  Future<Map<String, dynamic>> pushMirror({
    required Map<String, dynamic> tables,
    List<Map<String, dynamic>> stockDeltas = const [],
    String resetToken = '',
  }) =>
      _postJson('/api/mirror', {
        'tables': tables,
        'stockDeltas': stockDeltas,
        'resetToken': resetToken,
      });

  /// Asks the shop server to wipe the report history. Stock, products and
  /// images are not touched.
  Future<Map<String, dynamic>> resetFinancials() =>
      _postJson('/api/mirror/reset', const {});

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