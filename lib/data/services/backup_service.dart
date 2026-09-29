import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_service.dart';
import '../models/shop_settings.dart';
import '../../core/utils/secure_storage.dart';

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

class BackupService {
  static const String preferredWindowsBackupPath =
      r'C:\Program Files\POS\backups';
  static const String googleDriveApiUrl =
      'https://www.googleapis.com/drive/v3/files';
  static const String uploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=media';
    static const String multipartUploadUrl =
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart';

  // Google API credentials
  static const String clientId = ''; // Will be set during setup
  static const String clientSecret = ''; // Will be set during setup

  // Shared Google Drive folder that the shop backups are uploaded into.
  static const String defaultGoogleDriveFolderId =
      '1N0YvowmSVGnI-X6MWfQf3o6ux880JHom';

  // Backup configuration
  static const int backupIntervalDays = 1;
  static const int autoDeleteDays = 120; // 4 months

  Future<Directory?> _prepareWritableDirectory(String path) async {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final probe = File('${dir.path}\\.write_probe');
      probe.writeAsStringSync('ok');
      if (probe.existsSync()) {
        probe.deleteSync();
      }

      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getStorageInfo() async {
    try {
      // This is a placeholder - you'd need to use Google Drive API
      // to get actual storage info
      return 'Storage check not implemented yet';
    } catch (e) {
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

  /// Perform automatic backup to Google Drive
  Future<bool> performBackup(String databasePath) async {
    try {
      // Get the database file
      final dbFile = File(databasePath);
      if (!dbFile.existsSync()) {
        return false;
      }

      // Read database as bytes
      final bytes = await dbFile.readAsBytes();

      // Create backup metadata
      final backupName =
          'randil_pos_backup_${DateTime.now().toIso8601String()}.db';
      final backupSize = bytes.length;

      // Store backup info locally (for later upload to cloud)
      final prefs = await SharedPreferences.getInstance();
      final backups = prefs.getStringList('backup_history') ?? [];

      // Add new backup info
      backups.add(jsonEncode({
        'name': backupName,
        'size': backupSize,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'path': databasePath,
        'status': 'pending_upload',
      }));

      // Keep only last 30 backups
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

  /// Clean up old backups (older than 4 months)
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

  /// Get local backup directory
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
      candidates.add('${docDir.path}\\randil_backups');
    } catch (_) {}

    try {
      final supportDir = await getApplicationSupportDirectory();
      candidates.add('${supportDir.path}\\randil_backups');
    } catch (_) {}

    try {
      final tempDir = await getTemporaryDirectory();
      candidates.add('${tempDir.path}\\randil_backups');
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

  String? _lastError;

  String? get lastError => _lastError;

  /// Save backup locally
  Future<String?> saveLocalBackup(
    String databasePath, {
    String? customPath,
  }) async {
    try {
      _lastError = null;
      // Make sure database is initialized and physically present before backup.
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
      final backupPath = '${backupDir.path}/$backupFileName';
      final tempPath = '$backupPath.tmp';

      // Create the backup file then encrypt it in place with DPAPI so that
      // the file on disk is never stored in plaintext.
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
        // Fall back to a direct file copy, then encrypt the copy.
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

      // Store backup record
      final prefs = await SharedPreferences.getInstance();
      final localBackups = prefs.getStringList('local_backups') ?? [];

      localBackups.add(jsonEncode({
        'name': backupFileName,
        'path': backupPath,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'size': await backupFile.length(),
        'location': backupDir.path,
      }));

      await prefs.setStringList('local_backups', localBackups);

      return backupPath;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<bool> uploadBackupToGoogleDrive({
    required String backupFilePath,
    required String accessToken,
    String? folderId,
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

      final backupName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'randil_backup_${DateTime.now().millisecondsSinceEpoch}.db';

      final metadata = {
        'name': backupName,
        if (folderId != null && folderId.trim().isNotEmpty)
          'parents': [folderId.trim()],
      };

      final boundary =
          'boundary_${DateTime.now().millisecondsSinceEpoch}_${backupName.hashCode.abs()}';
      final fileBytes = await file.readAsBytes();
      final metadataJson = jsonEncode(metadata);

      final request = http.Request('POST', Uri.parse(multipartUploadUrl));
      request.headers['Authorization'] = 'Bearer ${accessToken.trim()}';
      request.headers['Content-Type'] =
          'multipart/related; boundary=$boundary';

      final bodyBytes = <int>[];
      bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
      bodyBytes.addAll(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      );
      bodyBytes.addAll(utf8.encode(metadataJson));
      bodyBytes.addAll(utf8.encode('\r\n'));

      bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
      bodyBytes.addAll(
        utf8.encode('Content-Type: application/octet-stream\r\n\r\n'),
      );
      bodyBytes.addAll(fileBytes);
      bodyBytes.addAll(utf8.encode('\r\n--$boundary--\r\n'));

      request.bodyBytes = bodyBytes;

      final response = await request.send();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseText = await response.stream.bytesToString();
        _lastError =
            'Google Drive upload failed (${response.statusCode}): $responseText';
      }
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<BackupRunResult> backupNowDetailed({
    required String databasePath,
    required ShopSettings settings,
  }) async {
    final localBackupPath = await saveLocalBackup(
      databasePath,
      customPath: settings.backupLocalPath,
    );

    if (localBackupPath == null) {
      return BackupRunResult(
        localSaved: false,
        cloudEnabled: settings.enableGoogleDriveBackup,
        cloudUploaded: false,
        message: _lastError ?? 'Local backup failed',
      );
    }

    await performBackup(databasePath);

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

      final uploaded = await uploadBackupToGoogleDrive(
        backupFilePath: localBackupPath,
        accessToken: rawToken,
        folderId: settings.googleDriveFolderId.trim().isEmpty
            ? defaultGoogleDriveFolderId
            : settings.googleDriveFolderId,
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

      // Convert to GB
      final sizeInGB = totalSize / (1024 * 1024 * 1024);

      // Warning if more than 1GB local backup
      if (sizeInGB > 1.0) {
        return 'Storage warning: Backups using ${sizeInGB.toStringAsFixed(2)}GB. Consider cleaning old backups.';
      }

      // Warning if more than 500MB
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

  /// Schedule automatic backups.
  ///
  /// Every 1 hour: save an encrypted local backup, upload to Google Drive
  /// (when enabled) and push a plain .db snapshot to the GitHub repo, all
  /// in the same cycle so the database lives in all three places together.
  Timer? _backupTimer;
  Timer? _snapshotTimer;

  String _lastCloudStatus = '';
  String get lastCloudStatus => _lastCloudStatus;

  String? get githubSyncPath => _githubSyncPath;
  String? _githubSyncPath;

  String? _githubToken;

  /// Optional GitHub personal-access token. When the client machine does not
  /// have git installed, backups are still pushed through the GitHub REST API
  /// using this token, so the hourly GitHub backup works everywhere.
  String? get githubToken => _githubToken;

  Future<void> loadGithubCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _githubSyncPath = prefs.getString('github_repo_path');
      final enc = prefs.getString('github_token');
      _githubToken =
          (enc == null || enc.isEmpty) ? null : SecureStorageService().decryptString(enc);
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

  /// Locate the local clone of the GitHub backup repo. Uses the folder set
  /// in settings; falls back to the known development location.
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

  /// Copy a fresh plain .db snapshot into the GitHub repo's
  /// `database-backups/` folder and push it (git when available, otherwise
  /// the GitHub REST API using a stored token).
  Future<bool> pushSnapshotToGithub({String? snapshotPath}) async {
    _lastError = null;
    try {
      final String snap;
      if (snapshotPath != null && File(snapshotPath).existsSync()) {
        snap = snapshotPath;
      } else {
        final created = await DatabaseService().createDbSnapshot();
        if (created == null) {
          _lastError = 'Snapshot could not be created for GitHub push.';
          return false;
        }
        snap = created;
      }

      final repo = await _resolveGithubRepo();
      if (repo != null) {
        try {
          final pushed = await _pushViaGit(snap, repo);
          _lastCloudStatus = pushed
              ? 'Last GitHub push: ${DateTime.now().toLocal()}'
              : 'GitHub git push failed: $_lastError';
          if (pushed || _lastError != 'GitHub git not available on this machine.') {
            return pushed;
          }
          // git unavailable - fall through to the REST API.
        } catch (e) {
          _lastError = e.toString();
          return false;
        }
      }

      if (_githubToken == null || _githubToken!.trim().isEmpty) {
        _lastError = repo == null
            ? 'GitHub sync folder not set and no GitHub token saved.'
            : 'git is not available on this machine and no GitHub token saved.';
        return false;
      }

      final pushed = await _pushViaRest(snap);
      _lastCloudStatus = pushed
          ? 'Last GitHub push: ${DateTime.now().toLocal()}'
          : 'GitHub REST push failed: $_lastError';
      return pushed;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  static Future<bool> _gitAvailable() async {
    try {
      final r = await Process.run('git', ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pushViaGit(String snap, String repo) async {
    final backupsDir = Directory('$repo\\database-backups');
    if (!backupsDir.existsSync()) {
      backupsDir.createSync(recursive: true);
    }

    final fileName = File(snap).uri.pathSegments.isNotEmpty
        ? File(snap).uri.pathSegments.last
        : 'randil_grocery_pos.db';
    File(snap).copySync('${backupsDir.path}\\$fileName');

    _pruneRepoBackups(backupsDir, keep: 90);

    final now = DateTime.now().toLocal();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    Future<int?> runGit(List<String> args) async {
      try {
        final r = await Process.run('git', args, workingDirectory: repo);
        return r.exitCode;
      } catch (_) {
        return null;
      }
    }

    final push = await runGit(['push', 'origin', 'main']);
    if (push == null) {
      _lastError = 'GitHub git not available on this machine.';
      return false;
    }
    if (push != 0) {
      // Try to add/commit/push in one go (auth may be cached or none).
      await runGit(['add', '-A', 'database-backups']);
      await runGit(['commit', '-m', 'db backup $stamp']);
      final retry = await runGit(['push', 'origin', 'main']);
      if (retry == null || retry != 0) {
        _lastError = 'git push failed with exit code ${retry ?? 'unknown'}.';
        return false;
      }
    }
    return true;
  }

  static const String _githubApiBase =
      'https://api.github.com/repos/randilgrocery-Store/Randil-Grocery';

  Future<bool> _pushViaRest(String snap) async {
    final fileName = File(snap).uri.pathSegments.isNotEmpty
        ? File(snap).uri.pathSegments.last
        : 'randil_grocery_pos.db';
    final path = 'database-backups/$fileName';
    final bytes = await File(snap).readAsBytes();
    final content = base64Encode(bytes);

    final headers = {
      'Authorization': 'Bearer ${_githubToken!.trim()}',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };

    try {
      // Existing file? Fetch its sha so we can overwrite it.
      String? sha;
      final existing =
          await http.get(Uri.parse('$_githubApiBase/contents/$path'),
              headers: headers);
      if (existing.statusCode == 200) {
        final decoded = jsonDecode(existing.body) as Map<String, dynamic>;
        sha = decoded['sha'] as String?;
      }

      final put = await http.put(
        Uri.parse('$_githubApiBase/contents/$path'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': 'db backup ${DateTime.now().toLocal().toIso8601String()}',
          'content': content,
          'branch': 'main',
          if (sha != null) 'sha': sha,
        }),
      );
      if (put.statusCode != 200 && put.statusCode != 201) {
        _lastError = 'GitHub REST upload failed (${put.statusCode}): ${put.body}';
        return false;
      }

      await _pruneViaRest(headers);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _pruneViaRest(Map<String, String> headers) async {
    try {
      final list = await http.get(
        Uri.parse('$_githubApiBase/contents/database-backups'),
        headers: headers,
      );
      if (list.statusCode != 200) return;
      final items = jsonDecode(list.body) as List;
      final files = items
          .whereType<Map<String, dynamic>>()
          .where((f) => (f['name'] as String? ?? '').endsWith('.db'))
          .toList()
        ..sort((a, b) => (a['name'] as String)
            .compareTo(b['name'] as String));
      while (files.length > 90) {
        final oldest = files.removeAt(0);
        final sha = oldest['sha'] as String?;
        final name = oldest['name'] as String;
        if (sha == null) continue;
        await http.delete(
          Uri.parse('$_githubApiBase/contents/database-backups/$name'),
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

  static void _pruneRepoBackups(Directory dir, {required int keep}) {
    try {
      final files = (dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.db'))
              .toList())
        ..sort((a, b) =>
            a.statSync().modified.compareTo(b.statSync().modified));
      while (files.length > keep) {
        files.removeAt(0).deleteSync();
      }
    } catch (_) {}
  }

  Future<void> _runHourlyCycle(
    String databasePath, {
    ShopSettings? settings,
  }) async {
    try {
      _lastError = null;
      _lastCloudStatus = 'Hourly backup running...';

      final localPath = settings == null
          ? await saveLocalBackup(databasePath)
          : await saveLocalBackup(databasePath,
              customPath: settings.backupLocalPath);

      if (settings != null &&
          settings.enableGoogleDriveBackup &&
          localPath != null) {
        final rawToken =
            SecureStorageService()
                .decryptString(settings.googleDriveAccessToken);
        if (rawToken != null && rawToken.trim().isNotEmpty) {
          final uploaded = await uploadBackupToGoogleDrive(
            backupFilePath: localPath,
            accessToken: rawToken.trim(),
            folderId: settings.googleDriveFolderId.trim().isEmpty
                ? defaultGoogleDriveFolderId
                : settings.googleDriveFolderId,
          );
          _lastCloudStatus = uploaded
              ? 'Last Google Drive upload: '
                  '${DateTime.now().toIso8601String()}'
              : 'Google Drive upload failed: ${_lastError ?? 'unknown'}';
        } else {
          _lastCloudStatus = 'Google Drive token unavailable - skipped.';
        }
      }

      await cleanupOldBackups();

      // GitHub push shares the same hourly cycle as the Drive upload.
      await pushSnapshotToGithub();
      if (_lastError != null) {
        _lastCloudStatus = 'GitHub push failed: $_lastError';
      }
    } catch (e) {
      _lastError = e.toString();
      _lastCloudStatus = 'Hourly backup failed: $e';
    }
  }

  void startAutoBackup(String databasePath, {ShopSettings? settings}) {
    stopAutoBackup();
    // First cloud push shortly after launch so a fresh client PC gets its
    // first GitHub + Drive backup within ~30 seconds, then every 1 hour.
    Timer(const Duration(seconds: 30), () async {
      _runHourlyCycle(databasePath, settings: settings);
    });
    // Full cycle (local + Drive + GitHub) once every 1 hour.
    _backupTimer = Timer.periodic(
      const Duration(hours: 1),
      (timer) async {
        _runHourlyCycle(databasePath, settings: settings);
      },
    );
    // Keep a fresh snapshot locally every 15 minutes so non-sale changes
    // (GRNs, expenses, product edits, ...) are never lost either.
    _snapshotTimer = Timer.periodic(const Duration(minutes: 15), (timer) async {
      await DatabaseService().createDbSnapshot();
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

    // A snapshot is captured immediately on launch so the first cloud push
    // always has fresh data even if nothing changed after startup.
    await DatabaseService().createDbSnapshot();

    // Check if backup is needed
    if (await isBackupNeeded()) {
      await performBackup(databasePath);
      await saveLocalBackup(
        databasePath,
        customPath: settings?.backupLocalPath,
      );
    }

    // Clean up old backups
    await cleanupOldBackups();

    // Start automatic backup schedule
    startAutoBackup(databasePath, settings: settings);
  }
}
