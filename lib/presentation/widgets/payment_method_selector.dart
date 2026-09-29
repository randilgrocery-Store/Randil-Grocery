import 'package:flutter/material.dart';

import '../providers/payment_provider.dart';

class PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod? selectedMethod;
  final ValueChanged<PaymentMethod>? onMethodSelected;
  final List<PaymentMethod>? enabledMethods;
  final double? width;

  const PaymentMethodSelector({
    super.key,
    this.selectedMethod,
    this.onMethodSelected,
    this.enabledMethods,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final methods = enabledMethods ?? PaymentMethod.values;

    return SizedBox(
      width: width,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: methods
            .map(
              (method) => PaymentMethodCard(
                method: method,
                isSelected: selectedMethod == method,
                onTap: () => onMethodSelected?.call(method),
              ),
            )
            .toList(),
      ),
    );
  }
}

class PaymentMethodDetailsForm extends StatefulWidget {
  final PaymentMethod paymentMethod;
  final ValueChanged<Map<String, dynamic>>? onDetailsChanged;

  const PaymentMethodDetailsForm({
    super.key,
    required this.paymentMethod,
    this.onDetailsChanged,
  });

  @override
  State<PaymentMethodDetailsForm> createState() =>
      _PaymentMethodDetailsFormState();
}

class _PaymentMethodDetailsFormState extends State<PaymentMethodDetailsForm> {
  late final TextEditingController _firstController;
  late final TextEditingController _secondController;

  @override
  void initState() {
    super.initState();
    _firstController = TextEditingController();
    _secondController = TextEditingController();
  }

  @override
  void dispose() {
    _firstController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  void _emitDetails({required String firstKey, required String secondKey}) {
    widget.onDetailsChanged?.call({
      firstKey: _firstController.text,
      secondKey: _secondController.text,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.paymentMethod) {
      case PaymentMethod.card:
      case PaymentMethod.split:
        return _buildForm(
          firstLabel: 'Card Last 4 Digits (optional)',
          secondLabel: 'Transaction / Approval ID (optional)',
          firstKeyboardType: TextInputType.number,
          firstMaxLength: 4,
          firstKey: widget.paymentMethod == PaymentMethod.split
              ? 'splitCardLast4'
              : 'cardLast4',
          secondKey: widget.paymentMethod == PaymentMethod.split
              ? 'splitTransactionId'
              : 'transactionId',
        );
      case PaymentMethod.cash:
        return const SizedBox.shrink();
    }
  }

  Widget _buildForm({
    required String firstLabel,
    required String secondLabel,
    required String firstKey,
    required String secondKey,
    TextInputType firstKeyboardType = TextInputType.text,
    TextInputType secondKeyboardType = TextInputType.text,
    int? firstMaxLength,
    int? secondMaxLines,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _firstController,
              keyboardType: firstKeyboardType,
              maxLength: firstMaxLength,
              decoration: InputDecoration(
                labelText: firstLabel,
                isDense: true,
                counterText: '',
              ),
              onChanged: (_) =>
                  _emitDetails(firstKey: firstKey, secondKey: secondKey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _secondController,
              keyboardType: secondKeyboardType,
              maxLines: secondMaxLines,
              decoration: InputDecoration(
                labelText: secondLabel,
                isDense: true,
              ),
              onChanged: (_) =>
                  _emitDetails(firstKey: firstKey, secondKey: secondKey),
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentMethodCard extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const PaymentMethodCard({
    super.key,
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? method.color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? method.color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(method.icon, color: method.color, size: 20),
            const SizedBox(width: 8),
            Text(
              method.displayName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? method.color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
