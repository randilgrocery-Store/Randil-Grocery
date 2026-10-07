import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/secure_storage.dart';
import '../database/database_service.dart';
import '../models/shop_settings.dart';

class BackupRunResult {
  const BackupRunResult({
    required this.localSaved,
    required this.cloudEnabled,
    required this.cloudUploaded,
    this.localPath,
    this.message,
  });

  final bool localSaved;
  final bool cloudEnabled;
  final bool cloudUploaded;
  final String? localPath;
  final String? message;

  bool get isSuccess => localSaved;
}

/// Live view of the automatic backup pipeline, used by the Settings screen to
/// show the shop owner exactly what has been saved and pushed, in plain words.
@immutable
class BackupCloudStatus {
  const BackupCloudStatus({
    this.lastTransactionAt,
    this.lastTransaction = '',
    this.lastLocalSnapshotAt,
    this.localSnapshotFolder = '',
    this.localSnapshotCount = 0,
    this.lastDrivePushAt,
    this.lastDriveError,
    this.lastGithubPushAt,
    this.lastGithubError,
    this.working = false,
  });

  final DateTime? lastTransactionAt;
  final String lastTransaction;
  final DateTime? lastLocalSnapshotAt;
  final String localSnapshotFolder;
  final int localSnapshotCount;
  final DateTime? lastDrivePushAt;
  final String? lastDriveError;
  final DateTime? lastGithubPushAt;
  final String? lastGithubError;
  final bool working;

  bool get driveHealthy => lastDrivePushAt != null && lastDriveError == null;
  bool get githubHealthy => lastGithubPushAt != null && lastGithubError == null;

  BackupCloudStatus copyWith({
    DateTime? lastTransactionAt,
    String? lastTransaction,
    DateTime? lastLocalSnapshotAt,
    String? localSnapshotFolder,
    int? localSnapshotCount,
    DateTime? lastDrivePushAt,
    String? lastDriveError,
    bool clearDriveError = false,
    DateTime? lastGithubPushAt,
    String? lastGithubError,
    bool clearGithubError = false,
    bool? working,
  }) {
    return BackupCloudStatus(
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
      lastTransaction: lastTransaction ?? this.lastTransaction,
      lastLocalSnapshotAt: lastLocalSnapshotAt ?? this.lastLocalSnapshotAt,
      localSnapshotFolder: localSnapshotFolder ?? this.localSnapshotFolder,
      localSnapshotCount: localSnapshotCount ?? this.localSnapshotCount,
      lastDrivePushAt: lastDrivePushAt ?? this.lastDrivePushAt,
      lastDriveError:
          clearDriveError ? null : (lastDriveError ?? this.lastDriveError),
      lastGithubPushAt: lastGithubPushAt ?? this.lastGithubPushAt,
      lastGithubError: clearGithubError
          ? null
          : (lastGithubError ?? this.lastGithubError),
      working: working ?? this.working,
    );
  }
}

/// Backups for RandilPOS.
///
/// Every transaction (a bill, a goods received note, a wastage entry, a
/// refund, an expense, a supplier payment, a product edit, ...) calls
/// [notifyTransaction]. That immediately writes a crash-safe copy of the
/// database into the machine's temporary folder, and then pushes the very same
/// database file to Google Drive and GitHub in the background.
class BackupService {
  factory BackupService() => _instance;

  BackupService._internal();
  static final BackupService _instance = BackupService._internal();

  static const String preferredWindowsBackupPath =
      r'C:\Program Files\POS\backups';

  static const String googleDriveApiUrl =
      'https://www.googleapis.com/drive/v3/files';
  static const String multipartUploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';
  static const String mediaUpdateUrl =
      'https://www.googleapis.com/upload/drive/v3/files';

  // Google API credentials
  static const String clientId = ''; // Will be set during setup
  static const String clientSecret = ''; // Will be set during setup

  // Shared Google Drive folder that the shop backups are uploaded into.
  static const String defaultGoogleDriveFolderId =
      '1N0YvowmSVGnI-X6MWfQf3o6ux880JHom';

  /// Fixed file names. Re-using one name in the cloud means each push
  /// overwrites the previous copy instead of filling the folder with hundreds
  /// of files - which is what makes the cloud backup quick and tidy.
  static const String driveFileName = 'RandilPOS_database.db';
  static const String githubFileName = 'RandilPOS_database.db';
  static const String githubFolder = 'database-backups';

  // Backup configuration
  static const int backupIntervalDays = 1;
  static const int autoDeleteDays = 120; // 4 months
  static const int snapshotsToKeep = 60;

  /// Minimum time between two cloud pushes. A local copy is written for every
  /// single transaction; the cloud copy follows within this window so a busy
  /// till never waits for the internet.
  static const Duration cloudPushInterval = Duration(seconds: 45);

  // ===================== live status (shared, static) =====================
  static final ValueNotifier<BackupCloudStatus> status =
      ValueNotifier<BackupCloudStatus>(const BackupCloudStatus());

  static void _publishStatus(BackupCloudStatus Function(BackupCloudStatus) f) {
    try {
      status.value = f(status.value);
    } catch (_) {}
  }

  String? _lastError;

  String? get lastError => _lastError;

  String _lastCloudStatus = '';
  String get lastCloudStatus => _lastCloudStatus;

