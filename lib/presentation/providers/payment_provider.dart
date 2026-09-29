import 'package:flutter/material.dart';

enum PaymentMethod { cash, card, split }

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.split:
        return 'Cash + Card';
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.cash:
        return Icons.money;
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.split:
        return Icons.account_balance_wallet;
    }
  }

  Color get color {
    switch (this) {
      case PaymentMethod.cash:
        return Colors.green;
      case PaymentMethod.card:
        return Colors.blue;
      case PaymentMethod.split:
        return Colors.orange;
    }
  }

  /// Whether a cash amount is collected for this method (split collects cash
  /// in addition to card, cash collects only cash, card collects none).
  bool get usesCash =>
      this == PaymentMethod.cash || this == PaymentMethod.split;

  /// Whether a card amount is collected for this method.
  bool get usesCard =>
      this == PaymentMethod.card || this == PaymentMethod.split;
}

class PaymentProvider with ChangeNotifier {
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  Map<String, dynamic> _paymentDetails = {};
  final List<PaymentMethod> _enabledPaymentMethods = [
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.split,
  ];

  PaymentMethod get selectedPaymentMethod => _selectedPaymentMethod;
  Map<String, dynamic> get paymentDetails => _paymentDetails;
  List<PaymentMethod> get enabledPaymentMethods => _enabledPaymentMethods;

  void setPaymentMethod(PaymentMethod method) {
    _selectedPaymentMethod = method;
    _paymentDetails.clear();
    notifyListeners();
  }

  void setPaymentDetails(Map<String, dynamic> details) {
    _paymentDetails = details;
    notifyListeners();
  }

  void reset() {
    _selectedPaymentMethod = PaymentMethod.cash;
    _paymentDetails.clear();
    notifyListeners();
  }
}
