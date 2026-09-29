import 'package:flutter/material.dart';

import '../../core/utils/secure_storage.dart';
import '../../data/database/database_service.dart';
import '../../data/models/shop_settings.dart';

class SettingsProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  ShopSettings _settings = ShopSettings();

  ShopSettings get settings => _settings;

  Future<void> loadSettings() async {
    _settings = await _dbService.getShopSettings();
    notifyListeners();
  }

  Future<void> updateSettings(ShopSettings settings) async {
    await _dbService.updateShopSettings(settings);
    _settings = settings;
    notifyListeners();
  }

  Future<void> updateShopName(String name) async {
    await updateSettings(_settings.copyWith(shopName: name));
  }

  Future<void> updateAddress(String address) async {
    await updateSettings(_settings.copyWith(address: address));
  }

  Future<void> updatePhone(String phone) async {
    await updateSettings(_settings.copyWith(phone: phone));
  }

  Future<void> updateEmail(String email) async {
    await updateSettings(_settings.copyWith(email: email));
  }

  Future<void> updateCurrency(String currency) async {
    await updateSettings(_settings.copyWith(currency: currency));
  }

  Future<void> updateTaxSettings(bool enable, double percentage) async {
    await updateSettings(
      _settings.copyWith(enableTax: enable, taxPercentage: percentage),
    );
  }

  Future<void> updatePrinterSettings(String name, bool enable) async {
    await updateSettings(
      _settings.copyWith(printerName: name, enablePrinting: enable),
    );
  }

  Future<void> updateBackupSettings({
    required String backupLocalPath,
    required bool enableGoogleDriveBackup,
    required String googleDriveAccessToken,
    required String googleDriveFolderId,
    required String googleDriveAdminEmail,
  }) async {
    final secure = SecureStorageService();
    await updateSettings(
      _settings.copyWith(
        backupLocalPath: backupLocalPath,
        enableGoogleDriveBackup: enableGoogleDriveBackup,
        googleDriveAccessToken:
            secure.encryptString(googleDriveAccessToken),
        googleDriveFolderId: googleDriveFolderId,
        googleDriveAdminEmail: googleDriveAdminEmail,
      ),
    );
  }

  Future<void> updateNetworkSettings({
    bool? isServerMode,
    int? networkPort,
    String? serverIpFallback,
    bool? useAutoDiscovery,
  }) async {
    await updateSettings(
      _settings.copyWith(
        isServerMode: isServerMode,
        networkPort: networkPort,
        serverIpFallback: serverIpFallback,
        useAutoDiscovery: useAutoDiscovery,
      ),
    );
  }
}
