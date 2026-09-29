import 'package:uuid/uuid.dart';

class RefundReturnItem { // e.g., "Damaged", "Defective", "Wrong item", "Customer request"

  RefundReturnItem({
    required this.saleItemId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.originalPrice,
    required this.refundAmount,
    required this.reason,
  });

  factory RefundReturnItem.fromMap(Map<String, dynamic> map) => RefundReturnItem(
      saleItemId: map['saleItemId'] as String,
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      quantity: map['quantity'] as int,
      originalPrice: (map['originalPrice'] as num).toDouble(),
      refundAmount: (map['refundAmount'] as num).toDouble(),
      reason: map['reason'] as String,
    );
  final String saleItemId;
  final String productId;
  final String productName;
  final int quantity;
  final double originalPrice;
  final double refundAmount;
  final String
      reason;

  Map<String, dynamic> toMap() => {
      'saleItemId': saleItemId,
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'originalPrice': originalPrice,
      'refundAmount': refundAmount,
      'reason': reason,
    };
}

class RefundReturn {

  RefundReturn({
    required this.originalSaleId, required this.items, required this.totalRefundAmount, String? id,
    this.invoiceNumber = '',
    this.refundMethod = 'Cash',
    this.status = 'Pending',
    this.notes = '',
    this.processedBy,
    this.requesterId = '',
    this.requesterName = '',
    DateTime? requestDate,
    this.processedDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        requestDate = requestDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory RefundReturn.fromMap(Map<String, dynamic> map) => RefundReturn(
      id: map['id'] as String,
      originalSaleId: map['originalSaleId'] as String,
      invoiceNumber: map['invoiceNumber'] as String? ?? '',
      items: (map['items'] as List)
          .map((e) => RefundReturnItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      totalRefundAmount: (map['totalRefundAmount'] as num).toDouble(),
      refundMethod: map['refundMethod'] as String? ?? 'Cash',
      status: map['status'] as String? ?? 'Pending',
      notes: map['notes'] as String? ?? '',
      processedBy: map['processedBy'] as String?,
        requesterId: map['requesterId'] as String? ?? '',
        requesterName: map['requesterName'] as String? ?? '',
      requestDate: DateTime.parse(map['requestDate'] as String),
      processedDate: map['processedDate'] != null
          ? DateTime.parse(map['processedDate'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  final String id;
  final String originalSaleId;
  final String invoiceNumber;
  final List<RefundReturnItem> items;
  final double totalRefundAmount;
  final String refundMethod; // "Cash", "Original Payment", "Store Credit"
  final String status; //"Pending", "Approved", "Rejected", "Processed"
  final String notes;
  final String? processedBy; // User ID
  final String requesterId; // User ID of cashier/admin who requested
  final String requesterName;
  final DateTime requestDate;
  final DateTime? processedDate;
  final DateTime createdAt;

  RefundReturn copyWith({
    String? id,
    String? originalSaleId,
    String? invoiceNumber,
    List<RefundReturnItem>? items,
    double? totalRefundAmount,
    String? refundMethod,
    String? status,
    String? notes,
    String? processedBy,
    String? requesterId,
    String? requesterName,
    DateTime? requestDate,
    DateTime? processedDate,
    DateTime? createdAt,
  }) => RefundReturn(
      id: id ?? this.id,
      originalSaleId: originalSaleId ?? this.originalSaleId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      items: items ?? this.items,
      totalRefundAmount: totalRefundAmount ?? this.totalRefundAmount,
      refundMethod: refundMethod ?? this.refundMethod,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      processedBy: processedBy ?? this.processedBy,
      requesterId: requesterId ?? this.requesterId,
      requesterName: requesterName ?? this.requesterName,
      requestDate: requestDate ?? this.requestDate,
      processedDate: processedDate ?? this.processedDate,
      createdAt: createdAt ?? this.createdAt,
    );

  Map<String, dynamic> toMap() => {
      'id': id,
      'originalSaleId': originalSaleId,
      'invoiceNumber': invoiceNumber,
      'items': items.map((e) => e.toMap()).toList(),
      'totalRefundAmount': totalRefundAmount,
      'refundMethod': refundMethod,
      'status': status,
      'notes': notes,
      'processedBy': processedBy,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requestDate': requestDate.toIso8601String(),
      'processedDate': processedDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };

  @override
  String toString() =>
      'RefundReturn(id: $id, status: $status, amount: $totalRefundAmount)';
}
