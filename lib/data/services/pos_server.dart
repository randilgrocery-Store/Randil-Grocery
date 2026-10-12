import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import '../database/database_service.dart';
import '../models/sale.dart';
import '../models/shop_settings.dart';
import 'pos_protocol.dart';
import '../../presentation/widgets/product_image.dart';

/// The admin PC's built-in server. Hosts the single live database over a small
/// HTTP API that cashier terminals (and later the mobile app) talk to, and
/// announces itself on the LAN so clients can find it automatically.
class PosServer {
  final DatabaseService _dbService = DatabaseService();

  HttpServer? _httpServer;
  RawDatagramSocket? _discoverySocket;
  Timer? _announceTimer;
  ShopSettings _settings = ShopSettings();
  String _status = 'Stopped';

  /// Notified whenever another terminal pushes a sale into this server, so the
  /// host machine's own UI can refresh its stock/dashboard immediately.
  void Function()? onSaleRecorded;

  /// Fired when another machine pushes money rows up (expenses/wastage) or
  /// wipes the reports, so this server's own screens repaint immediately
  /// instead of waiting for the next local action.
  void Function()? onMirrorChanged;

  /// True while the server is listening and answering requests.
  bool get isRunning => _httpServer != null;

  /// Human readable status for the settings screen.
  String get status => _status;

