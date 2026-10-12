import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/database/database_service.dart';
import 'package:randil_grocery_pos/data/services/backup_service.dart';
import 'package:randil_grocery_pos/data/services/scale_barcode.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reproduces the shop's real scale label and the product barcode it must find.
///
/// The scale prints `0000010002100`; with the shop's layout (prefix `00`, item
/// 5 digits, weight 5 digits, check 1) that decodes to item `00010` at 0.210 kg,
/// but the Banana product was entered with the barcode `0000010`. The two differ
/// only in leading zeros, so the lookup must tolerate that.
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

  Future<void> insertProduct(String id, String name, String barcode,
      {int soldByWeight = 0}) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('products', {
      'id': id,
      'name': name,
      'barcode': barcode,
      'categoryId': 'cat1',
      'buyingPrice': 150.0,
      'sellingPrice': 200.0,
      'quantity': 20.0,
      'soldByWeight': soldByWeight,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  test('the real scale label resolves to the Banana product', () async {
    await insertProduct('banana', 'Banana', '0000010', soldByWeight: 1);

    const config = ScaleBarcodeConfig(
      enabled: true,
      prefix: '00',
      totalLength: 13,
      itemLength: 5,
      priceMode: false,
      checkDigit: true,
    );
    final parsed = ScaleBarcodeParser.decode('0000010002100', config);
    expect(parsed, isNotNull);
    expect(parsed!.itemCode, '00010');
    expect(parsed.weightKg, closeTo(0.210, 1e-9));

    // The exact printed item code does not exist ...
    expect(await DatabaseService().getProductByBarcode(parsed.itemCode), isNull);
    // ... but the leading-zero-tolerant lookup finds the product.
    final product =
        await DatabaseService().getProductByBarcodeLoose(parsed.itemCode);
    expect(product, isNotNull);
    expect(product!.name, 'Banana');
  });

  test('loose lookup matches the exact barcode and the fully-stripped code',
      () async {
    await insertProduct('banana', 'Banana', '0000010', soldByWeight: 1);
    expect(
      (await DatabaseService().getProductByBarcodeLoose('0000010'))!.name,
      'Banana',
    );
    expect(
      (await DatabaseService().getProductByBarcodeLoose('10'))!.name,
      'Banana',
    );
    expect(await DatabaseService().getProductByBarcodeLoose(''), isNull);
  });

  test('loose lookup leaves an ordinary EAN-13 barcode untouched', () async {
    await insertProduct('cherish', 'Cherish Lemon', '4790014650037');
    final exact =
        await DatabaseService().getProductByBarcodeLoose('4790014650037');
    expect(exact, isNotNull);
    expect(exact!.name, 'Cherish Lemon');
  });
}
