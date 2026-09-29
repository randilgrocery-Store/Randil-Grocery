import 'dart:io';

/// Shared constants and message helpers for the LAN POS link.
///
/// The admin PC runs a built-in HTTP server (the single live database) and a
/// small UDP beacon. Cashier PCs listen for the beacon to find the admin PC
/// automatically and otherwise fall back to a manually saved IP address.
class PosProtocol {
  PosProtocol._();

  static const String magic = 'RANDILPOS';
  static const int defaultHttpPort = 8180;

  /// UDP port every POS instance binds and talks on for discovery. Using one
  /// port with SO_REUSEADDR means clients receive the server's announcements
  /// directly and servers hear client hellos.
  static const int discoveryPort = 8181;

  static final InternetAddress multicastGroup =
      InternetAddress('239.0.0.7');

  static const int announceIntervalSeconds = 3;
  static const int helloIntervalSeconds = 5;

  static String announce(String shopName, int httpPort) =>
      '$magic|ANNOUNCE|$shopName|$httpPort';

  static String hello() => '$magic|HELLO';

  static String here(String shopName, int httpPort) =>
      '$magic|HERE|$shopName|$httpPort';

  /// Parses a discovery datagram into (shopName, httpPort) or null.
  static (String shopName, int httpPort)? parse(String message) {
    final parts = message.split('|');
    if (parts.isEmpty || parts[0] != magic) {
      return null;
    }
    if (parts.length >= 4 &&
        (parts[1] == 'ANNOUNCE' || parts[1] == 'HERE')) {
      final port = int.tryParse(parts[3]);
      if (port == null || port <= 0) {
        return null;
      }
      return (parts[2], port);
    }
    return null;
  }
}