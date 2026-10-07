import 'package:flutter_test/flutter_test.dart';

import 'package:randil_grocery_pos/data/services/barcode_scanner_service.dart';

// NOTE: the receipt/drawer ordering itself is NOT unit tested. Deciding when a
// pulse is owed lives in POSScreen._fireCashDrawerForLastSale, which needs a
// live window, a database and a printer. A test that re-implements that
// decision in a helper class would only assert its own logic, so it was removed
// rather than left as decoration. `drawer_events` provides the real
// exactly-once guarantee and is exercised through CashDrawerCoordinator at
// runtime.
//
// The rule the code must keep, and which a reviewer should re-check on change:
//
//   * the sale is saved, but the pulse does NOT fire yet
//   * the pulse fires from _printBill (success, failure, no-receipt and
//     exception paths) and from _clearForm as a safety net
//   * _fireCashDrawerForLastSale clears _pendingDrawerOpen before doing any
//     work, so every extra call site is a no-op

void main() {
  group('BarcodeScannerService.submit de-duplication', () {
    late BarcodeScannerService service;

    setUp(() {
      service = BarcodeScannerService.instance;
      service.resetForTesting();
    });

    tearDown(() => service.resetForTesting());

    test('delivers the first scan', () async {
      final seen = <String>[];
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async => seen.add(code),
      );

      await service.submit('111111');

      expect(seen, <String>['111111']);
    });

    test('suppresses the SAME barcode repeated inside the window', () async {
      final seen = <String>[];
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async => seen.add(code),
      );

      await service.submit('111111');
      // A second physical scan of the same item must be ignored: the field's
      // onSubmitted and the root listener can both report one scan.
      await service.submit('111111');

      expect(seen, <String>['111111']);
    });

    test('does NOT swallow a DIFFERENT barcode scanned quickly', () async {
      final seen = <String>[];
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async => seen.add(code),
      );

      // Two different items scanned back to back. A global time window used to
      // drop the second one, losing a sale.
      await service.submit('111111');
      await service.submit('222222');

      expect(seen, <String>['111111', '222222']);
    });

    test('allows the same barcode again once the window has passed', () async {
      final seen = <String>[];
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async => seen.add(code),
      );

      await service.submit('111111');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await service.submit('111111');

      // Two separate scans of two identical items must both reach the cart.
      expect(seen, <String>['111111', '111111']);
    });

    test('a failing handler still lets the next scan through', () async {
      var calls = 0;
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async {
          calls++;
          if (code == 'bad111') throw StateError('boom');
        },
      );

      await service.submit('bad111');
      await service.submit('good111');

      expect(calls, 2);
    });

    test('ignores input shorter than the minimum barcode length', () async {
      final seen = <String>[];
      service.claimForTesting(
        token: 1,
        onBarcode: (code) async => seen.add(code),
      );

      await service.submit('12');

      expect(seen, isEmpty);
    });

    test('does nothing when no screen owns the scanners', () async {
      var calls = 0;
      service.claimForTesting(
        token: 1,
        onBarcode: (_) async => calls++,
      );
      service.release(1);

      await service.submit('111111');

      expect(calls, 0);
    });
  });
}
