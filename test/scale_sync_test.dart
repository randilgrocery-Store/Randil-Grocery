import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The admin PC pushes the label-scale layout inside the LAN catalog; a
/// terminal must adopt it without touching any other local setting, and the
/// catalog revision must change so that terminals actually re-pull it.
void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    BackupService.transactionNotificationsEnabled = false;
    await DatabaseService().debugUseDatabase(db);
  });

  tearDown(() async {
    DatabaseService().debugResetDatabase();
    BackupService.transactionNotificationsEnabled = true;
    await db.close();
  });

  test('applyScaleSettingsFromServer updates only the scale fields', () async {
    final service = DatabaseService();
    final before = await service.getShopSettings();
    expect(before.scaleBarcodeEnabled, isFalse);

    await service.applyScaleSettingsFromServer({
      'enabled': true,
      'prefix': '2',
      'length': 12,
      'itemLength': 5,
      'priceMode': false,
      'checkDigit': true,
    });

    final after = await service.getShopSettings();
    expect(after.scaleBarcodeEnabled, isTrue);
    expect(after.scaleBarcodePrefix, '2');
    expect(after.scaleBarcodeLength, 12);
    expect(after.scaleBarcodeItemLength, 5);
    expect(after.scaleBarcodePriceMode, isFalse);
    expect(after.scaleBarcodeCheckDigit, isTrue);
    // Every other machine-local setting stays untouched.
    expect(after.shopName, before.shopName);
    expect(after.networkPort, before.networkPort);
    expect(after.printerName, before.printerName);
  });

  test('a changed scale layout bumps the catalog revision', () async {
    final service = DatabaseService();
    final rev1 = await service.catalogRevision();
    await service.applyScaleSettingsFromServer({
      'enabled': true,
      'prefix': '2',
      'length': 12,
      'itemLength': 5,
      'priceMode': false,
      'checkDigit': true,
    });
    final rev2 = await service.catalogRevision();
    expect(rev2, isNot(equals(rev1)));
  });

  test('left-out keys keep the locally configured value', () async {
    final service = DatabaseService();
    await service.applyScaleSettingsFromServer({'enabled': true});
    final after = await service.getShopSettings();
    expect(after.scaleBarcodeEnabled, isTrue);
    expect(after.scaleBarcodePrefix, '2');
    expect(after.scaleBarcodeLength, 12);
    expect(after.scaleBarcodeItemLength, 5);
  });
}