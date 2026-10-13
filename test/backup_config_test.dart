import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/core/utils/secure_storage.dart';
import 'package:randil_grocery_pos/data/models/shop_settings.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the two delivery-critical backup behaviours:
///
///  * [BackupService.githubReady] must tell the truth about whether a GitHub
///    push can actually run here, so the Settings screen can warn instead of
///    letting a misconfigured cloud backup fail silently.
///  * The durable local backup must be detectable ([newestLocalBackupAt]) and
///    not rewritten when a fresh copy already exists.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = BackupService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Point the developer fallback at a folder that cannot exist, so this test
    // asserts the real "not configured" path no matter which PC runs it.
    BackupService.devRepoFallback = r'C:\__randil_no_such_repo__';
    await svc.setGithubToken('');
    await svc.setGithubSyncPath('');
  });

  tearDown(() {
    BackupService.devRepoFallback = r'D:\Randil Grocery POS';
  });

  group('githubReady', () {
    test('is false with no token and no repo folder', () {
      expect(svc.githubReady, isFalse);
    });

    test('is true once a token is saved (REST route)', () async {
      await svc.setGithubToken('ghp_example_token_value');
      expect(svc.githubReady, isTrue);
    });

    test('is true when a local repo folder is configured (git route)',
        () async {
      final dir = await Directory.systemTemp.createTemp('randil_repo_test');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      await svc.setGithubSyncPath(dir.path);
      expect(svc.githubReady, isTrue);
    });
  });

  group('durable local backup', () {
    test('newestLocalBackupAt returns the newest recorded timestamp',
        () async {
      final older = DateTime.now().subtract(const Duration(days: 3));
      final newer = DateTime.now().subtract(const Duration(hours: 2));
      SharedPreferences.setMockInitialValues({
        'local_backups': [
          '{"timestamp":${older.millisecondsSinceEpoch}}',
          '{"timestamp":${newer.millisecondsSinceEpoch}}',
        ],
      });

      final got = await svc.newestLocalBackupAt();
      expect(got, isNotNull);
      expect(got!.millisecondsSinceEpoch, newer.millisecondsSinceEpoch);
    });

    test('newestLocalBackupAt is null when no backup is recorded', () async {
      expect(await svc.newestLocalBackupAt(), isNull);
    });

    test('ensureRecentLocalBackup skips the write when a fresh copy exists',
        () async {
      SharedPreferences.setMockInitialValues({
        'local_backups': [
          '{"timestamp":${DateTime.now().millisecondsSinceEpoch}}',
        ],
      });
      // Fresh (< 6h) => no DB VACUUM/no encryption, returns null quickly.
      expect(await svc.ensureRecentLocalBackup(), isNull);
    });
  });

  group('durable Google Drive credentials', () {
    test('blank fields keep the saved credentials', () async {
      await svc.setDriveOAuth(
        clientId: 'cid',
        clientSecret: 'secret',
        refreshToken: 'refresh',
      );
      expect(await svc.hasDriveRefreshCredentials(), isTrue);

      // Saving the form with all three blank must not wipe what is stored.
      await svc.setDriveOAuth(
        clientId: '',
        clientSecret: '',
        refreshToken: '',
      );
      final oauth = await svc.loadDriveOAuth();
      expect(await svc.hasDriveRefreshCredentials(), isTrue);
      expect(oauth['clientId'], 'cid');
      expect(oauth['refreshToken'], 'refresh');
    });

    test('driveReady is true when a refresh credential is saved', () async {
      await svc.setDriveOAuth(
        clientId: 'cid',
        clientSecret: 'secret',
        refreshToken: 'refresh',
      );
      expect(await svc.driveReady(ShopSettings()), isTrue);
    });

    test('driveReady falls back to the pasted access token', () async {
      final settings = ShopSettings(
        googleDriveAccessToken:
            SecureStorageService().encryptString('ya29.example'),
      );
      expect(await svc.driveReady(settings), isTrue);
    });

    test('driveReady is false when nothing is saved', () async {
      expect(await svc.driveReady(ShopSettings()), isFalse);
    });
  });

  group('BackupRunResult.summary', () {
    test('names all three destinations', () {
      const result = BackupRunResult(
        localSaved: true,
        githubUploaded: true,
        driveConfigured: true,
        driveUploaded: false,
      );
      expect(result.summary, contains('Local saved'));
      expect(result.summary, contains('GitHub uploaded'));
      expect(result.summary, contains('Drive failed'));
    });

    test('reports Drive off when it is not configured', () {
      const result = BackupRunResult(
        localSaved: true,
        githubUploaded: false,
        driveConfigured: false,
        driveUploaded: false,
      );
      expect(result.summary, contains('GitHub failed'));
      expect(result.summary, contains('Drive off'));
    });
  });
}
