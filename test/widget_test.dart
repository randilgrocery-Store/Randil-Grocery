import 'package:flutter_test/flutter_test.dart';

import 'package:randil_grocery_pos/core/utils/money_calculator.dart';
import 'package:randil_grocery_pos/core/utils/password_hasher.dart';

void main() {
  group('MoneyCalculator', () {
    test('calculates exact change without floating point drift', () {
      expect(MoneyCalculator.calculateChange(500, 100.10), 399.90);
      expect(MoneyCalculator.calculateChange(100, 33.33), 66.67);
    });

    test('sums item prices precisely', () {
      expect(MoneyCalculator.calculateSubtotal([10.10, 20.20, 30.30]), 60.60);
    });

    test('applies percentage discount', () {
      expect(MoneyCalculator.applyPercentageDiscount(100, 10), 10);
      expect(MoneyCalculator.applyPercentageDiscount(99.99, 50), 50.0);
    });

    test('validates payment sufficiency', () {
      expect(MoneyCalculator.isPaymentSufficient(100, 99.99), isTrue);
      expect(MoneyCalculator.isPaymentSufficient(99.99, 100), isFalse);
      expect(MoneyCalculator.isPaymentSufficient(100, 100), isTrue);
    });
  });

  group('PasswordHasher', () {
    test('hash includes a salt and cannot be verified without it', () {
      final hashed = PasswordHasher.hash('secret123');
      expect(hashed.contains('\$'), isTrue);
      expect(hashed.split('\$').length, 2);
    });

    test('verifies correct password and rejects wrong ones', () {
      const password = 'admin123';
      final stored = PasswordHasher.hash(password);
      expect(PasswordHasher.verify(password, stored), isTrue);
      expect(PasswordHasher.verify('wrong', stored), isFalse);
      expect(PasswordHasher.verify('secret', 'not-a-hash'), isFalse);
    });
  });
}