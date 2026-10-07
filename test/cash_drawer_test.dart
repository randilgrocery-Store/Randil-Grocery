import 'package:flutter_test/flutter_test.dart';

import 'package:randil_grocery_pos/data/models/shop_settings.dart';
import 'package:randil_grocery_pos/data/services/cash_drawer_service.dart';

void main() {
  group('CashDrawerService.buildOpenCommand', () {
    test('encodes pin 2 as m=0', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 2,
        pulseOnMs: 120,
        pulseOffMs: 240,
      );
      // ESC p m t1 t2  ->  t1 = 120ms/2ms = 60, t2 = 240ms/2ms = 120
      expect(bytes, <int>[0x1B, 0x70, 0x00, 60, 120]);
    });

    test('encodes pin 5 as m=1', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 5,
        pulseOnMs: 120,
        pulseOffMs: 240,
      );
      expect(bytes, <int>[0x1B, 0x70, 0x01, 60, 120]);
    });

    test('matches the documented 1B 70 00 19 FA default', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 2,
        pulseOnMs: 50,
        pulseOffMs: 500,
      );
      expect(bytes, <int>[0x1B, 0x70, 0x00, 0x19, 0xFA]);
    });

    test('always starts with the ESC p introducer', () {
      for (final pin in [2, 5]) {
        final bytes =
            CashDrawerService.buildOpenCommand(pin: pin, pulseOnMs: 120, pulseOffMs: 240);
        expect(bytes[0], 0x1B);
        expect(bytes[1], 0x70);
      }
    });

    test('clamps timings into the single-byte ESC/POS range', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 2,
        pulseOnMs: 5000,
        pulseOffMs: 5000,
      );
      // 5000ms / 2ms = 2500, clamped to the maximum 255.
      expect(bytes[3], 255);
      expect(bytes[4], 255);
    });

    test('rounds odd millisecond values instead of truncating', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 2,
        pulseOnMs: 101,
        pulseOffMs: 241,
      );
      expect(bytes[3], 51); // 50.5 -> 51
      expect(bytes[4], 121); // 120.5 -> 121
    });

    test('treats a zero pulse as a valid value rather than going negative', () {
      final bytes = CashDrawerService.buildOpenCommand(
        pin: 2,
        pulseOnMs: 0,
        pulseOffMs: 0,
      );
      expect(bytes[3], 0);
      expect(bytes[4], 0);
    });
  });

  group('CashDrawerService.pulseBytesForSale (drawer rides with the bill)', () {
    ShopSettings drawerOn() => ShopSettings(
          printerName: 'XP-80',
          cashDrawerEnabled: true,
          cashDrawerOpenOnCardOnly: true,
          cashDrawerPin: 2,
          cashDrawerPulseOnMs: 120,
          cashDrawerPulseOffMs: 240,
        );

    test('returns the raw kick for an ordinary cash sale', () async {
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: false,
        settings: drawerOn(),
      );

      expect(bytes, isNotNull);
      expect(
        bytes,
        CashDrawerService.buildOpenCommand(
          pin: 2,
          pulseOnMs: 120,
          pulseOffMs: 240,
        ),
      );
    });

    test('is exactly 5 bytes so nothing extra prints on the receipt', () async {
      // Any padding byte here would appear on the customer's receipt. This is
      // the regression guard for the "add a dwell so the solenoid starts first"
      // idea, which would have used ESC t n -- the character-set select -- and
      // silently changed every glyph on the bill.
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: false,
        settings: drawerOn(),
      );

      expect(bytes, hasLength(5));
      expect(bytes!.sublist(0, 3), [0x1B, 0x70, 0x00]);
    });

    test('returns nothing once the sale already had its pulse', () async {
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: true,
        isCardOnly: false,
        settings: drawerOn(),
      );

      expect(bytes, isNull);
    });

    test('returns nothing when the drawer is switched off', () async {
      final settings = ShopSettings(
        printerName: 'XP-80',
        cashDrawerEnabled: false,
      );
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: false,
        settings: settings,
      );

      expect(bytes, isNull);
    });

    test('returns nothing for a card-only sale the owner opted out of', () async {
      final settings = ShopSettings(
        printerName: 'XP-80',
        cashDrawerEnabled: true,
        cashDrawerOpenOnCardOnly: false,
      );
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: true,
        settings: settings,
      );

      expect(bytes, isNull);
    });

    test('still pulses a card-only sale when the owner opted in', () async {
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: true,
        settings: drawerOn(),
      );

      expect(bytes, isNotNull);
    });

    test('returns nothing when no printer is configured at all', () async {
      final settings = ShopSettings(
        printerName: '   ',
        cashDrawerEnabled: true,
      );
      final bytes = await CashDrawerService().pulseBytesForSale(
        alreadyHandled: false,
        isCardOnly: false,
        settings: settings,
      );

      expect(bytes, isNull);
    });
  });

  group('CashDrawerService.resolvePrinterName', () {
    test('prefers the dedicated drawer printer when set', () {
      final settings = ShopSettings(
        printerName: 'Receipt Printer',
        cashDrawerPrinterName: 'Drawer Printer',
      );
      expect(
        CashDrawerService.resolvePrinterName(settings),
        'Drawer Printer',
      );
    });

    test('falls back to the receipt printer', () {
      final settings = ShopSettings(printerName: 'Receipt Printer');
      expect(
        CashDrawerService.resolvePrinterName(settings),
        'Receipt Printer',
      );
    });

    test('treats whitespace as unset', () {
      final settings = ShopSettings(
        printerName: 'Receipt Printer',
        cashDrawerPrinterName: '   ',
      );
      expect(
        CashDrawerService.resolvePrinterName(settings),
        'Receipt Printer',
      );
    });
  });

  group('ShopSettings cash drawer persistence', () {
    test('round-trips every drawer field through the database map', () {
      final original = ShopSettings(
        cashDrawerEnabled: false,
        cashDrawerPrinterName: 'Drawer Printer',
        cashDrawerPin: 5,
        cashDrawerPulseOnMs: 200,
        cashDrawerPulseOffMs: 300,
        cashDrawerOpenOnCardOnly: false,
      );

      final restored = ShopSettings.fromMap(original.toMap());

      expect(restored.cashDrawerEnabled, isFalse);
      expect(restored.cashDrawerPrinterName, 'Drawer Printer');
      expect(restored.cashDrawerPin, 5);
      expect(restored.cashDrawerPulseOnMs, 200);
      expect(restored.cashDrawerPulseOffMs, 300);
      expect(restored.cashDrawerOpenOnCardOnly, isFalse);
    });

    test('defaults to automatic opening on card payments', () {
      final settings = ShopSettings();
      expect(settings.cashDrawerEnabled, isTrue);
      expect(settings.cashDrawerOpenOnCardOnly, isTrue);
      expect(settings.cashDrawerPin, 2);
    });

    test('tolerates an older database row without drawer columns', () {
      // A database created before this feature has no cashDrawer* keys.
      final legacy = ShopSettings().toMap()..remove('cashDrawerEnabled');
      final restored = ShopSettings.fromMap(legacy);
      expect(restored.cashDrawerEnabled, isTrue);
    });

    test('copyWith changes only the requested drawer field', () {
      final settings = ShopSettings();
      final updated = settings.copyWith(cashDrawerPin: 5);
      expect(updated.cashDrawerPin, 5);
      expect(updated.cashDrawerPulseOnMs, settings.cashDrawerPulseOnMs);
      expect(updated.cashDrawerEnabled, settings.cashDrawerEnabled);
    });
  });
}
