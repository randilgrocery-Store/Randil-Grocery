import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Passwords are never stored as plain text. They are stored as a
/// salted SHA-256 hash in the form: `<salt>$<hash>`.
///
/// A random 16-byte salt is generated per user and the hash is computed as
/// an HMAC of the password using the salt as the key, then base64-encoded.
/// This simple, dependency-light scheme is sufficient for a local desktop
/// POS while avoiding ever persisting or returning the raw password.
class PasswordHasher {
  PasswordHasher._();

  static final Random _random = Random.secure();

  /// Returns a random salt for a new password.
  static String generateSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Hash a password with the given salt, producing
  /// `<salt>$<base64 hmac-sha256>`.
  static String hash(String password, {String? salt}) {
    final s = salt ?? generateSalt();
    final key = utf8.encode(s);
    final hmac = Hmac(sha256, key).convert(utf8.encode(password)).bytes;

    // Multiple iterations cheaply to slow brute-force attempts.
    var digest = hmac;
    for (var i = 0; i < 1000; i++) {
      digest = Hmac(sha256, digest).convert(utf8.encode(password)).bytes;
    }

    return '$s\$${base64Url.encode(digest)}';
  }

  /// Verify a plain-text password against a stored `<salt>$<hash>` string.
  static bool verify(String password, String stored) {
    if (!stored.contains('\$')) {
      return false;
    }
    final parts = stored.split('\$');
    if (parts.length != 2) {
      return false;
    }
    final salt = parts[0];
    final expectedHash = parts[1];
    final recomputed = hash(password, salt: salt);
    final recomputedHash = recomputed.split('\$')[1];
    return _constantTimeEquals(expectedHash, recomputedHash);
  }

  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }
}
