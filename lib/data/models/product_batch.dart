import 'package:uuid/uuid.dart';

class ProductBatch {
  ProductBatch({
    required this.productId,
    required this.batchNumber,
    required this.price,
    required this.quantity,
    required this.supplierId,
    String? id,
    double? sellingPrice,
    this.expiryDate,
    DateTime? receivedDate,
    this.notes = '',
    DateTime? createdAt,
    double? initialQuantity,
  })  : id = id ?? const Uuid().v4(),
        sellingPrice = sellingPrice ?? 0,
        receivedDate = receivedDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        initialQuantity = initialQuantity ?? quantity;

  factory ProductBatch.fromMap(Map<String, dynamic> map) => ProductBatch(
        id: map['id'] as String,
        productId: map['productId'] as String,
        batchNumber: map['batchNumber'] as String,
        price: (map['price'] as num).toDouble(),
        sellingPrice: map['sellingPrice'] != null
            ? (map['sellingPrice'] as num).toDouble()
            : 0,
        expiryDate: map['expiryDate'] != null
            ? DateTime.parse(map['expiryDate'] as String)
            : null,
        quantity: (map['quantity'] as num).toDouble(),
        initialQuantity:
            (map['initialQuantity'] as num?)?.toDouble() ??
                (map['quantity'] as num).toDouble(),
        receivedDate: DateTime.parse(map['receivedDate'] as String),
        supplierId: map['supplierId'] as String,
        notes: map['notes'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
  final String id;
  final String productId;
  final String batchNumber;
  final double price; // Cost price paid for this batch
  final double sellingPrice; // Retail price for this batch (0 = use product price)
  final DateTime? expiryDate;
  final double quantity;

  /// Quantity originally received for this batch (0 on very old databases,
  /// where only the remaining quantity was tracked).
  final double initialQuantity;

  /// Quantity already sold/used out of this batch.
  double get usedQuantity =>
      (initialQuantity - quantity).clamp(0.0, double.infinity);
  final DateTime receivedDate;
  final String supplierId;
  final String notes;
  final DateTime createdAt;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon {
    if (expiryDate == null) {
      return false;
    }
    final daysUntilExpiry = expiryDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry > 0;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) {
      return null;
    }
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  ProductBatch copyWith({
    String? id,
    String? productId,
    String? batchNumber,
    double? price,
    double? sellingPrice,
    DateTime? expiryDate,
    double? quantity,
    DateTime? receivedDate,
    String? supplierId,
    String? notes,
    DateTime? createdAt,
    double? initialQuantity,
  }) =>
      ProductBatch(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        batchNumber: batchNumber ?? this.batchNumber,
        price: price ?? this.price,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        expiryDate: expiryDate ?? this.expiryDate,
        quantity: quantity ?? this.quantity,
        receivedDate: receivedDate ?? this.receivedDate,
        supplierId: supplierId ?? this.supplierId,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        initialQuantity: initialQuantity ?? this.initialQuantity,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'batchNumber': batchNumber,
        'price': price,
        'sellingPrice': sellingPrice,
        'expiryDate': expiryDate?.toIso8601String(),
        'quantity': quantity,
        'initialQuantity': initialQuantity,
        'receivedDate': receivedDate.toIso8601String(),
        'supplierId': supplierId,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() =>
      'ProductBatch(id: $id, batchNumber: $batchNumber, qty: $quantity)';
}

/// A single slice of a sale fulfilled from a specific stock batch (FIFO).
class BatchAllocation {
  const BatchAllocation({
    required this.batchId,
    required this.batchNumber,
    required this.quantity,
    required this.unitPrice,
    required this.costPrice,
  });

  factory BatchAllocation.fromMap(Map<String, dynamic> map) => BatchAllocation(
        batchId: map['batchId'] as String? ?? '',
        batchNumber: map['batchNumber'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
        costPrice: (map['costPrice'] as num?)?.toDouble() ?? 0,
      );

  final String batchId;
  final String batchNumber;
  final double quantity;
  final double unitPrice;
  final double costPrice;

  Map<String, dynamic> toMap() => {
        'batchId': batchId,
        'batchNumber': batchNumber,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'costPrice': costPrice,
      };
}

/// Resolved picking plan for a cart line: which batches supply it and at what
/// cost/price. When no batches exist the product's own prices are used and
/// [allocations] is empty.
class FifoPlan {
  const FifoPlan({
    required this.allocations,
    required this.effectivePrice,
    required this.weightedCost,
  });

  final List<BatchAllocation> allocations;
  final double effectivePrice;
  final double weightedCost;

  String get batchLabel =>
      allocations.map((a) => a.batchNumber).toSet().join(', ');
}

