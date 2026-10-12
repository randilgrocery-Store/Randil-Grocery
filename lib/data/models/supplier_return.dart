import 'dart:convert';

import 'package:uuid/uuid.dart';

/// One line of a supplier return: how much of one product goes back to the
/// supplier, which batch it comes out of and the cost credited per box.
class SupplierReturnItem {
  SupplierReturnItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.costPrice,
    this.batchId = '',
    this.batchNumber = '',
  });

  factory SupplierReturnItem.fromMap(Map<String, dynamic> map) =>
      SupplierReturnItem(
        productId: map['productId'] as String,
        productName: map['productName'] as String? ?? '',
        quantity: (map['quantity'] as num).toDouble(),
        costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0,
        batchId: map['batchId'] as String? ?? '',
        batchNumber: map['batchNumber'] as String? ?? '',
      );

  final String productId;
  final String productName;

  /// Quantity in the product's stock unit (boxes) — the same unit GRN adds, so
  /// a return of 2 boxes takes exactly 2 boxes back out of the shelves and the
  /// FIFO batches.
  final double quantity;

  /// Cost per box credited back (from the picked batch or the product price).
  final double costPrice;
  final String batchId;
  final String batchNumber;

  double get lineTotal => quantity * costPrice;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'costPrice': costPrice,
        'batchId': batchId,
        'batchNumber': batchNumber,
      };
}

/// Goods returned to a supplier.
///
/// The value of a return is credited against what the shop still owes that
/// supplier (outstanding = GRN total − payments − returns), the returned stock
/// is taken back out of the shelves (product quantity + FIFO batches), and the
/// whole record travels to the other machine through the LAN mirror exactly like
/// a GRN or a supplier payment.
class SupplierReturn {
  SupplierReturn({
    required this.supplierId,
    required this.supplierName,
    required this.items,
    required this.reason,
    String? id,
    String? returnNumber,
    this.notes = '',
    this.returnedBy = '',
    DateTime? returnDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        returnNumber = returnNumber ?? '',
        returnDate = returnDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory SupplierReturn.fromMap(Map<String, dynamic> map) => SupplierReturn(
        id: map['id'] as String,
        returnNumber: map['returnNumber'] as String? ?? '',
        supplierId: map['supplierId'] as String,
        supplierName: map['supplierName'] as String? ?? '',
        items: ((map['items'] as String?) ?? '[]').isEmpty
            ? <SupplierReturnItem>[]
            : (jsonDecode(map['items'] as String) as List)
                .map((e) =>
                    SupplierReturnItem.fromMap(Map<String, dynamic>.from(e)))
                .toList(),
        reason: map['reason'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        returnedBy: map['returnedBy'] as String? ?? '',
        returnDate: DateTime.parse(map['returnDate'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  final String id;
  final String returnNumber;
  final String supplierId;
  final String supplierName;
  final List<SupplierReturnItem> items;
  final String reason;
  final String notes;
  final String returnedBy;
  final DateTime returnDate;
  final DateTime createdAt;

  double get total => items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  Map<String, dynamic> toMap() => {
        'id': id,
        'returnNumber': returnNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        // Kept as a JSON *string* on purpose — the mirror carries the row
        // verbatim (like sales.items) and never re-encodes it.
        'items': jsonEncode(items.map((e) => e.toMap()).toList()),
        'total': total,
        'reason': reason,
        'notes': notes,
        'returnedBy': returnedBy,
        'returnDate': returnDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}