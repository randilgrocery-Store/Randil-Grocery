import 'dart:convert';

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

/// One line of a bill's `items_json`.
class SaleItem {
  const SaleItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.lineTotal,
  });

  final String name;
  final double qty;
  final double price;
  final double lineTotal;
}

/// Decodes the `items_json` string the POS stores on each `sales_sync` row.
/// Failures return an empty list so the bill view can show its fallback
/// instead of throwing.
List<SaleItem> decodeItems(String raw) {
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final e in list)
        SaleItem(
          name: (e is Map ? e['name'] ?? '' : '').toString(),
          qty: e is Map && e['qty'] is num ? (e['qty'] as num).toDouble() : 0,
          price:
              e is Map && e['price'] is num ? (e['price'] as num).toDouble() : 0,
          lineTotal: e is Map && e['line_total'] is num
              ? (e['line_total'] as num).toDouble()
              : 0,
        ),
    ];
  } catch (_) {
    return const [];
  }
}