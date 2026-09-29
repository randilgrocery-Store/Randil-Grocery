import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database/database_service.dart';
import '../../data/models/shop_settings.dart';
import '../../data/services/network_sync.dart';
import '../../data/services/pos_client.dart';
import '../../data/services/pos_discovery.dart';
import '../../data/services/pos_server.dart';

enum NetworkMode { standalone, server, client }

enum ClientConnectState { idle, connecting, connected, offline }

/// Coordinates the LAN link:
///   - Server mode (admin PC): runs [PosServer] so cashiers/mobile can reach
///     the single live database.
///   - Client mode (cashier PC): auto-discovers the server, connects, keeps
///     the health ping alive, pulls the catalog, and flushes queued sales.
class NetworkProvider extends ChangeNotifier {
  final PosServer _server = PosServer();
  final PosDiscovery _discovery = PosDiscovery();
  Timer? _pingTimer;
  ShopSettings _settings = ShopSettings();
  int _syncGeneration = 0;

  NetworkMode mode = NetworkMode.standalone;
  ClientConnectState connectState = ClientConnectState.idle;
  bool serverRunning = false;
  String serverStatus = 'Stopped';

  /// Display name (shop name) of the connected server.
  String? serverName;
  String? serverUrl;
  String? serverLocalAddress;
  DateTime? lastSyncAt;
  String lastError = '';
  int pendingCount = 0;

  /// Invoked after a successful catalog sync so callers can reload providers.
  VoidCallback? onCatalogSynced;

  /// Incremented every time the catalog is refreshed.
  int get syncGeneration => _syncGeneration;

  bool get isConnected =>
      mode == NetworkMode.server ||
      (mode == NetworkMode.client && connectState == ClientConnectState.connected);

  String get statusLabel {
    switch (mode) {
      case NetworkMode.server:
        return serverRunning ? 'Server running' : 'Server stopped';
      case NetworkMode.client:
        switch (connectState) {
          case ClientConnectState.connected:
            return 'Connected to $serverName';
          case ClientConnectState.connecting:
            return 'Looking for the shop server…';
          case ClientConnectState.offline:
            return 'Offline — server not found';
          case ClientConnectState.idle:
            return 'Not connected';
        }
      case NetworkMode.standalone:
        return 'Standalone (offline)';
    }
  }

  /// Boots networking according to the saved settings. Safe to call once at
  /// app startup (and again after settings change).
  Future<void> init() async {
    try {
      final settings = await DatabaseService().getShopSettings();
      _settings = settings;
      await applySettings(settings);
    } catch (e) {
      // Database not ready yet or networking failed — stay standalone.
      lastError = 'Network init failed: $e';
      mode = NetworkMode.standalone;
    }
  }

  Future<void> applySettings(ShopSettings settings) async {
    _settings = settings;
    pendingCount = (await ServerSync.instance.pendingSales()).length;

    final newMode =
        settings.isServerMode ? NetworkMode.server : NetworkMode.client;
    if (newMode == NetworkMode.server) {
      await stopClient();
      mode = NetworkMode.server;
      await startServer();
    } else {
      await stopServer();
      mode = NetworkMode.client;
      await startClient();
    }
    notifyListeners();
  }

  // ============== SERVER MODE ==============

  Future<void> startServer() async {
    try {
      await _server.start(_settings);
      serverRunning = true;
      serverStatus = _server.status;
      serverLocalAddress = await _server.localHttpUrl();
      // This PC is the single source of truth; the local DB already has all
      // sales, so nothing to push. Still flush anything queued from earlier.
      unawaited(ServerSync.instance.flushPending(url: serverLocalAddress));
    } catch (e) {
      serverRunning = false;
      serverStatus = 'Failed to start: $e';
      lastError = e.toString();
    }
    notifyListeners();
  }

  Future<void> stopServer() async {
    await _server.stop();
    serverRunning = false;
    serverStatus = _server.status;
    ServerSync.instance.clearConnection();
  }

  // ============== CLIENT MODE ==============

