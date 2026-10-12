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
    this.updatedAt,
  })  : id = id ?? const Uuid().v4(),
        wastageDate = wastageDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory Wastage.fromMap(Map<String, dynamic> map) => Wastage(
        id: (map['id'] as String?) ?? const Uuid().v4(),
        productId: (map['productId'] as String?) ?? '',
        productName: (map['productName'] as String?) ?? '',
        quantity: _asDouble(map['quantity']),
        reason: (map['reason'] as String?) ?? '',
        lossValue: _asDouble(map['lossValue']),
        batchId: map['batchId'] as String? ?? '',
        batchNumber: map['batchNumber'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        recordedBy: map['recordedBy'] as String? ?? '',
        wastageDate: _asDate(map['wastageDate']),
        createdAt: _asDate(map['createdAt']),
        updatedAt: _asDateOrNull(map['updatedAt']),
      );

  /// Tolerant number parse — a row synced from another machine can carry a
  /// null/blank value, and one bad row must never hide the whole list.
  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  /// Tolerant date parse — falls back to now for a null or unparseable value
  /// instead of throwing and blanking the screen.
  static DateTime _asDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _asDateOrNull(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

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

  /// When the record was last edited. Bumped on every correction so the LAN
  /// mirror clock moves and the other PC pulls the edited row.
  final DateTime? updatedAt;

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
        'updatedAt': updatedAt?.toIso8601String(),
      };

  @override
  String toString() =>
      'Wastage(id: $id, product: $productName, qty: $quantity, reason: $reason, loss: $lossValue)';
}