  // ===================== every-transaction pipeline ========================
  static bool _snapshotRunning = false;
  static bool _snapshotQueued = false;
  static bool _cloudRunning = false;
  static bool _cloudQueued = false;
  static Timer? _cloudTimer;

  /// Called by every write path in the app. Never throws, never blocks the UI.
  static void notifyTransaction(String kind) {
    final now = DateTime.now();
    _publishStatus((s) => s.copyWith(
          lastTransactionAt: now,
          lastTransaction: kind,
          working: true,
        ));
    unawaited(_runLocalSnapshotPass());
    _scheduleCloudPush();
  }

  static Future<void> _runLocalSnapshotPass() async {
    if (_snapshotRunning) {
      _snapshotQueued = true;
      return;
    }
    _snapshotRunning = true;
    try {
      do {
        _snapshotQueued = false;
        await _instance._writeLocalSnapshot();
      } while (_snapshotQueued);
    } finally {
      _snapshotRunning = false;
      _publishStatus((s) => s.copyWith(working: false));
    }
  }

  static void _scheduleCloudPush() {
    final now = DateTime.now();
    final last = _lastCloudPushAt;
    if (last == null || now.difference(last) >= cloudPushInterval) {
      _cloudTimer?.cancel();
      _cloudTimer = null;
      unawaited(_runCloudPass());
      return;
    }
    // Too soon - come back when the window opens. Only one timer is kept so a
    // busy till still results in a single push.
    _cloudTimer?.cancel();
    final wait = cloudPushInterval - now.difference(last);
    _cloudTimer = Timer(wait, () {
      _cloudTimer = null;
      unawaited(_runCloudPass());
    });
  }

  static DateTime? _lastCloudPushAt;

  static Future<void> _runCloudPass({bool archive = false}) async {
    if (_cloudRunning) {
      _cloudQueued = true;
      return;
    }
    _cloudRunning = true;
    try {
      do {
        _cloudQueued = false;
        await _instance._pushSnapshotToCloud(archive: archive);
      } while (_cloudQueued);
    } finally {
      _cloudRunning = false;
      _lastCloudPushAt = DateTime.now();
    }
  }

  /// Crash-safe copy of the live database into the machine's temp folder.
  /// Returns the newest snapshot path, or null when it could not be written.
  Future<String?> snapshotToTempFolder({String prefix = 'pos'}) async {
    final dir = await tempSnapshotDirectory();
    final stamp = _fileStamp(DateTime.now());
    final name = '${prefix}_$stamp.db';
    return _writeSnapshotInto(dir.path, name);
  }

  /// Same as [snapshotToTempFolder] but also refreshes the fixed
  /// `latest.db` copy that the cloud uploads always use.
  Future<String?> _writeLocalSnapshot() async {
    final dir = await tempSnapshotDirectory();
    final stamp = _fileStamp(DateTime.now());
    final written =
        await _writeSnapshotInto(dir.path, 'pos_$stamp.db');
    if (written == null) {
      return null;
    }
    // Fixed-name copy used for cloud pushes (and for a quick manual restore).
    try {
      final latest = p.join(dir.path, 'latest.db');
      final tmp = '$latest.writing';
      if (File(tmp).existsSync()) File(tmp).deleteSync();
      File(written).copySync(tmp);
      if (File(latest).existsSync()) File(latest).deleteSync();
      File(tmp).renameSync(latest);
    } catch (e) {
      developer.log('latest.db refresh failed: $e', name: 'BackupService');
    }
    _prune(dir, keep: snapshotsToKeep, prefix: 'pos_');
    _lastLocalSnapshot = written;
    _publishStatus((s) => s.copyWith(
          lastLocalSnapshotAt: DateTime.now(),
          localSnapshotFolder: dir.path,
          localSnapshotCount: _countSnapshots(dir),
        ));
    return written;
  }

  static String? _lastLocalSnapshot;

  /// Newest temp-folder snapshot path, if any.
  String? get lastLocalSnapshot => _lastLocalSnapshot;

  /// Writes a consistent copy of the live database. `VACUUM INTO` is used
  /// first because it produces a complete, consistent file even while the till
  /// is writing; a plain file copy (after flushing any pending journal) is the
  /// fallback. The file only appears under its final name once it is whole, so
  /// a power cut can never leave a half-written backup behind.
  Future<String?> _writeSnapshotInto(String dirPath, String fileName) async {
    _lastError = null;
    try {
      final livePath = await DatabaseService().getDatabasePath();
      final liveFile = File(livePath);
      if (!liveFile.existsSync()) {
        _lastError = 'Database file not found at $livePath';
        return null;
      }

      var target = p.join(dirPath, fileName);
      // Never overwrite an existing snapshot (VACUUM INTO refuses to).
      var attempt = 1;
      while (File(target).existsSync() && attempt < 50) {
        final base = fileName.replaceAll(RegExp(r'\.db$'), '');
        target = p.join(dirPath, '${base}_$attempt.db');
        attempt++;
      }

      final tmp = '$target.writing';
      if (File(tmp).existsSync()) {
        File(tmp).deleteSync();
      }

      var created = false;
      try {
        final db = await DatabaseService().database;
        final escaped = tmp.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$escaped'");
        created = File(tmp).existsSync();
      } catch (_) {
        created = false;
      }

      if (!created) {
        // Fallback: flush any pending writes, then copy the file.
        try {
          final db = await DatabaseService().database;
          await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {}
        try {
          await liveFile.copy(tmp);
          created = File(tmp).existsSync();
        } catch (_) {
          created = false;
        }
      }

      if (!created) {
        _lastError = 'Backup file could not be created in $dirPath';
        return null;
      }

      if (File(target).existsSync()) {
        File(target).deleteSync();
      }
      File(tmp).renameSync(target);
      return target;
    } catch (e) {
      _lastError = e.toString();
      developer.log('snapshot failed: $e', name: 'BackupService');
      return null;
    }
  }

  /// The temporary folder every transaction is copied into.
  Future<Directory> tempSnapshotDirectory() async {
    Directory? base;
    try {
      base = await getTemporaryDirectory();
    } catch (_) {}
    if (base == null || !_writable(base.path)) {
      base = DatabaseService().snapshotsDirectory();
    }
    final dir = Directory(p.join(base.path, 'RandilPOS_Backups'));
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } catch (_) {
      return DatabaseService().snapshotsDirectory();
    }
    _publishStatus((s) => s.copyWith(localSnapshotFolder: dir.path));
    return dir;
  }

