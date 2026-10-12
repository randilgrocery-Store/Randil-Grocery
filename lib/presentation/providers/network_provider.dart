import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/database_service.dart';
import '../../data/models/shop_settings.dart';
import '../../data/services/network_sync.dart';
import '../../data/services/pos_client.dart';
import '../../data/services/pos_discovery.dart';
import '../../data/services/pos_server.dart';
import '../../data/services/stock_sync.dart';
import '../widgets/product_image.dart';

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
  Timer? _catalogRefreshTimer;
  ShopSettings _settings = ShopSettings();
  int _syncGeneration = 0;

  /// SharedPreferences key holding the last catalog revision this PC applied.
  static const String _catalogRevisionKey = 'last_catalog_revision';
  static const String _expectedImagesKey = 'expected_product_images';

  /// SharedPreferences keys for the financial (sales/expenses/wastage) mirror.
  static const String _mirrorRevisionKey = 'last_financial_revision';
  static const String _mirrorWatermarkKey = 'financial_mirror_watermark';

  /// Where the next upward push of this machine's expenses/wastage starts, and
  /// the report-reset stamp last seen from the server.
  static const String _pushWatermarkKey = 'financial_push_watermark';
  static const String _resetTokenKey = 'reports_reset_token';

  /// How far back a mirror pull re-reads rows it already has. The gap is the
  /// window in which a row could be committed while a request is in flight;
  /// re-sending is harmless because rows are replaced by primary key, and it
  /// guarantees nothing is ever silently skipped.
  static const Duration _mirrorOverlap = Duration(minutes: 1);

  /// How often a connected client re-checks the server for catalog changes.
  /// How often the client re-checks the server for changes. This is a tiny
  /// ~100-byte request (not a catalog download), so a short interval keeps the
  /// stock looking live without spending WiFi data.
  static const Duration _catalogRefreshInterval = Duration(seconds: 20);

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

  /// Invoked when this PC is the server and another terminal pushes a sale in,
  /// so the host's own stock/dashboard refreshes without a manual reload.
  VoidCallback? onRemoteSaleReceived;

  /// Incremented every time the catalog is refreshed.
  int get syncGeneration => _syncGeneration;

  /// Bumped every time another terminal pushes a sale into this server.
  /// Screens showing money (Reports, dashboard) watch this to reload their
  /// figures instead of showing stale profit/loss.
  int remoteSaleTick = 0;

  /// Bumped when mirrored billing rows land on this client, so Reports and the
  /// dashboard repaint with the shop-wide figures instead of this machine's.
  int financialTick = 0;

  /// Invoked after mirrored money rows were applied (client mode only).
  VoidCallback? onFinancialsSynced;

  /// When this machine last pulled the shop's money figures. Surfaced in
  /// Settings so "is it syncing?" has a visible answer.
  DateTime? lastFinancialSyncAt;

  /// Guards the money cycle so the heartbeat and the catalog refresh can never
  /// run two overlapping push/pull passes.
  bool _moneyBusy = false;

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
      // A sale pushed in from another terminal should refresh this machine's
      // own stock and dashboard right away.
      _server.onSaleRecorded = () {
        remoteSaleTick++;
        notifyListeners();
        onRemoteSaleReceived?.call();
      };
      // Money rows pushed up by a terminal (or a report reset) must repaint
      // this PC's own dashboard and Reports too.
      _server.onMirrorChanged = () {
        financialTick++;
        notifyListeners();
        onFinancialsSynced?.call();
      };
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

    // Try the saved address over plain HTTP first: it works even when the
    // router or firewall drops UDP discovery packets (very common on shop
    // networks). Without this a terminal whose UDP probe fails would never
    // connect at all — no catalog, no images, no live figures.
    if (_settings.serverIpFallback.trim().isNotEmpty) {
      unawaited(_tryHttpFallback());

      final hostRaw = _settings.serverIpFallback.trim();
      // Support http://host:port or just IP (port = settings.networkPort).
      final (host, port) = _parseFallback(hostRaw);
      unawaited(_discovery
          .probeFallback(host, port ?? _settings.networkPort)
          .then((fallback) {
        if (fallback != null) {
          unawaited(_tryConnectTo(fallback));
        }
      }));
    }

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (connectState == ClientConnectState.connected) {
        _pingConnectedServer();
        // Money rides the heartbeat too, so a bill or an expense recorded on
        // either PC reaches the other within ~10 seconds.
        final url = serverUrl;
        if (url != null) {
          unawaited(_syncMoney(PosClient(url)));
        }
      } else {
        _retryDiscovery();
      }
    });

    // Live catalog refresh: while connected, re-check the server's revision
    // every so often and pull changes automatically (stock moved on the admin
    // PC shows up on this terminal without the user touching anything).
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer =
        Timer.periodic(_catalogRefreshInterval, (_) async {
      final url = serverUrl;
      if (url == null ||
          connectState != ClientConnectState.connected ||
          mode != NetworkMode.client) {
        return;
      }
      try {
        // Re-send any sale that failed to push: without this a single failed
        // POST would leave the revenue stuck in the queue, so the admin PC's
        // profit report would never include it.
        await ServerSync.instance.flushPending();
        await _syncCatalog(PosClient(url));
        await _syncMoney(PosClient(url));
        pendingCount = (await ServerSync.instance.pendingSales()).length;
        notifyListeners();
      } catch (_) {
        // Next tick retries; a transient blip must not kill the timer.
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
    _catalogRefreshTimer?.cancel();
    _catalogRefreshTimer = null;
    await _discovery.stop();
    connectState = ClientConnectState.idle;
    serverName = null;
    serverUrl = null;
    ServerSync.instance.clearConnection();
  }

  Future<void> _tryConnectTo(DiscoveredPos pos) async {
    final baseUrl = pos.baseUrl;
    if (baseUrl == null) {
      return;
    }
    try {
      final health = await PosClient(baseUrl).fetchHealth();
      await _establishConnection(baseUrl, health);
    } catch (e) {
      // Only surface this when we have nothing better to show — a discovery
      // packet from an unreachable address must not mask a healthy link.
      if (connectState != ClientConnectState.connected) {
        lastError = 'Server at ${pos.sourceAddress.address} not responding: $e';
        notifyListeners();
      }
    }
  }

  /// Direct HTTP probe of the saved fallback address (`192.168.8.122:8080`).
  ///
  /// Deliberately skips UDP discovery: on shop networks the firewall or router
  /// often allows plain HTTP but drops multicast/unicast discovery packets, and
  /// a terminal that only ever tried UDP would stay disconnected forever —
  /// which is exactly what "no images and no live data" looks like. Costs one
  /// tiny `/api/health` request.
  Future<void> _tryHttpFallback() async {
    final raw = _settings.serverIpFallback.trim();
    if (raw.isEmpty) {
      return;
    }
    final (host, port) = _parseFallback(raw);
    if (host.isEmpty) {
      return;
    }
    final baseUrl = 'http://$host:${port ?? _settings.networkPort}';
    if (connectState == ClientConnectState.connected &&
        serverUrl == baseUrl) {
      return;
    }
    try {
      final health = await PosClient(baseUrl).fetchHealth();
      await _establishConnection(baseUrl, health);
    } catch (_) {
      if (connectState != ClientConnectState.connected) {
        lastError = 'No answer from $baseUrl — check WiFi and firewall';
        notifyListeners();
      }
    }
  }

  /// Shared connect path, whether the server was found by discovery or dialed
  /// directly by URL.
  Future<void> _establishConnection(
    String baseUrl,
    (String, String, String) health,
  ) async {
    if (connectState == ClientConnectState.connected &&
        serverUrl == baseUrl) {
      return;
    }
    serverUrl = baseUrl;
    serverName = health.$1;
    connectState = ClientConnectState.connected;
    lastError = '';
    notifyListeners();

    // Push this machine's queued sales FIRST: the server deducts its stock
    // then, so the catalog pulled below already carries this terminal's own
    // sales. (The other order let a stale server quantity overwrite the local
    // deduction until the next refresh.)
    await ServerSync.instance.flushPending(url: serverUrl);
    // Fresh catalog so the cashier terminal always sells at server prices.
    await _syncCatalog(PosClient(baseUrl));
    // Then the shop's money: push this machine's own expenses/wastage up, and
    // pull everything back so daily income and profit are the whole shop's —
    // not just the bills this terminal rang up itself.
    await _syncMoney(PosClient(baseUrl));
    pendingCount = (await ServerSync.instance.pendingSales()).length;
    notifyListeners();
    // Make sure the UI repaints even if this connection finished before the
    // screens registered their reload callback (startup race).
    onCatalogSynced?.call();
  }

  Future<void> _syncCatalog(PosClient client) async {
    try {
      // Cheap check first: if the server's catalog hasn't changed since our
      // last sync, skip the full download entirely (the images and rows are
      // already cached locally) — this is what keeps WiFi usage tiny.
      String? revision;
      try {
        revision = await client.fetchCatalogRevision();
      } catch (_) {
        revision = null; // Older server without revision support: always pull.
      }

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_catalogRevisionKey);

      if (revision != null && revision.isNotEmpty && last == revision) {
        // No row changes — reuse the local catalog (cheap, saves WiFi). Pictures
        // are still checked, using the local product table as the source of
        // truth: an upgrade from an earlier build has a saved revision but no
        // recorded image list, and trusting that list alone left every
        // placeholder on that machine for good.
        final names = await _localImageNames();
        final healed = await _syncImages(client, names);
        lastSyncAt = DateTime.now();
        if (healed > 0) {
          onCatalogSynced?.call(); // Re-render the freshly cached pictures.
        }
        return;
      }

      // Push this terminal's own changes (including any stock it already moved)
      // before overwriting the local catalog below, so a fresh pull can never
      // erase a movement still waiting to reach the server.
      if (!await _pushLocalChanges(client)) {
        lastError = 'Catalog sync deferred: unsent changes still queued';
        return;
      }

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
      final suppliers = (catalog['suppliers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      await DatabaseService().upsertCatalog(
        products: products,
        categories: categories,
        customers: customers,
        suppliers: suppliers,
      );
      // Adopt the admin PC's label-scale layout (server → counter), so the
      // cashier machine decodes scale labels with no local setup.
      final scale = catalog['scale'];
      if (scale is Map) {
        await DatabaseService().applyScaleSettingsFromServer(
          Map<String, dynamic>.from(scale),
        );
      }
      // Re-anchor the stock baseline to the server's quantities we just pulled.
      await StockSync.setFromCatalog(products);

      // Pull any product pictures this machine does not have yet (cached once).
      final wanted = _imageNamesFrom(products);
      await _syncImages(client, wanted);
      // Remember what we need so the no-change path can still retry misses.
      await prefs.setStringList(_expectedImagesKey, wanted.toList());

      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(_catalogRevisionKey, revision);
      }
      _syncGeneration++;
      lastSyncAt = DateTime.now();
      onCatalogSynced?.call();
    } catch (e) {
      lastError = 'Catalog sync failed: $e';
    }
  }

  /// One sync cycle: push this terminal's own records and stock movements up to
  /// the server, then pull the whole shop's data back down.
  ///
  /// Runs on the 10-second heartbeat, so a bill, an expense, a wastage record, a
  /// reload card or a repack entered on either PC shows on the other within a
  /// few seconds. Both halves are gated by a cheap revision/watermark check, so
  /// an idle link costs a few hundred bytes — not the whole day's data.
  Future<void> _syncMoney(PosClient client) async {
    if (_moneyBusy) return;
    _moneyBusy = true;
    try {
      await _pushLocalChanges(client);
      await _syncFinancials(client);
    } catch (e) {
      // Both halves swallow their own errors; this is belt-and-braces so an
      // unawaited call from the heartbeat can never throw.
      lastError = 'Sync failed: $e';
    } finally {
      _moneyBusy = false;
    }
  }

  /// The in-flight upward push, shared by every caller so the 10s money
  /// heartbeat and the 20s catalog refresh can never advance the watermark at
  /// the same time. A second caller awaits the first push instead of being told
  /// (wrongly) that there are still unsent changes.
  Future<bool>? _pushFuture;

  /// Sends everything this machine recorded since the last successful push —
  /// expenses, wastage, reload cards, refunds, repack runs, goods received,
  /// purchase orders and supplier payments — plus any stock it moved itself.
  ///
  /// Bills are deliberately NOT sent here: they travel through the sale queue,
  /// which also moves stock. Only rows newer than the last successful push are
  /// sent, so this stays a tiny request.
  ///
  /// Returns true when there is nothing left to send (or the push succeeded) and
  /// false when the records are still unsent — the caller must not overwrite the
  /// local catalog in that case.
  Future<bool> _pushLocalChanges(PosClient client) {
    return _pushFuture ??= _runPushLocalChanges(client).whenComplete(() {
      _pushFuture = null;
    });
  }

  Future<bool> _runPushLocalChanges(PosClient client) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sinceRaw = prefs.getString(_pushWatermarkKey);
      final since = sinceRaw == null ? null : DateTime.tryParse(sinceRaw);

      final tables = await DatabaseService().mirrorRowsSince(since);
      // Bills travel through the sale queue (which assigns the server's own
      // invoice number), so they must not be pushed verbatim here.
      tables.remove('sales');

      final hasRows = tables.values.any(
        (rows) => rows is List && rows.isNotEmpty,
      );
      // Stock this terminal moved itself, sent as a delta so a bill the server
      // rang up in the same second is never clobbered.
      final stockDeltas = await StockSync.pendingDeltas();
      if (!hasRows && stockDeltas.isEmpty) return true;

      final json = await client.pushMirror(
        tables: tables,
        stockDeltas: stockDeltas,
        resetToken: prefs.getString(_resetTokenKey) ?? '',
      );

      if (json['stale'] == true) {
        // The server has been reset and this PC has not caught up yet. Do NOT
        // advance the watermark or commit the deltas: the same rows must be
        // re-sent once the next pull has taught us the new reset stamp. Return
        // true so the catalog pull is not blocked (the stock baseline will be
        // re-anchored to the server's post-reset quantities).
        return true;
      }

      // Advance the push watermark using THIS machine's clock, not the
      // server's: the rows being pushed are stamped with the local clock too,
      // so a PC whose clock runs behind the server can no longer silently skip
      // its own new rows (they would sort before a server-based cutoff).
      await prefs.setString(
        _pushWatermarkKey,
        DateTime.now().subtract(_mirrorOverlap).toIso8601String(),
      );
      if (stockDeltas.isNotEmpty) {
        await StockSync.commitDeltas();
      }
      return true;
    } catch (e) {
      // Retried on the next heartbeat; the rows stay in this database.
      lastError = 'Sending changes failed: $e';
      return false;
    }
  }

  /// Pulls the whole shop's data so this terminal's reports, stock, reload
  /// cards, refunds, repacks, goods received and supplier ledger all match the
  /// server's.
  ///
  /// Without this the terminal only ever knew about what it recorded itself,
  /// which is why its profit report looked empty. Gated behind a revision
  /// check, so an idle link still costs one tiny request every few seconds.
  Future<void> _syncFinancials(PosClient client) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      String? revision;
      try {
        revision = await client.fetchFinancialRevision();
      } catch (_) {
        revision = null; // Older server without the endpoint: pull anyway.
      }

      final last = prefs.getString(_mirrorRevisionKey);
      if (revision != null && revision.isNotEmpty && last == revision) {
        // Confirmed in step with the server: record the check so Settings can
        // show that the money link is alive even when nothing had to move.
        lastFinancialSyncAt = DateTime.now();
        return;
      }

      final sinceRaw = prefs.getString(_mirrorWatermarkKey);
      final since = sinceRaw == null ? null : DateTime.tryParse(sinceRaw);

      final json = await client.fetchFinancialMirror(since);

      // The admin wiped the reports. Drop the local copies *before* applying
      // the pull, otherwise the deleted bills would be resurrected row by row.
      final token = json['resetToken'] as String? ?? '';
      final seenToken = prefs.getString(_resetTokenKey) ?? '';
      var resetHere = false;
      if (token.isNotEmpty && token != seenToken) {
        await DatabaseService().clearFinancialHistory();
        await ServerSync.instance.clearPending();
        await prefs.setString(_resetTokenKey, token);
        // Local history was just cleared, so anchor the push watermark on the
        // local clock rather than the server's reset stamp — the next rows this
        // PC records must not be filtered out by clock skew.
        await prefs.setString(
          _pushWatermarkKey,
          DateTime.now().subtract(_mirrorOverlap).toIso8601String(),
        );
        await prefs.remove(_mirrorWatermarkKey);
        resetHere = true;
      }

      final rawTables = json['tables'];
      final attempted = rawTables is Map
          ? rawTables.values
              .whereType<List>()
              .fold<int>(0, (sum, rows) => sum + rows.length)
          : 0;
      final applied = rawTables is Map
          ? await DatabaseService().applyMirror(
              Map<String, dynamic>.from(rawTables),
            )
          : 0;

      if (attempted > 0 && applied < attempted) {
        lastError = 'Sync: ${attempted - applied} of $attempted row(s) '
            'rejected — the two PCs may be on different app versions';
      }

      final serverNow = DateTime.tryParse(json['serverNow'] as String? ?? '');
      if (serverNow != null) {
        await prefs.setString(
          _mirrorWatermarkKey,
          serverNow.subtract(_mirrorOverlap).toIso8601String(),
        );
      }
      if (revision != null && revision.isNotEmpty) {
        await prefs.setString(_mirrorRevisionKey, revision);
      }
      lastFinancialSyncAt = DateTime.now();

      if (applied > 0 || resetHere) {
        financialTick++;
        onFinancialsSynced?.call();
        notifyListeners();
      }
    } catch (e) {
      // Additive only: a mirror failure must never break the catalog link.
      lastError = 'Financial sync failed: $e';
    }
  }

  /// Manual "sync the money now" trigger used by Settings.
  Future<void> syncMoneyNow() async {
    final url = serverUrl;
    if (url == null || mode != NetworkMode.client) return;
    await _syncMoney(PosClient(url));
    notifyListeners();
  }

  /// Wipes the shop's report history — bills, expenses, wastage and reload
  /// cards — on this PC and on the other machine. Products, images, customers
  /// and current stock are deliberately untouched.
  Future<String> resetReports() async {
    try {
      if (mode == NetworkMode.server) {
        final cleared = await DatabaseService().clearFinancialHistory();
        financialTick++;
        onFinancialsSynced?.call();
        notifyListeners();
        return 'Reports cleared: ${cleared['sales']} bill(s), '
            '${cleared['expenses']} expense(s), '
            '${cleared['wastages']} wastage record(s) and '
            '${cleared['reload_cards']} reload card(s) removed. '
            'Items, images and stock were not touched.';
      }

      final url = serverUrl;
      if (url == null) {
        return 'Not connected to the shop server — connect first, then reset.';
      }
      final json = await PosClient(url).resetFinancials();
      final token = json['resetAt'] as String? ?? '';

      // Clear locally straight away, otherwise the next pull would read the
      // server's old rows back in before the reset stamp propagates.
      await DatabaseService().clearFinancialHistory();
      await ServerSync.instance.clearPending();
      final prefs = await SharedPreferences.getInstance();
      if (token.isNotEmpty) {
        await prefs.setString(_resetTokenKey, token);
        await prefs.setString(_pushWatermarkKey, token);
      }
      await prefs.remove(_mirrorWatermarkKey);
      await prefs.remove(_mirrorRevisionKey);
      financialTick++;
      onFinancialsSynced?.call();
      notifyListeners();
      return 'Reports cleared on the server and on this PC '
          '(bills, expenses, wastage and reload cards). '
          'Items, images and stock were not touched.';
    } catch (e) {
      return 'Reset failed: $e';
    }
  }

  /// Basenames of every picture referenced by [products] (a server row may
  /// still hold an absolute path from an older build — we only need the name).
  /// Picture names this machine should have cached, read from the *local*
  /// product table. Used by the "nothing changed" sync path, where the network
  /// catalog is deliberately not re-downloaded.
  Future<Set<String>> _localImageNames() async {
    try {
      final products = await DatabaseService().getAllProducts();
      final names =
          _imageNamesFrom(products.map((e) => e.toMap()).toList());
      if (names.isNotEmpty) return names;
    } catch (_) {
      // Fall back to the recorded list below.
    }
    // Recorded during the last full pull; keeps image healing working even if
    // the local database cannot be read right now.
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_expectedImagesKey) ?? const <String>[])
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Set<String> _imageNamesFrom(List<Map<String, dynamic>> products) {
    final wanted = <String>{};
    for (final prod in products) {
      final raw = prod['imagePath'] as String?;
      if (raw == null || raw.isEmpty) continue;
      final name = raw.split(RegExp(r'[/\\]')).last;
      if (name.isNotEmpty && !name.startsWith('.')) {
        wanted.add(name);
      }
    }
    return wanted;
  }

  /// Downloads the product images in [names] that are missing on this machine
  /// into the local `product_images` folder. Each picture is fetched once and
  /// then served from the local cache, so WiFi usage stays minimal.
  /// Returns how many files were actually downloaded.
  Future<int> _syncImages(PosClient client, Set<String> wanted) async {
    if (wanted.isEmpty) return 0;

    final dir = ProductImageStore.directory();
    try {
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
    } catch (_) {
      return 0;
    }

    var downloaded = 0;
    for (final name in wanted) {
      // Already cached locally → skip the download entirely.
      if (ProductImageStore.resolve(name) != null) continue;
      try {
        final bytes = await client.downloadImage(name);
        final target = File('${dir.path}${Platform.pathSeparator}$name');
        await target.writeAsBytes(bytes);
        downloaded++;
      } catch (_) {
        // Image missing or transient network issue: keep the placeholder and
        // retry on the next catalog refresh.
      }
    }
    return downloaded;
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
    // Plain HTTP probe of the saved address — the path that actually works on
    // locked-down networks, so it runs every time alongside the UDP attempts.
    await _tryHttpFallback();

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
    _catalogRefreshTimer?.cancel();
    _discovery.stop();
    _server.stop();
    super.dispose();
  }
}