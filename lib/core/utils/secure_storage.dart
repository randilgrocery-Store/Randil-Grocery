import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows DPAPI-backed secure storage.
///
/// Secrets (e.g. Google Drive access tokens) and backup files are encrypted
/// with the Windows Data Protection API (DPAPI) so that they are unreadable by
/// other Windows accounts or when the files are copied off the machine.
///
/// Encrypted secrets are stored as `dpapi1:<base64>` which can live in the
/// settings database. Backup files are prefixed with a magic header so that
/// legacy (plaintext) backups can still be restored.
class SecureStorageService {
  factory SecureStorageService() => _instance;

  SecureStorageService._internal();
  static final SecureStorageService _instance = SecureStorageService._internal();

  static const String _prefix = 'dpapi1:';
  static const int _cryptprotectUiForbidden = 0x1;
  static const String _magic = 'RANDILENC';

  /// True when [value] is an encrypted token (starts with the dpapi prefix).
  bool isEncrypted(String value) => value.startsWith(_prefix);

  /// Encrypt a string. Returns it unchanged when empty or already encrypted.
  String encryptString(String plain) {
    if (plain.isEmpty || isEncrypted(plain)) {
      return plain;
    }
    final protected = protect(Uint8List.fromList(utf8.encode(plain)));
    return _prefix + base64Encode(protected);
  }

  /// Decrypt a string produced by [encryptString]. Returns null when the value
  /// is empty/plain, or when it cannot be decrypted (e.g. different user).
  String? decryptString(String stored) {
    if (stored.isEmpty || !isEncrypted(stored)) {
      return null;
    }
    try {
      final data = base64Decode(stored.substring(_prefix.length));
      final plain = unprotect(data);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Encrypt arbitrary bytes with DPAPI (current Windows user).
  Uint8List protect(Uint8List data) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      input.ref.cbData = data.length;
      input.ref.pbData = dataPtr;

      final result = CryptProtectData(
        input,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptprotectUiForbidden,
        output,
      );
      if (result == 0) {
        throw Exception('CryptProtectData failed: ${GetLastError()}');
      }
      final count = output.ref.cbData;
      final ptr = output.ref.pbData;
      if (count == 0 || ptr == nullptr) {
        return Uint8List(0);
      }
      return Uint8List.fromList(ptr.asTypedList(count));
    } finally {
      if (output.ref.pbData != nullptr) {
        LocalFree(output.ref.pbData);
      }
      calloc.free(input);
      calloc.free(output);
      calloc.free(dataPtr);
    }
  }

  /// Decrypt bytes produced by [protect].
  Uint8List unprotect(Uint8List data) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final dataPtr = calloc<Uint8>(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      input.ref.cbData = data.length;
      input.ref.pbData = dataPtr;

      final result = CryptUnprotectData(
        input,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        _cryptprotectUiForbidden,
        output,
      );
      if (result == 0) {
        throw Exception('CryptUnprotectData failed: ${GetLastError()}');
      }
      final count = output.ref.cbData;
      final ptr = output.ref.pbData;
      if (count == 0 || ptr == nullptr) {
        return Uint8List(0);
      }
      return Uint8List.fromList(ptr.asTypedList(count));
    } finally {
      if (output.ref.pbData != nullptr) {
        LocalFree(output.ref.pbData);
      }
      calloc.free(input);
      calloc.free(output);
      calloc.free(dataPtr);
    }
  }

  /// Read [srcPath] and write an encrypted copy to [destPath].
  bool encryptFile(String srcPath, String destPath) {
    try {
      final bytes = File(srcPath).readAsBytesSync();
      final protected = protect(bytes);
      final payload = <int>[...utf8.encode(_magic), ...protected];
      File(destPath).writeAsBytesSync(payload, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Decrypt a file created by [encryptFile] into [destPath]. If [srcPath]
  /// has no magic header it is a legacy plaintext backup and is copied as-is.
  bool decryptFile(String srcPath, String destPath) {
    try {
      final bytes = File(srcPath).readAsBytesSync();
      final magic = utf8.encode(_magic);
      var isEncryptedFile = bytes.length >= magic.length;
      if (isEncryptedFile) {
        for (var i = 0; i < magic.length; i++) {
          if (bytes[i] != magic[i]) {
            isEncryptedFile = false;
            break;
          }
        }
      }
      if (!isEncryptedFile) {
        File(srcPath).copySync(destPath);
        return true;
      }
      final payload = bytes.sublist(magic.length);
      File(destPath).writeAsBytesSync(unprotect(Uint8List.fromList(payload)));
      return true;
    } catch (_) {
      return false;
    }
  }
}