  static bool _writable(String path) {
    try {
      final probe = File(p.join(path, '.randil_write_probe'));
      probe.writeAsStringSync('ok');
      if (probe.existsSync()) probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _prune(Directory dir, {required int keep, required String prefix}) {
    try {
      final files = (dir
              .listSync()
              .whereType<File>()
              .where((f) =>
                  f.path.endsWith('.db') &&
                  p.basename(f.path).startsWith(prefix))
              .toList())
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final old in files.skip(keep)) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static int _countSnapshots(Directory dir) {
    try {
      return dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.db') && p.basename(f.path).startsWith('pos_'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  static String _fileStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}'
        '${two(t.minute)}${two(t.second)}';
  }

  // ===================== cloud push =====================
  /// Pushes the newest temp-folder copy to Google Drive and GitHub.
  Future<void> _pushSnapshotToCloud({bool archive = false}) async {
    try {
      String? snapshot = _lastLocalSnapshot;
      if (snapshot == null || !File(snapshot).existsSync()) {
        snapshot = await _writeLocalSnapshot();
      }
      if (snapshot == null || !File(snapshot).existsSync()) {
        return;
      }

      // GitHub first: it is the cheapest of the two pushes.
      await pushSnapshotToGithub(snapshotPath: snapshot, archive: archive);

      // Google Drive next, only when the shop turned it on.
      final settings = await _safeSettings();
      if (settings != null && settings.enableGoogleDriveBackup) {
        final token = SecureStorageService()
            .decryptString(settings.googleDriveAccessToken);
        if (token != null && token.trim().isNotEmpty) {
          final ok = await uploadBackupToGoogleDrive(
            backupFilePath: snapshot,
            accessToken: token.trim(),
            folderId: settings.googleDriveFolderId.trim().isEmpty
                ? defaultGoogleDriveFolderId
                : settings.googleDriveFolderId,
            fileName: driveFileName,
          );
          _lastCloudStatus = ok
              ? 'Google Drive updated ${_time(DateTime.now())}'
              : 'Google Drive push failed: ${_lastError ?? 'unknown'}';
        } else {
          _lastCloudStatus = 'Google Drive is switched off.';
        }
      }
    } catch (e) {
      _lastError = e.toString();
      developer.log('cloud push failed: $e', name: 'BackupService');
    }
  }

  static Future<ShopSettings?> _safeSettings() async {
    try {
      return await DatabaseService().getShopSettings();
    } catch (_) {
      return null;
    }
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  // ===================== Google Drive =====================
  static const String _prefsDriveFileId = 'gdrive_backup_file_id';

  /// Uploads (or replaces) the backup in Google Drive. When the same file
  /// already exists in the folder it is updated in place, which is much
  /// faster than creating a new copy every time.
  Future<bool> uploadBackupToGoogleDrive({
    required String backupFilePath,
    required String accessToken,
    String? folderId,
    String? fileName,
  }) async {
    try {
      _lastError = null;
      if (accessToken.trim().isEmpty) {
        _lastError = 'Google Drive access token is empty';
        return false;
      }

      final file = File(backupFilePath);
      if (!file.existsSync()) {
        _lastError = 'Backup file does not exist: $backupFilePath';
        return false;
      }

      final name = (fileName == null || fileName.trim().isEmpty)
          ? p.basename(backupFilePath)
          : fileName.trim();
      final targetFolder =
          (folderId == null || folderId.trim().isEmpty)
              ? defaultGoogleDriveFolderId
              : folderId.trim();

      final fileId = await _findDriveFileId(
        accessToken: accessToken,
        name: name,
        folderId: targetFolder,
      );

      final bytes = await file.readAsBytes();
      final headers = {'Authorization': 'Bearer ${accessToken.trim()}'};

      if (fileId != null) {
        final request = http.Request(
          'PATCH',
          Uri.parse('$mediaUpdateUrl/$fileId?uploadType=media'),
        )
          ..headers.addAll(headers)
          ..bodyBytes = bytes;
        final response = await request.send();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _publishStatus((s) => s.copyWith(
                lastDrivePushAt: DateTime.now(),
                clearDriveError: true,
              ));
          return true;
        }
        final text = await response.stream.bytesToString();
        // A stale id means the file was deleted on Drive: drop it and retry
        // once as a fresh upload.
        if (response.statusCode == 404 || response.statusCode == 410) {
          await _forgetDriveFileId();
          final created = await _createDriveFile(
            accessToken: accessToken,
            name: name,
            folderId: targetFolder,
            bytes: bytes,
          );
          if (created) {
            _publishStatus((s) => s.copyWith(
                  lastDrivePushAt: DateTime.now(),
                  clearDriveError: true,
                ));
          }
          return created;
        }
        _lastError = 'Google Drive upload failed (${response.statusCode}): $text';
        _publishStatus((s) => s.copyWith(lastDriveError: _lastError));
        return false;
      }

      final created = await _createDriveFile(
        accessToken: accessToken,
        name: name,
        folderId: targetFolder,
        bytes: bytes,
      );
      if (created) {
        _publishStatus((s) => s.copyWith(
              lastDrivePushAt: DateTime.now(),
              clearDriveError: true,
            ));
      }
      return created;
    } catch (e) {
      _lastError = e.toString();
      _publishStatus((s) => s.copyWith(lastDriveError: _lastError));
      return false;
    }
  }

  Future<bool> _createDriveFile({
    required String accessToken,
    required String name,
    required String folderId,
    required List<int> bytes,
  }) async {
    final metadata = {'name': name, 'parents': [folderId]};
    final boundary =
        'boundary_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}';
    final bodyBytes = <int>[];
    bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
    bodyBytes.addAll(
      utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
    );
    bodyBytes.addAll(utf8.encode(jsonEncode(metadata)));
    bodyBytes.addAll(utf8.encode('\r\n'));
    bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
    bodyBytes.addAll(
      utf8.encode('Content-Type: application/octet-stream\r\n\r\n'),
    );
    bodyBytes.addAll(bytes);
    bodyBytes.addAll(utf8.encode('\r\n--$boundary--\r\n'));

    final request = http.Request('POST', Uri.parse(multipartUploadUrl))
      ..headers['Authorization'] = 'Bearer ${accessToken.trim()}'
      ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
      ..bodyBytes = bodyBytes;

    final response = await request.send();
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final text = await response.stream.bytesToString();
      try {
        final id = (jsonDecode(text) as Map<String, dynamic>)['id'] as String?;
        if (id != null) await _rememberDriveFileId(id);
      } catch (_) {}
      return true;
    }
    final text = await response.stream.bytesToString();
    _lastError = 'Google Drive upload failed (${response.statusCode}): $text';
    _publishStatus((s) => s.copyWith(lastDriveError: _lastError));
    return false;
  }

  /// Locates the backup file in the Drive folder. The id is remembered so this
  /// is normally a single shared-preferences read instead of a web request.
  Future<String?> _findDriveFileId({
    required String accessToken,
    required String name,
    required String folderId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsDriveFileId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    } catch (_) {}

    try {
      final q = "name = '$name' and '$folderId' in parents and trashed = false";
      final uri = Uri.parse(googleDriveApiUrl).replace(
        queryParameters: {'q': q, 'fields': 'files(id,name)', 'pageSize': '5'},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${accessToken.trim()}'},
      );
      if (response.statusCode == 200) {
        final files =
            (jsonDecode(response.body) as Map<String, dynamic>)['files'] as List?;
        if (files != null && files.isNotEmpty) {
          final id = (files.first as Map<String, dynamic>)['id'] as String?;
          if (id != null) {
            await _rememberDriveFileId(id);
            return id;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _rememberDriveFileId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsDriveFileId, id);
    } catch (_) {}
  }

  Future<void> _forgetDriveFileId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsDriveFileId);
    } catch (_) {}
  }

  // ===================== GitHub =====================
  static const String _githubApiBase =
      'https://api.github.com/repos/randilgrocery-Store/Randil-Grocery';
  static const String _prefsGithubEnabled = 'github_backup_enabled';

  String? _githubSyncPath;
  String? _githubToken;

  String? get githubSyncPath => _githubSyncPath;

  /// Optional GitHub personal-access token. When the client machine does not
  /// have git installed, backups are still pushed through the GitHub REST API
  /// using this token, so the GitHub backup works everywhere.
  String? get githubToken => _githubToken;

  Future<void> loadGithubCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _githubSyncPath = prefs.getString('github_repo_path');
      final enc = prefs.getString('github_token');
      _githubToken = (enc == null || enc.isEmpty)
          ? null
          : SecureStorageService().decryptString(enc);
    } catch (_) {}
  }

