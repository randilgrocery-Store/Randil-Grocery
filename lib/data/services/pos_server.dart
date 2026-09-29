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
      ..get('/api/catalog', _wrap(_catalog))
      ..get('/api/customers', _wrap(_customers))
      ..get('/api/report/daily', _wrap(_dailyReport))
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
    return jsonResponse(200, {
      'ok': true,
      'products': products.map((e) => e.toMap()).toList(),
      'categories': categories.map((e) => e.toMap()).toList(),
      'customers': customers.map((e) => e.toMap()).toList(),
      'syncedAt': DateTime.now().toIso8601String(),
    });
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
    return jsonResponse(200, {
      'ok': true,
      'invoiceNumber': recorded.invoiceLabel,
      'saleDate': recorded.saleDate.toIso8601String(),
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