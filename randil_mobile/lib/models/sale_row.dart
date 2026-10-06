/// One row of the shop's `sales_sync` table — used for the "Recent bills"
/// list on the phone. Same record the POS pushes after every completed sale.
class SaleRow {
  const SaleRow({
    required this.id,
    required this.billNumber,
    required this.amount,
    required this.paymentMethod,
    required this.itemsCount,
    required this.timestamp,
  });

  final String id;
  final String billNumber;
  final double amount;
  final String paymentMethod;
  final int itemsCount;
  final DateTime? timestamp;

  factory SaleRow.fromJson(Map<String, dynamic> json) => SaleRow(
        id: (json['id'] ?? '').toString(),
        billNumber: (json['bill_number'] ?? '').toString(),
        amount: json['amount'] is num ? (json['amount'] as num).toDouble() : 0,
        paymentMethod: (json['payment_method'] ?? '').toString(),
        itemsCount: json['items_count'] is num
            ? (json['items_count'] as num).toInt()
            : 0,
        timestamp:
            (json['timestamp'] is String && (json['timestamp'] as String).isNotEmpty)
                ? DateTime.tryParse(json['timestamp'] as String)
                : null,
      );
}