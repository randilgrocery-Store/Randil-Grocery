import 'dart:convert';

import 'package:uuid/uuid.dart';

class GrnItem {
  GrnItem({
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.quantity,
    required this.costPrice,
    required this.sellingPrice,
    this.batchNumber = '',
    this.expiryDate,
  });

  factory GrnItem.fromMap(Map<String, dynamic> map) => GrnItem(
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        barcode: map['barcode'] as String? ?? '',
        quantity: (map['quantity'] as num).toDouble(),
        costPrice: (map['costPrice'] as num).toDouble(),
        sellingPrice: (map['sellingPrice'] as num).toDouble(),
        batchNumber: map['batchNumber'] as String? ?? '',
        expiryDate: map['expiryDate'] != null
            ? DateTime.parse(map['expiryDate'] as String)
            : null,
      );

  final String productId;
  final String productName;
  final String barcode;
  final double quantity;
  final double costPrice;
  final double sellingPrice;
  final String batchNumber;
  final DateTime? expiryDate;

  double get lineTotal => quantity * costPrice;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'barcode': barcode,
        'quantity': quantity,
        'costPrice': costPrice,
        'sellingPrice': sellingPrice,
        'batchNumber': batchNumber,
        'expiryDate': expiryDate?.toIso8601String(),
      };
}

/// A Goods Received Note records stock actually received from a supplier.
/// Every line carries its own cost and retail price so goods bought at a
/// different price can be sold at that price (FIFO) without re-pricing the
/// stock that is already on the shelf.
class GoodsReceivedNote {
  GoodsReceivedNote({
    required this.supplierId,
    required this.supplierName,
    required this.items,
    String? id,
    String? grnNumber,
    this.receivedBy = '',
    this.notes = '',
    DateTime? receivedDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        grnNumber = grnNumber ?? generateGrnNumber(),
        receivedDate = receivedDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory GoodsReceivedNote.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    final items = rawItems is String ? jsonDecode(rawItems) : rawItems;
    return GoodsReceivedNote(
      id: map['id'] as String,
      grnNumber: map['grnNumber'] as String,
      supplierId: map['supplierId'] as String,
      supplierName: map['supplierName'] as String,
      items: (items as List)
          .map((e) => GrnItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      receivedBy: map['receivedBy'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      receivedDate: DateTime.parse(map['receivedDate'] as String),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  final String id;
  final String grnNumber;
  final String supplierId;
  final String supplierName;
  final List<GrnItem> items;
  final String receivedBy;
  final String notes;
  final DateTime receivedDate;
  final DateTime createdAt;

  double get total => items.fold<double>(0, (sum, i) => sum + i.lineTotal);
  double get totalItems => items.fold<double>(0, (sum, i) => sum + i.quantity);

  Map<String, dynamic> toMap() => {
        'id': id,
        'grnNumber': grnNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'items': items.map((e) => e.toMap()).toList(),
        'total': total,
        'receivedBy': receivedBy,
        'notes': notes,
        'receivedDate': receivedDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Human-friendly GRN number: GRN-YYYYMMDD-HHMMSS.
String generateGrnNumber() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'GRN-$stamp';
}
