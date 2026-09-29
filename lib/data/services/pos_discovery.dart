import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pos_protocol.dart';

/// A POS instance found on the LAN. [sourceAddress] is where the announcement
/// came from — the HTTP base URL is built from it.
class DiscoveredPos {
  DiscoveredPos({
    required this.sourceAddress,
    required this.httpPort,
    this.shopName = '',
  });

  final InternetAddress sourceAddress;
  final String shopName;
  final int httpPort;

  String? get baseUrl =>
      'http://${sourceAddress.address}:$httpPort';

  @override
  String toString() =>
      'DiscoveredPos($shopName @ ${sourceAddress.address}:$httpPort)';
}

/// Client-side discovery. Binds the shared UDP port and listens for server
/// announcements; also probes the multicast group and (optionally) a saved
/// fallback IP so connection works even on routers that block multicast.
class PosDiscovery {
  RawDatagramSocket? _socket;
  Timer? _helloTimer;
  final Map<String, DiscoveredPos> _seen = {};
  final Map<String, Timer> _expiryTimers = {};
  DateTime _lastJoinAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called whenever a server is discovered/heard. Callers keep the last one
  /// that successfully answers /api/health.
  void Function(DiscoveredPos pos)? onDiscovered;

  /// Currently known servers, most recently heard first.
  List<DiscoveredPos> get servers {
    final list = _seen.values.toList()
      ..sort((a, b) =>
          (_expiryTimers[b.sourceAddress.address]?.tick ?? 0)
              .compareTo(_expiryTimers[a.sourceAddress.address]?.tick ?? 0));
    return list;
  }

  Future<void> start() async {
    if (_socket != null) {
      return;
    }
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      PosProtocol.discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    socket.multicastHops = 1;
    socket.multicastLoopback = false;

    _joinMulticast(socket);

    socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }
      _handleDatagram(datagram);
    });

    // Actively probe the group so we find servers that booted before us and
    // that (for whatever reason) are not announcing.
    _helloTimer = Timer.periodic(
      const Duration(seconds: PosProtocol.helloIntervalSeconds),
      (_) => _sendHello(),
    );
    _sendHello();
  }

  Future<void> stop() async {
    _helloTimer?.cancel();
    _helloTimer = null;
    for (final t in _expiryTimers.values) {
      t.cancel();
    }
    _expiryTimers.clear();
    _socket?.close();
    _socket = null;
    _seen.clear();
  }

  Future<void> _joinMulticast(RawDatagramSocket socket) async {
    // Windows can throw transiently if the interface is not ready yet — retry
    // a few times, never more than once every few seconds.
    if (DateTime.now().difference(_lastJoinAttempt).inSeconds < 3) {
      return;
    }
    _lastJoinAttempt = DateTime.now();
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        socket.joinMulticast(PosProtocol.multicastGroup);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
  }

  void _handleDatagram(Datagram datagram) {
    final text = utf8.decode(datagram.data, allowMalformed: true);
    final parsed = PosProtocol.parse(text);
    if (parsed == null) {
      return;
    }
    final (shopName, httpPort) = parsed;
    final pos = DiscoveredPos(
      sourceAddress: datagram.address,
      shopName: shopName,
      httpPort: httpPort,
    );
    _seen[datagram.address.address] = pos;
    _expiryTimers[datagram.address.address]?.cancel();
    _expiryTimers[datagram.address.address] = Timer(
      const Duration(seconds: 30),
      () {
        _seen.remove(datagram.address.address);
        _expiryTimers.remove(datagram.address.address);
      },
    );
    onDiscovered?.call(pos);
  }

  void _sendHello() {
    try {
      _socket?.send(
        utf8.encode(PosProtocol.hello()),
        PosProtocol.multicastGroup,
        PosProtocol.discoveryPort,
      );
    } catch (_) {
      // Optionally ignore.
    }
  }

  /// Unicast probe against a saved fallback IP (routers that block multicast).
  /// Returns the server's reply if HTTP is actually reachable, else null.
  Future<DiscoveredPos?> probeFallback(String host, int httpPort) async {
    final address = InternetAddress.tryParse(host.trim());
    if (address == null) {
      return null;
    }
    final socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      final completer = Completer<DiscoveredPos>();
      socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final datagram = socket.receive();
        if (datagram == null) {
          return;
        }
        final parsed =
            PosProtocol.parse(utf8.decode(datagram.data, allowMalformed: true));
        if (parsed != null) {
          completer.complete(
            DiscoveredPos(
              sourceAddress: datagram.address,
              shopName: parsed.$1,
              httpPort: parsed.$2 == 0 ? httpPort : parsed.$2,
            ),
          );
        }
      });
      socket.send(
        utf8.encode(PosProtocol.hello()),
        address,
        PosProtocol.discoveryPort,
      );
      return await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    } finally {
      socket.close();
    }
  }
}