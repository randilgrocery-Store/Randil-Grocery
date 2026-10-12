import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/data/services/scale_barcode.dart';

void main() {
  const config = ScaleBarcodeConfig(enabled: true); // 2 + 5 item + 5 value + check

  group('ScaleBarcodeParser.decode (weight labels)', () {
    test('decodes a 12-digit weight label', () {
      // prefix 2 | item 10012 | 00500 g | check 7
      final decoded = ScaleBarcodeParser.decode('210012005007', config);
      expect(decoded, isNotNull);
      expect(decoded!.itemCode, '10012');
      expect(decoded.value, 500);
      expect(decoded.weightKg, closeTo(0.5, 1e-9));
      expect(decoded.priceMode, isFalse);
    });

    test('decodes a full-kilogram label', () {
      // item 10012 | 01000 g (= 1.000 kg) | check 4
      final decoded = ScaleBarcodeParser.decode('210012010004', config);
      expect(decoded!.weightKg, closeTo(1.0, 1e-9));
    });

    test('returns null when decoding is disabled', () {
      const disabled = ScaleBarcodeConfig(enabled: false);
      expect(ScaleBarcodeParser.decode('210012005007', disabled), isNull);
    });

    test('rejects a wrong total length', () {
      expect(ScaleBarcodeParser.decode('21001200500', config), isNull);
      expect(ScaleBarcodeParser.decode('2100120050077', config), isNull);
    });

    test('rejects a wrong prefix', () {
      expect(ScaleBarcodeParser.decode('310012005007', config), isNull);
    });

    test('rejects non-digit input', () {
      expect(ScaleBarcodeParser.decode('21001200500X', config), isNull);
    });
  });

  group('ScaleBarcodeParser.decode (price labels)', () {
    const priceConfig = ScaleBarcodeConfig(enabled: true, priceMode: true);

    test('decodes a price-embedded label', () {
      // prefix 2 | item 10012 | 12500 (=Rs.125.00) | check 8
      final decoded = ScaleBarcodeParser.decode('210012125008', priceConfig);
      expect(decoded!.price, closeTo(125.0, 1e-9));
      expect(decoded.priceMode, isTrue);
    });
  });

  group('check digit handling', () {
    test('without a check digit the value region grows by one', () {
      const noCheck = ScaleBarcodeConfig(enabled: true, checkDigit: false);
      // 2 + 5 item + 6 value = 12 digits (no check digit)
      final decoded = ScaleBarcodeParser.decode('210012050001', noCheck);
      expect(decoded, isNotNull);
      expect(decoded!.itemCode, '10012');
      expect(decoded.value, 50001);
    });
  });

  group('candidateItemLengths', () {
    test('puts the configured length first then nearby widths', () {
      final lengths = ScaleBarcodeParser.candidateItemLengths(config);
      expect(lengths.first, 5);
      expect(lengths, contains(4));
      expect(lengths, contains(6));
      // Every candidate must leave room for at least one value digit.
      expect(lengths.every((l) => l >= 1 && l <= 9), isTrue);
    });

    test('an item-length override can recover a mis-configured split', () {
      // Configured as 4-item but the label actually uses 5-item codes.
      const wrong = ScaleBarcodeConfig(enabled: true, itemLength: 4);
      // At the configured split the item code is wrong...
      final asConfigured = ScaleBarcodeParser.decode('210012005007', wrong);
      expect(asConfigured!.itemCode, '1001');
      // ...but the fallback width decodes the real item.
      final recovered =
          ScaleBarcodeParser.decode('210012005007', wrong, itemLength: 5);
      expect(recovered!.itemCode, '10012');
      expect(recovered.weightKg, closeTo(0.5, 1e-9));
    });
  });
}
