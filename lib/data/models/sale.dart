import 'package:uuid/uuid.dart';

import 'product_batch.dart';

class SaleItem {

  SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.discount = 0.0,
    this.costPrice = 0.0,
    this.batchNumber = '',
    this.barcode = '',
    String? id,
    this.allocations = const [],
  }) : id = id ?? const Uuid().v4();

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    final rawAllocations = map['allocations'];
    return SaleItem(
      id: map['id'] as String? ?? const Uuid().v4(),
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int,
      discount: (map['discount'] as num).toDouble(),
      costPrice: map['costPrice'] != null
          ? (map['costPrice'] as num).toDouble()
          : 0.0,
      batchNumber: map['batchNumber'] as String? ?? '',
      barcode: map['barcode'] as String? ?? '',
      allocations: rawAllocations is List
          ? rawAllocations
              .map((e) => BatchAllocation.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
    );
  }
  final String id;
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double discount;

  /// Weighted cost of the batch(es) this line was picked from (for accurate
  /// profit reporting when the same product is bought at different prices).
  final double costPrice;

  /// The batch(es) this line was fulfilled from (FIFO), for traceability.
  final String batchNumber;

  /// Item code / barcode, useful for returns and re-scanning.
  final String barcode;

  /// The exact stock batches this line was fulfilled from (FIFO). Used to put
  /// the right stock back into the right batch when the line is refunded.
  final List<BatchAllocation> allocations;

  double get subtotal => price * quantity;
  double get discountAmount => (subtotal * discount) / 100;
  double get total => subtotal - discountAmount;
  double get profitAmount => total - (costPrice * quantity);

  Map<String, dynamic> toMap() => {
      'id': id,
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'discount': discount,
      'costPrice': costPrice,
      'batchNumber': batchNumber,
      'barcode': barcode,
      'allocations': allocations.map((e) => e.toMap()).toList(),
    };
}

class Sale {

  Sale({
    required this.cashierId, required this.cashierName, required this.items, required this.subtotal, required this.totalDiscount, required this.totalAmount, required this.amountReceived, required this.balance, String? id,
    this.invoiceNumber = '',
    this.paymentMethod = 'Cash',
    DateTime? saleDate,
    this.notes = '',
  })  : id = id ?? const Uuid().v4(),
        saleDate = saleDate ?? DateTime.now();

  factory Sale.fromMap(Map<String, dynamic> map) => Sale(
      id: map['id'] as String,
      invoiceNumber: map['invoiceNumber'] as String? ?? '',
      cashierId: map['cashierId'] as String,
      cashierName: map['cashierName'] as String,
      items: (map['items'] as List)
          .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      subtotal: (map['subtotal'] as num).toDouble(),
      totalDiscount: (map['totalDiscount'] as num).toDouble(),
      totalAmount: (map['totalAmount'] as num).toDouble(),
      amountReceived: (map['amountReceived'] as num).toDouble(),
      balance: (map['balance'] as num).toDouble(),
      paymentMethod: map['paymentMethod'] as String,
      saleDate: DateTime.parse(map['saleDate'] as String),
      notes: map['notes'] as String? ?? '',
    );
  final String id;

  /// Human-readable, numeric invoice number (e.g. INV-000123). Empty for
  /// legacy sales created before invoice numbering was introduced.
  final String invoiceNumber;
  final String cashierId;
  final String cashierName;
  final List<SaleItem> items;
  final double subtotal;
  final double totalDiscount;
  final double totalAmount;
  final double amountReceived;
  final double balance;
  final String paymentMethod;
  final DateTime saleDate;
  final String notes;

  /// Invoice label to show on screen and on the printed bill.
  String get invoiceLabel => invoiceNumber.isEmpty
      ? 'INV-${id.substring(0, 6).toUpperCase()}'
      : invoiceNumber;

  Map<String, dynamic> toMap() => {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'totalDiscount': totalDiscount,
      'totalAmount': totalAmount,
      'amountReceived': amountReceived,
      'balance': balance,
      'paymentMethod': paymentMethod,
      'saleDate': saleDate.toIso8601String(),
      'notes': notes,
    };

  @override
  String toString() =>
      'Sale(id: $id, invoice: $invoiceLabel, total: $totalAmount, items: ${items.length}, date: $saleDate)';
}

/// Formats a numeric sequence into the shop's invoice number format.
String formatInvoiceNumber(int sequence) =>
    'INV-${sequence.toString().padLeft(6, '0')}';