  Future<void> setGithubToken(String token) async {
    _githubToken = token.trim().isEmpty ? null : token.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_githubToken == null) {
      await prefs.remove('github_token');
    } else {
      await prefs.setString(
        'github_token',
        SecureStorageService().encryptString(_githubToken!),
      );
    }
  }

  Future<void> loadGithubSyncPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _githubSyncPath = prefs.getString('github_repo_path');
    } catch (_) {}
  }

  Future<void> setGithubSyncPath(String path) async {
    _githubSyncPath = path.trim().isEmpty ? null : path.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_githubSyncPath == null) {
        await prefs.remove('github_repo_path');
      } else {
        await prefs.setString('github_repo_path', _githubSyncPath!);
      }
    } catch (_) {}
  }

  static Future<bool> isGithubBackupEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsGithubEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setGithubBackupEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsGithubEnabled, value);
    } catch (_) {}
  }

  /// Locate the local clone of the GitHub backup repo. Uses the folder set in
  /// settings; falls back to the known development location.
  Future<String?> _resolveGithubRepo() async {
    if (_githubSyncPath != null && _githubSyncPath!.isNotEmpty) {
      return Directory(_githubSyncPath!).existsSync()
          ? _githubSyncPath
          : null;
    }
    const devRepo = r'D:\Randil Grocery POS';
    try {
      if (Directory(devRepo).existsSync() &&
          Directory('$devRepo\\.git').existsSync()) {
        return devRepo;
      }
    } catch (_) {}
    return null;
  }

  /// Copies the snapshot into the GitHub repo's backup folder and pushes it
  /// (git when the machine has git, otherwise the GitHub REST API). The cloud
  /// file keeps one fixed name so each push is a quick replace, and an hourly
  /// dated copy is kept for history when [archive] is true.
  Future<bool> pushSnapshotToGithub({
    String? snapshotPath,
    bool archive = false,
  }) async {
    _lastError = null;
    try {
      if (!await isGithubBackupEnabled()) {
        _lastCloudStatus = 'GitHub backup is switched off.';
        return false;
      }
      if (_githubSyncPath == null && _githubToken == null) {
        _githubSyncPath = await _prefsString('github_repo_path');
        final enc = await _prefsString('github_token');
        _githubToken =
            (enc == null || enc.isEmpty) ? null : SecureStorageService().decryptString(enc);
      }

      final String snap;
      if (snapshotPath != null && File(snapshotPath).existsSync()) {
        snap = snapshotPath;
      } else {
        final created = await _writeLocalSnapshot();
        if (created == null) {
          _lastError = 'Backup copy could not be created for GitHub push.';
          return false;
        }
        snap = created;
      }

      final repo = await _resolveGithubRepo();
      if (repo != null) {
        final pushed = await _pushViaGit(snap, repo, archive: archive);
        if (pushed || _lastError != 'GitHub git not available on this machine.') {
          if (pushed) {
            _publishStatus((s) => s.copyWith(
                  lastGithubPushAt: DateTime.now(),
                  clearGithubError: true,
                ));
          }
          return pushed;
        }
        // git unavailable - fall through to the REST API.
      }

      if (_githubToken == null || _githubToken!.trim().isEmpty) {
        _lastError = repo == null
            ? 'GitHub backup folder is not set and no GitHub key is saved.'
            : 'git is not available on this machine and no GitHub key is saved.';
        _publishStatus((s) => s.copyWith(lastGithubError: _lastError));
        return false;
      }

      final pushed = await _pushViaRest(snap, archive: archive);
      if (pushed) {
        _publishStatus((s) => s.copyWith(
              lastGithubPushAt: DateTime.now(),
              clearGithubError: true,
            ));
        _lastCloudStatus = 'GitHub updated ${_time(DateTime.now())}';
      } else {
        _publishStatus((s) => s.copyWith(lastGithubError: _lastError));
      }
      return pushed;
    } catch (e) {
      _lastError = e.toString();
      _publishStatus((s) => s.copyWith(lastGithubError: _lastError));
      return false;
    }
  }

  Future<String?> _prefsString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _pushViaGit(String snap, String repo, {bool archive = false}) async {
    final backupsDir = Directory(p.join(repo, githubFolder));
    if (!backupsDir.existsSync()) {
      backupsDir.createSync(recursive: true);
    }

    File(snap).copySync(p.join(backupsDir.path, githubFileName));
    if (archive) {
      File(snap).copySync(
        p.join(backupsDir.path, 'pos_${_fileStamp(DateTime.now())}.db'),
      );
    }
    _prune(backupsDir, keep: 90, prefix: 'pos_');

    final now = DateTime.now().toLocal();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    Future<ProcessResult?> runGit(List<String> args) async {
      try {
        return await Process.run('git', args, workingDirectory: repo);
      } catch (_) {
        return null;
      }
    }

    // Commit the fresh snapshot on whatever branch is checked out, then push
    // that branch's tip to the remote's main. Pushing the local `main` branch
    // by name silently stopped working once the checkout moved to another
    // branch: the backup stayed committed locally and never reached GitHub.
    final add = await runGit(['add', '-A', githubFolder]);
    if (add == null) {
      _lastError = 'GitHub git not available on this machine.';
      return false;
    }
    final commit = await runGit(['commit', '-m', 'db backup $stamp']);
    if (commit == null) {
      _lastError = 'GitHub git not available on this machine.';
      return false;
    }
    final status = await runGit(['status', '--porcelain', '--', githubFolder]);
    final dirty = status == null ? '' : '${status.stdout}'.trim();
    if (dirty.isNotEmpty) {
      // The snapshot is still uncommitted (git config or hook problem), so a
      // push now would upload an older copy - surface the real reason instead.
      final detail = ('${commit.stdout}\n${commit.stderr}').trim();
      _lastError =
          detail.isEmpty ? 'git commit failed.' : 'git commit failed: $detail';
      return false;
    }
    final push = await runGit(['push', 'origin', 'HEAD:main']);
    if (push == null) {
      _lastError = 'GitHub git not available on this machine.';
      return false;
    }
    if (push.exitCode != 0) {
      _lastError = 'git push failed with exit code ${push.exitCode}.';
      return false;
    }
    return true;
  }

  Future<bool> _pushViaRest(String snap, {bool archive = false}) async {
    final bytes = await File(snap).readAsBytes();
    final headers = {
      'Authorization': 'Bearer ${_githubToken!.trim()}',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    final uploaded =
        await _putGithubFile(headers, '$githubFolder/$githubFileName', bytes,
            'db backup ${DateTime.now().toLocal()}');
    if (!uploaded) {
      return false;
    }

    if (archive) {
      await _putGithubFile(
        headers,
        '$githubFolder/pos_${_fileStamp(DateTime.now())}.db',
        bytes,
        'db archive ${DateTime.now().toLocal()}',
      );
      await _pruneViaRest(headers);
    }
    return true;
  }

  Future<bool> _putGithubFile(
    Map<String, String> headers,
    String path,
    List<int> bytes,
    String message,
  ) async {
    try {
      // Existing file? Fetch its sha so we can overwrite it.
      String? sha;
      final existing = await http.get(
        Uri.parse('$_githubApiBase/contents/$path'),
        headers: headers,
      );
      if (existing.statusCode == 200) {
        final decoded = jsonDecode(existing.body) as Map<String, dynamic>;
        sha = decoded['sha'] as String?;
      } else if (existing.statusCode != 404) {
        _lastError = 'GitHub check failed (${existing.statusCode}).';
        return false;
      }

      final put = await http.put(
        Uri.parse('$_githubApiBase/contents/$path'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'content': base64Encode(bytes),
          'branch': 'main',
          if (sha != null) 'sha': sha,
        }),
      );
      if (put.statusCode != 200 && put.statusCode != 201) {
        _lastError = 'GitHub upload failed (${put.statusCode}): ${put.body}';
        return false;
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _pruneViaRest(Map<String, String> headers) async {
    try {
      final list = await http.get(
        Uri.parse('$_githubApiBase/contents/$githubFolder'),
        headers: headers,
      );
      if (list.statusCode != 200) return;
      final items = jsonDecode(list.body) as List;
      final files = items
          .whereType<Map<String, dynamic>>()
          .where((f) => (f['name'] as String? ?? '').endsWith('.db'))
          .toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      while (files.length > 90) {
        final oldest = files.removeAt(0);
        final sha = oldest['sha'] as String?;
        final name = oldest['name'] as String;
        if (sha == null) continue;
        await http.delete(
          Uri.parse('$_githubApiBase/contents/$githubFolder/$name'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': 'prune old db backup $name',
            'sha': sha,
            'branch': 'main',
          }),
        );
      }
    } catch (_) {}
  }

  // ===================== long-term local backups =====================
  Future<Directory?> _prepareWritableDirectory(String path) async {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return _writable(dir.path) ? dir : null;
    } catch (_) {
      return null;
    }
  }

  /// Check if backup is needed
  Future<bool> isBackupNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackupTime = prefs.getInt('last_backup_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    return (now - lastBackupTime) > (backupIntervalDays * 24 * 60 * 60 * 1000);
  }

  /// Record that a backup cycle ran.
  Future<bool> performBackup(String databasePath) async {
    try {
      final dbFile = File(databasePath);
      if (!dbFile.existsSync()) {
        return false;
      }

      final backupName =
          'randil_pos_backup_${DateTime.now().toIso8601String()}.db';
      final backupSize = dbFile.lengthSync();

      final prefs = await SharedPreferences.getInstance();
      final backups = prefs.getStringList('backup_history') ?? [];

      backups.add(jsonEncode({
        'name': backupName,
        'size': backupSize,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'path': databasePath,
        'status': 'pending_upload',
      }));

      if (backups.length > 30) {
        backups.removeAt(0);
      }

      await prefs.setStringList('backup_history', backups);
      await prefs.setInt(
          'last_backup_timestamp', DateTime.now().millisecondsSinceEpoch);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clean up old backup records (older than 4 months)
  Future<bool> cleanupOldBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backups = prefs.getStringList('backup_history') ?? [];

      final now = DateTime.now().millisecondsSinceEpoch;
      final fourMonthsMs = autoDeleteDays * 24 * 60 * 60 * 1000;

      final filteredBackups = backups.where((backup) {
        final data = jsonDecode(backup);
        final backupTime = data['timestamp'] as int;
        return (now - backupTime) < fourMonthsMs;
      }).toList();

      await prefs.setStringList('backup_history', filteredBackups);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get local backup directory (long-term copies kept by the shop owner)
  Future<Directory> getBackupDirectory({String? customPath}) async {
    if (customPath != null && customPath.trim().isNotEmpty) {
      final configured =
          await _prepareWritableDirectory(customPath.trim());
      if (configured != null) {
        return configured;
      }
    }

    if (Platform.isWindows) {
      final preferred =
          await _prepareWritableDirectory(preferredWindowsBackupPath);
      if (preferred != null) {
        return preferred;
      }
    }

    final candidates = <String>[];
    try {
      final docDir = await getApplicationDocumentsDirectory();
      candidates.add(p.join(docDir.path, 'randil_backups'));
    } catch (_) {}

    try {
      final supportDir = await getApplicationSupportDirectory();
      candidates.add(p.join(supportDir.path, 'randil_backups'));
    } catch (_) {}

    try {
      final tempDir = await getTemporaryDirectory();
      candidates.add(p.join(tempDir.path, 'randil_backups'));
    } catch (_) {}

    for (final path in candidates) {
      final dir = await _prepareWritableDirectory(path);
      if (dir != null) {
        return dir;
      }
    }

    throw const FileSystemException(
      'Unable to create a writable backup directory in any fallback location',
    );
  }

  /// Save an encrypted long-term backup in the chosen folder.
  Future<String?> saveLocalBackup(
    String databasePath, {
    String? customPath,
  }) async {
    try {
      _lastError = null;
      await DatabaseService().database;

      var sourcePath = databasePath;
      var dbFile = File(sourcePath);
      if (!dbFile.existsSync()) {
        sourcePath = await DatabaseService().getDatabasePath();
        dbFile = File(sourcePath);
      }

      if (!dbFile.existsSync()) {
        _lastError = 'Database file not found at $sourcePath';
        return null;
      }

      final backupDir = await getBackupDirectory(customPath: customPath);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupFileName = 'backup_$timestamp.db';
      final backupPath = p.join(backupDir.path, backupFileName);
      final tempPath = '$backupPath.tmp';

      var backupCreated = false;
      try {
        final db = await DatabaseService().database;
        final escapedTemp = tempPath.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$escapedTemp'");
        backupCreated = File(tempPath).existsSync();
      } catch (_) {
        backupCreated = false;
      }

      if (!backupCreated) {
        try {
          await dbFile.copy(tempPath);
          backupCreated = File(tempPath).existsSync();
        } catch (_) {
          backupCreated = false;
        }
      }

      if (!backupCreated) {
        _lastError = 'Backup file was not created at $tempPath';
        return null;
      }

      final secure = SecureStorageService();
      final encrypted = secure.encryptFile(tempPath, backupPath);
      try {
        File(tempPath).deleteSync();
      } catch (_) {}

      if (!encrypted || !File(backupPath).existsSync()) {
        _lastError =
            'Backup could not be encrypted. No plaintext backup was written.';
        return null;
      }

      final backupFile = File(backupPath);

      final prefs = await SharedPreferences.getInstance();
      final localBackups = prefs.getStringList('local_backups') ?? [];

      localBackups.add(jsonEncode({
        'name': backupFileName,
        'path': backupPath,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'size': backupFile.lengthSync(),
        'location': backupDir.path,
      }));

      await prefs.setStringList('local_backups', localBackups);

      return backupPath;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<BackupRunResult> backupNowDetailed({
    required String databasePath,
    required ShopSettings settings,
  }) async {
    // 1. Immediate crash-safe copy in the temp folder (always).
    final tempSnapshot = await _writeLocalSnapshot();

    // 2. Encrypted long-term copy in the shop's own backup folder.
    final localBackupPath = await saveLocalBackup(
      databasePath,
      customPath: settings.backupLocalPath,
    );

    if (localBackupPath == null) {
      return BackupRunResult(
        localSaved: tempSnapshot != null,
        cloudEnabled: settings.enableGoogleDriveBackup,
        cloudUploaded: false,
        localPath: tempSnapshot,
        message: _lastError ?? 'Backup creation failed',
      );
    }

    await performBackup(databasePath);

    var uploaded = false;
    if (settings.enableGoogleDriveBackup) {
      final rawToken =
          SecureStorageService().decryptString(settings.googleDriveAccessToken);
      if (rawToken == null || rawToken.trim().isEmpty) {
        return BackupRunResult(
          localSaved: true,
          cloudEnabled: true,
          cloudUploaded: false,
          localPath: localBackupPath,
          message: 'Saved Google Drive token could not be decrypted. '
              'Re-enter the token in Backup Settings.',
        );
      }

      uploaded = await uploadBackupToGoogleDrive(
        backupFilePath: tempSnapshot ?? localBackupPath,
        accessToken: rawToken,
        folderId: settings.googleDriveFolderId.trim().isEmpty
            ? defaultGoogleDriveFolderId
            : settings.googleDriveFolderId,
        fileName: driveFileName,
      );

      return BackupRunResult(
        localSaved: true,
        cloudEnabled: true,
        cloudUploaded: uploaded,
        localPath: localBackupPath,
        message: uploaded
            ? null
            : (_lastError ?? 'Google Drive upload failed'),
      );
    }

    return BackupRunResult(
      localSaved: true,
      cloudEnabled: false,
      cloudUploaded: false,
      localPath: localBackupPath,
    );
  }

  Future<bool> backupNow({
    required String databasePath,
    required ShopSettings settings,
  }) async {
    final result = await backupNowDetailed(
      databasePath: databasePath,
      settings: settings,
    );
    return result.isSuccess;
  }

  /// Get storage space warnings
  Future<String?> getStorageWarning({String? customPath}) async {
    try {
      final backupDir = await getBackupDirectory(customPath: customPath);
      final files = backupDir.listSync();

      double totalSize = 0;
      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      final sizeInGB = totalSize / (1024 * 1024 * 1024);

      if (sizeInGB > 1.0) {
        return 'Storage warning: Backups using ${sizeInGB.toStringAsFixed(2)}GB. Consider cleaning old backups.';
      }

      if (sizeInGB > 0.5) {
        return 'Storage notice: Backups using ${sizeInGB.toStringAsFixed(2)}GB.';
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Restore from backup (encrypted or legacy plaintext).
  Future<bool> restoreFromBackup(
      String backupPath, String targetDatabasePath) async {
    try {
      final backupFile = File(backupPath);
      if (!backupFile.existsSync()) {
        return false;
      }
      return SecureStorageService().decryptFile(backupPath, targetDatabasePath);
    } catch (e) {
      return false;
    }
  }

  /// Get all local backups
  Future<List<Map<String, dynamic>>> getLocalBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backups = prefs.getStringList('local_backups') ?? [];

      return backups
          .map((backup) => jsonDecode(backup) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Delete old backups manually
  Future<bool> deleteOldBackups({
    int olderThanDays = 120,
    String? customPath,
  }) async {
    try {
      final backupDir = await getBackupDirectory(customPath: customPath);
      final files = backupDir.listSync();
      final now = DateTime.now();

      for (var file in files) {
        if (file is File) {
          final stat = file.statSync();
          final fileAge = now.difference(stat.modified);

          if (fileAge.inDays > olderThanDays) {
            await file.delete();
          }
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  // ===================== schedules =====================
  Timer? _backupTimer;
  Timer? _snapshotTimer;

  /// One full pass every hour: temp copy, encrypted long-term copy, and both
  /// cloud destinations (with a dated archive kept for history).
  Future<void> _runHourlyCycle(
    String databasePath, {
    ShopSettings? settings,
  }) async {
    try {
      _lastError = null;
      _lastCloudStatus = 'Automatic backup running...';

      final tempSnapshot = await _writeLocalSnapshot();

      final localPath = settings == null
          ? await saveLocalBackup(databasePath)
          : await saveLocalBackup(databasePath,
              customPath: settings.backupLocalPath);

      if (tempSnapshot != null) {
        await pushSnapshotToGithub(snapshotPath: tempSnapshot, archive: true);

        if (settings != null &&
            settings.enableGoogleDriveBackup &&
            localPath != null) {
          final rawToken = SecureStorageService()
              .decryptString(settings.googleDriveAccessToken);
          if (rawToken != null && rawToken.trim().isNotEmpty) {
            final stamp = _fileStamp(DateTime.now());
            final archived = await _archiveCopy(
              tempSnapshot,
              'pos_hourly_$stamp.db',
            );
            final uploaded = await uploadBackupToGoogleDrive(
              backupFilePath: archived ?? tempSnapshot,
              accessToken: rawToken.trim(),
              folderId: settings.googleDriveFolderId.trim().isEmpty
                  ? defaultGoogleDriveFolderId
                  : settings.googleDriveFolderId,
              fileName: 'RandilPOS_hourly_$stamp.db',
            );
            _lastCloudStatus = uploaded
                ? 'Google Drive updated ${_time(DateTime.now())}'
                : 'Google Drive upload failed: ${_lastError ?? 'unknown'}';
            // Keep the main Drive file current too, so recovery is always
            // possible from a single known file.
            await uploadBackupToGoogleDrive(
              backupFilePath: tempSnapshot,
              accessToken: rawToken.trim(),
              folderId: settings.googleDriveFolderId.trim().isEmpty
                  ? defaultGoogleDriveFolderId
                  : settings.googleDriveFolderId,
              fileName: driveFileName,
            );
          } else {
            _lastCloudStatus = 'Google Drive token unavailable - skipped.';
          }
        }
      }

      await cleanupOldBackups();
    } catch (e) {
      _lastError = e.toString();
      _lastCloudStatus = 'Automatic backup failed: $e';
    }
  }

  Future<String?> _archiveCopy(String source, String fileName) async {
    try {
      final dir = await tempSnapshotDirectory();
      final target = p.join(dir.path, fileName);
      File(source).copySync(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  void startAutoBackup(String databasePath, {ShopSettings? settings}) {
    stopAutoBackup();
    // First cloud push shortly after launch so a fresh client PC gets its
    // first GitHub + Drive backup within ~30 seconds, then every hour.
    Timer(const Duration(seconds: 30), () async {
      _runHourlyCycle(databasePath, settings: settings);
    });
    _backupTimer = Timer.periodic(
      const Duration(hours: 1),
      (timer) async {
        _runHourlyCycle(databasePath, settings: settings);
      },
    );
    // Keep a fresh local copy every 15 minutes even when nothing is sold, so
    // GRNs, expenses and product edits are covered too.
    _snapshotTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await _writeLocalSnapshot();
    });
  }

  void stopAutoBackup() {
    _backupTimer?.cancel();
    _backupTimer = null;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
  }

  /// Initialize backup system on app startup
  Future<void> initializeBackupSystem(
    String databasePath, {
    ShopSettings? settings,
  }) async {
    await loadGithubCredentials();

    // A copy is captured immediately on launch so the first cloud push always
    // has fresh data even if nothing changed after startup.
    await _writeLocalSnapshot();

    if (await isBackupNeeded()) {
      await performBackup(databasePath);
      await saveLocalBackup(
        databasePath,
        customPath: settings?.backupLocalPath,
      );
    }

    await cleanupOldBackups();

    startAutoBackup(databasePath, settings: settings);
  }

  // ===================== manual / legacy entry point =====================
  /// Run one full backup pass right now. Re-entrant calls are coalesced — if a
  /// pass is already running, exactly one more runs when it finishes.
  Future<void> backupAfterSale() async {
    await _runCloudPass();
  }
}
