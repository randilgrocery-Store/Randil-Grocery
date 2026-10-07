import 'package:uuid/uuid.dart';

class Wastage {
  Wastage({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.reason,
    required this.lossValue,
    String? id,
    this.batchId = '',
    this.batchNumber = '',
    this.notes = '',
    this.recordedBy = '',
    DateTime? wastageDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        wastageDate = wastageDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory Wastage.fromMap(Map<String, dynamic> map) => Wastage(
        id: map['id'] as String,
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        quantity: (map['quantity'] as num).toDouble(),
        reason: map['reason'] as String,
        lossValue: (map['lossValue'] as num).toDouble(),
        batchId: map['batchId'] as String? ?? '',
        batchNumber: map['batchNumber'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        recordedBy: map['recordedBy'] as String? ?? '',
        wastageDate: DateTime.parse(map['wastageDate'] as String),
        createdAt:
            DateTime.parse(map['createdAt'] as String),
      );

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final String reason;
  final double lossValue;
  final String batchId;
  final String batchNumber;
  final String notes;
  final String recordedBy;
  final DateTime wastageDate;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'reason': reason,
        'lossValue': lossValue,
        'batchId': batchId,
        'batchNumber': batchNumber,
        'notes': notes,
        'recordedBy': recordedBy,
        'wastageDate': wastageDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() =>
      'Wastage(id: $id, product: $productName, qty: $quantity, reason: $reason, loss: $lossValue)';
}