  Future<void> startClient() async {
    connectState = ClientConnectState.connecting;
    notifyListeners();

    _discovery.onDiscovered = (pos) {
      unawaited(_tryConnectTo(pos));
    };

    if (_settings.useAutoDiscovery) {
      await _discovery.start();
    } else {
      _discovery.stop();
    }

    // Immediately try the saved fallback IP (covers routers that block
    // multicast and lets us connect before announcements arrive).
    if (_settings.serverIpFallback.trim().isNotEmpty) {
      final hostRaw = _settings.serverIpFallback.trim();
      // Support http://host:port or just IP (port = settings.networkPort).
      final (host, port) = _parseFallback(hostRaw);
      final fallback = await _discovery.probeFallback(host, port ?? _settings.networkPort);
      if (fallback != null) {
        unawaited(_tryConnectTo(fallback));
      }
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (connectState == ClientConnectState.connected) {
        _pingConnectedServer();
      } else {
        _retryDiscovery();
      }
    });
  }

  (String, int?) _parseFallback(String raw) {
    var host = raw.trim();
    var port = _settings.networkPort;
    final scheme = 'http://';
    if (host.startsWith(scheme)) {
      host = host.substring(scheme.length);
    }
    final slash = host.indexOf('/');
    if (slash >= 0) {
      host = host.substring(0, slash);
    }
    final colon = host.lastIndexOf(':');
    if (colon > 0) {
      final parsedPort = int.tryParse(host.substring(colon + 1));
      if (parsedPort != null) {
        port = parsedPort;
        host = host.substring(0, colon);
      }
    }
    return (host, port);
  }

  Future<void> stopClient() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _discovery.stop();
    connectState = ClientConnectState.idle;
    serverName = null;
    serverUrl = null;
    ServerSync.instance.clearConnection();
  }

  Future<void> _tryConnectTo(DiscoveredPos pos) async {
    if (connectState == ClientConnectState.connected &&
        serverUrl == pos.baseUrl) {
      return;
    }
    if (pos.baseUrl == null) {
      return;
    }
    final client = PosClient(pos.baseUrl!);
    try {
      final health = await client.fetchHealth();
      serverUrl = pos.baseUrl;
      serverName = health.$1;
      connectState = ClientConnectState.connected;
      lastError = '';
      notifyListeners();

      // Fresh catalog so the cashier terminal always sells at server prices.
      await _syncCatalog(client);
      await ServerSync.instance.flushPending(url: serverUrl);
      pendingCount = (await ServerSync.instance.pendingSales()).length;
      notifyListeners();
    } catch (e) {
      lastError = 'Server at ${pos.sourceAddress.address} not responding: $e';
      notifyListeners();
    }
  }

  Future<void> _syncCatalog(PosClient client) async {
    try {
      final catalog = await client.fetchCatalog();
      final products = (catalog['products'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final categories = (catalog['categories'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final customers = (catalog['customers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      await DatabaseService().upsertCatalog(
        products: products,
        categories: categories,
        customers: customers,
      );
      _syncGeneration++;
      lastSyncAt = DateTime.now();
      onCatalogSynced?.call();
    } catch (e) {
      lastError = 'Catalog sync failed: $e';
    }
  }

  Future<void> _pingConnectedServer() async {
    final url = serverUrl;
    if (url == null) {
      connectState = ClientConnectState.offline;
      notifyListeners();
      return;
    }
    try {
      final health = await PosClient(url).fetchHealth();
      if (health.$1 != serverName) {
        serverName = health.$1;
      }
      lastError = '';
    } catch (_) {
      // Server went away (admin PC off / WiFi dropped). Keep the last known
      // url so we can quietly come back when the server returns.
      connectState = ClientConnectState.offline;
      ServerSync.instance.clearConnection();
      notifyListeners();
    }
  }

  Future<void> _retryDiscovery() async {
    if (_settings.useAutoDiscovery) {
      // Probe the group again.
      for (final pos in _discovery.servers) {
        unawaited(_tryConnectTo(pos));
      }
    }
    if (_settings.serverIpFallback.trim().isNotEmpty) {
      final (host, port) =
          _parseFallback(_settings.serverIpFallback.trim());
      final pos = await _discovery.probeFallback(
        host,
        port ?? _settings.networkPort,
      );
      if (pos != null) {
        unawaited(_tryConnectTo(pos));
      }
    }
  }

  /// Manual "find server now" action from the settings screen.
  Future<void> reconnectNow() async {
    if (mode != NetworkMode.client) {
      return;
    }
    connectState = ClientConnectState.connecting;
    notifyListeners();
    await _retryDiscovery();
    if (connectState == ClientConnectState.connecting) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (connectState == ClientConnectState.connecting) {
        connectState = ClientConnectState.offline;
        lastError = 'No server answered on this network';
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _discovery.stop();
    _server.stop();
    super.dispose();
  }
}