  /// Local URL clients on the LAN can reach this server at, e.g.
  /// http://192.168.1.10:8180
  Future<String?> localHttpUrl() async {
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final address = addr.address;
          if (address.startsWith('169.254.')) {
            continue; // No internet connection / APIPA link-local address.
          }
          return 'http://$address:${_settings.networkPort}';
        }
      }
    } catch (_) {
      // Fall through.
    }
    return null;
  }

  /// Starts the HTTP server plus the UDP discovery beacon. Throws when the
  /// port is already in use (another POS instance is already the server).
  Future<void> start(ShopSettings settings) async {
    if (_httpServer != null) {
      return;
    }
    _settings = settings;

    final router = Router()
      ..get('/api/health', _wrap(_health))
      ..get('/api/catalog/revision', _wrap(_catalogRevision))
      ..get('/api/catalog', _wrap(_catalog))
      ..get('/api/images/<name>', _wrapImage)
      ..get('/api/customers', _wrap(_customers))
      ..get('/api/report/daily', _wrap(_dailyReport))
      ..get('/api/mirror/revision', _wrap(_mirrorRevision))
      ..get('/api/mirror', _wrap(_mirror))
      ..post('/api/mirror', _wrap(_pushMirror))
      ..post('/api/mirror/reset', _wrap(_resetMirror))
      ..get('/api/guide', _wrap(_guide))
      ..post('/api/sales', _wrap(_pushSale))
      ..all('/<ignored|.*>', _notFound);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addHandler(router.call);

    _httpServer = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      _settings.networkPort,
    );

    _status = 'Listening on port ${_settings.networkPort}';
    _startBeacon();

    // Surface the http port to right now (settings may have been edited after
    // the listener bound, so keep the effective port authoritative).
    final effectivePort = _httpServer!.port;
    if (effectivePort != _settings.networkPort) {
      _settings = _settings.copyWith(networkPort: effectivePort);
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    await _httpServer?.close(force: true);
    _httpServer = null;
    _status = 'Stopped';
  }

  // ============== HTTP API ==============

  Response jsonResponse(int status, Map<String, dynamic> body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );

  Handler _wrap(Future<Response> Function(Request) inner) => (Request req) async {
        try {
          return await inner(req);
        } catch (e) {
          return jsonResponse(500, {'ok': false, 'error': e.toString()});
        }
      };

  Response _notFound(Request req) =>
      jsonResponse(404, {'ok': false, 'error': 'Not found'});

  Future<Response> _health(Request req) async {
    final settings = await _dbService.getShopSettings();
    return jsonResponse(200, {
      'ok': true,
      'app': 'Randil Grocery POS',
      'shopName': settings.shopName,
      'shopAddress': settings.address,
      'phone': settings.phone,
      'serverTime': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _catalog(Request req) async {
    final products = await _dbService.getAllProducts();
    final categories = await _dbService.getAllCategories();
    final customers = await _dbService.getAllCustomers();
    final suppliers = await _dbService.getAllSuppliers(includeInactive: true);
    final settings = await _dbService.getShopSettings();
    return jsonResponse(200, {
      'ok': true,
      'products': products.map((e) => e.toMap()).toList(),
      'categories': categories.map((e) => e.toMap()).toList(),
      'customers': customers.map((e) => e.toMap()).toList(),
      'suppliers': suppliers.map((e) => e.toMap()).toList(),
      // Label-scale layout is configured on the admin PC and copied to every
      // terminal, so the counter PC decodes scale labels without extra setup.
      'scale': {
        'enabled': settings.scaleBarcodeEnabled,
        'prefix': settings.scaleBarcodePrefix,
        'length': settings.scaleBarcodeLength,
        'itemLength': settings.scaleBarcodeItemLength,
        'priceMode': settings.scaleBarcodePriceMode,
        'checkDigit': settings.scaleBarcodeCheckDigit,
      },
      'syncedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Response> _catalogRevision(Request req) async {
    final revision = await _dbService.catalogRevision();
    return jsonResponse(200, {'ok': true, 'revision': revision});
  }

  Future<Response> _wrapImage(Request req, String name) async {
    try {
      return await _image(req, name);
    } catch (e) {
      return jsonResponse(500, {'ok': false, 'error': e.toString()});
    }
  }

  /// Serves a product image stored in the app's own image folder.
  ///
  /// Clients download these over LAN during catalog sync so product pictures
  /// appear on every terminal. The name is a bare filename; path separators
  /// are stripped so a crafted request can never escape the image folder.
  Future<Response> _image(Request req, String name) async {
    // shelf matches against the still-percent-encoded path, so undo the client's
    // encoding first (legacy filenames can contain spaces or brackets), then
    // strip any separator so a crafted `%2F` can never escape the image folder.
    var decoded = name;
    try {
      decoded = Uri.decodeComponent(decoded);
    } catch (_) {
      // Not valid escapes — treat the raw segment as the filename.
    }
    final safeName = decoded.split(RegExp(r'[/\\]')).last;
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      return jsonResponse(404, {'ok': false, 'error': 'Not found'});
    }

    File? file = await _findImageFile(safeName);
    if (file == null) {
      return jsonResponse(404, {'ok': false, 'error': 'Not found'});
    }
    final bytes = await file.readAsBytes();
    return Response.ok(bytes, headers: {
      'content-type': _contentTypeFor(safeName),
      'cache-control': 'public, max-age=31536000',
    });
  }

  /// Locates [name] on this PC: first the normal image folder, then — for rows
  /// whose imagePath still points at an absolute path from an older build —
  /// wherever the database says the picture lives.
  Future<File?> _findImageFile(String name) async {
    final folder =
        File('${ProductImageStore.directory().path}${Platform.pathSeparator}$name');
    if (folder.existsSync()) return folder;

    // Older rows store a full path (e.g. a Downloads file). Match by basename.
    try {
      final products = await _dbService.getAllProducts();
      for (final p in products) {
        final stored = p.imagePath;
        if (stored == null || stored.isEmpty) continue;
        if (stored.split(RegExp(r'[/\\]')).last != name) continue;
        final resolved = ProductImageStore.resolve(stored);
        if (resolved != null && File(resolved).existsSync()) {
          return File(resolved);
        }
        if (File(stored).existsSync()) return File(stored);
      }
    } catch (_) {
      // DB unavailable — 404 below.
    }
    return null;
  }

  static String _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }

  Future<Response> _customers(Request req) async {
    final customers = await _dbService.getAllCustomers();
    return jsonResponse(
      200,
      {'ok': true, 'customers': customers.map((e) => e.toMap()).toList()},
    );
  }

  Future<Response> _dailyReport(Request req) async {
    final fromRaw = req.url.queryParameters['from'];
    final toRaw = req.url.queryParameters['to'];
    if (fromRaw == null || toRaw == null) {
      return jsonResponse(400, {
        'ok': false,
        'error': 'Provide from and to ISO date parameters',
      });
    }

    final from = DateTime.tryParse(fromRaw);
    final to = DateTime.tryParse(toRaw);
    if (from == null || to == null) {
      return jsonResponse(400, {'ok': false, 'error': 'Invalid date'});
    }

    final sales = await _dbService.getSalesByDateRange(
      from,
      to.add(const Duration(days: 1)),
    );

    var gross = 0.0;
    var discount = 0.0;
    var net = 0.0;
    final byMethod = <String, double>{};
    for (final sale in sales) {
      gross += sale.subtotal;
      discount += sale.totalDiscount;
      net += sale.totalAmount;
      byMethod[sale.paymentMethod] =
          (byMethod[sale.paymentMethod] ?? 0.0) + sale.totalAmount;
    }

    return jsonResponse(200, {
      'ok': true,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'sales': sales.length,
      'gross': gross,
      'discount': discount,
      'net': net,
      'byPaymentMethod': byMethod,
    });
  }

  Future<Response> _guide(Request req) =>
      Future.value(jsonResponse(200, {
        'ok': true,
        'guide': 'Endpoints: /api/health, /api/catalog, /api/customers, '
            '/api/report/daily?from=ISO&to=ISO, POST /api/sales',
      }));

  Future<Response> _pushSale(Request req) async {
    final body = await req.readAsString();
    final payload = jsonDecode(body);
    if (payload is! Map<String, dynamic>) {
      return jsonResponse(400, {'ok': false, 'error': 'Invalid sale payload'});
    }

    final sale = Sale.fromMap(payload);
    final recorded = await _dbService.recordRemoteSale(sale);
    onSaleRecorded?.call(); // Refresh this machine's stock/dashboard UI.
    return jsonResponse(200, {
      'ok': true,
      'invoiceNumber': recorded.invoiceLabel,
      'saleDate': recorded.saleDate.toIso8601String(),
    });
  }

  /// Cheap fingerprint of the shop's billing/expenses/wastage. A terminal
  /// polls this and only pulls rows when it actually moved.
  Future<Response> _mirrorRevision(Request req) async {
    return jsonResponse(200, {
      'ok': true,
      'revision': await _dbService.financialRevision(),
    });
  }

  /// Everything written at or after `since`, so a terminal's reports, stock,
  /// reload cards, refunds, repacks, goods received and supplier payments all
  /// match this machine's without re-downloading history on every check.
  Future<Response> _mirror(Request req) async {
    final raw = req.url.queryParameters['since'];
    DateTime? since;
    if (raw != null && raw.isNotEmpty) {
      since = DateTime.tryParse(raw);
      if (since == null) {
        return jsonResponse(400, {'ok': false, 'error': 'Invalid since'});
      }
    }

    // Captured *before* reading, so the watermark the caller derives from it
    // can never skip a row written while this request was in flight.
    final serverNow = DateTime.now();
    final rows = await _dbService.mirrorRowsSince(since);
    return jsonResponse(200, {
      'ok': true,
      'serverNow': serverNow.toIso8601String(),
      'resetToken': await _dbService.reportsResetAt(),
      'tables': rows,
    });
  }

  /// Accepts records written on the *other* machine.
  ///
  /// Bills are not sent here: they arrive through `/api/sales`, which also
  /// moves stock, so routing them twice would double-count quantities. Every
  /// other table (expenses, wastage, reload cards, refunds, repack runs, goods
  /// received, purchase orders and supplier payments) is merged verbatim, and
  /// any stock the other till moved travels separately as a delta.
  Future<Response> _pushMirror(Request req) async {
    final body = await req.readAsString();
    final payload = jsonDecode(body);
    if (payload is! Map<String, dynamic>) {
      return jsonResponse(400, {'ok': false, 'error': 'Invalid mirror payload'});
    }

    // Refuse a push from a terminal that has not caught up with the latest
    // report reset. Without this, a PC still holding the old bills/expenses/
    // wastage/reload rows could send them straight back, undoing the reset.
    final clientToken = payload['resetToken'] as String? ?? '';
    final serverToken = await _dbService.reportsResetAt() ?? '';
    if (clientToken != serverToken) {
      return jsonResponse(200, {
        'ok': true,
        'stale': true,
        'applied': 0,
        'stockMoved': 0,
        'resetToken': serverToken,
        'serverNow': DateTime.now().toIso8601String(),
      });
    }

    final rawTables = payload['tables'];
    final applied = rawTables is Map
        ? await _dbService.applyMirror(Map<String, dynamic>.from(rawTables))
        : 0;

    final stockDeltas = (payload['stockDeltas'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final stockMoved = await _dbService.applyStockDeltas(stockDeltas);

    if (applied > 0) {
      onMirrorChanged?.call();
    }
    // Stock moved: refresh this machine's own product grid and figures too.
    if (stockMoved > 0) {
      onSaleRecorded?.call();
    }

    return jsonResponse(200, {
      'ok': true,
      'applied': applied,
      'stockMoved': stockMoved,
      'serverNow': DateTime.now().toIso8601String(),
    });
  }

  /// Clears the shop's report history on request. Stock, products, images and
  /// customers are untouched, and the reset is stamped so every terminal wipes
  /// its mirrored copy on its next sync instead of pulling the old rows back.
  Future<Response> _resetMirror(Request req) async {
    final cleared = await _dbService.clearFinancialHistory();
    onMirrorChanged?.call();
    return jsonResponse(200, {
      'ok': true,
      'cleared': cleared,
      'resetAt': await _dbService.reportsResetAt(),
    });
  }

  // ============== UDP DISCOVERY BEACON ==============

  void _startBeacon() {
    try {
      final socket = RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        PosProtocol.discoveryPort,
        reuseAddress: true,
      );
      _prepareBeacon(socket);
    } catch (_) {
      _status = 'HTTP running, but discovery failed '
          '(UDP port ${PosProtocol.discoveryPort} unavailable)';
    }
  }

  void _prepareBeacon(Future<RawDatagramSocket> socketFuture) {
    socketFuture.then((socket) {
      _discoverySocket = socket;
      socket.multicastHops = 1;
      socket.multicastLoopback = false;
      try {
        socket.joinMulticast(PosProtocol.multicastGroup);
      } catch (_) {
        // Multicast may be blocked on some networks; clients still reach us
        // through the saved fallback IP.
      }

      final announce = PosProtocol.announce(
        _settings.shopName,
        _settings.networkPort,
      );
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final text = utf8.decode(datagram.data, allowMalformed: true);
            if (text == PosProtocol.hello()) {
              // Reply directly to the caller so it learns our real address
              // even when multicast is filtered.
              socket.send(
                utf8.encode(PosProtocol.here(
                  _settings.shopName,
                  _settings.networkPort,
                )),
                datagram.address,
                datagram.port,
              );
            }
          }
        }
      });

      _announceTimer = Timer.periodic(
        const Duration(seconds: PosProtocol.announceIntervalSeconds),
        (_) {
          try {
            socket.send(
              utf8.encode(announce),
              PosProtocol.multicastGroup,
              PosProtocol.discoveryPort,
            );
          } catch (_) {
            // Ignore transient send failures.
          }
        },
      );
    }).catchError((Object _) {
      _status = 'HTTP running, but discovery failed to bind';
    });
  }
}