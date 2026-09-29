import 'dart:convert';

import 'package:uuid/uuid.dart';

class PurchaseOrderItem {
  PurchaseOrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.costPrice,
  });

  factory PurchaseOrderItem.fromMap(Map<String, dynamic> map) =>
      PurchaseOrderItem(
        productId: map['productId'] as String,
        productName: map['productName'] as String,
        quantity: map['quantity'] as int,
        costPrice: (map['costPrice'] as num).toDouble(),
      );

  final String productId;
  final String productName;
  final int quantity;
  final double costPrice;

  double get lineTotal => quantity * costPrice;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'costPrice': costPrice,
      };
}

class PurchaseOrder {
  PurchaseOrder({
    required this.supplierId,
    required this.supplierName,
    required this.items,
    String? id,
    String? orderNumber,
    this.status = 'Ordered',
    this.notes = '',
    DateTime? orderDate,
    this.receivedDate,
  })  : id = id ?? const Uuid().v4(),
        orderNumber = orderNumber ?? _generateOrderNumber(),
        orderDate = orderDate ?? DateTime.now();

  factory PurchaseOrder.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'];
    final items = rawItems is String ? jsonDecode(rawItems) : rawItems;
    return PurchaseOrder(
      id: map['id'] as String,
      orderNumber: map['orderNumber'] as String,
      supplierId: map['supplierId'] as String,
      supplierName: map['supplierName'] as String,
      items: (items as List)
          .map((e) => PurchaseOrderItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      status: map['status'] as String,
      notes: map['notes'] as String? ?? '',
      orderDate: DateTime.parse(map['orderDate'] as String),
      receivedDate: map['receivedDate'] != null
          ? DateTime.parse(map['receivedDate'] as String)
          : null,
    );
  }

  final String id;
  final String orderNumber;
  final String supplierId;
  final String supplierName;
  final List<PurchaseOrderItem> items;
  final String status; // 'Ordered' | 'Received' | 'Cancelled'
  final String notes;
  final DateTime orderDate;
  final DateTime? receivedDate;

  bool get isReceived => status == 'Received';
  bool get isCancelled => status == 'Cancelled';
  double get subtotal => items.fold<double>(0, (sum, i) => sum + i.lineTotal);
  double get total => subtotal;
  int get totalItems => items.fold<int>(0, (sum, i) => sum + i.quantity);

  Map<String, dynamic> toMap() => {
        'id': id,
        'orderNumber': orderNumber,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'items': items.map((e) => e.toMap()).toList(),
        'subtotal': subtotal,
        'total': total,
        'status': status,
        'notes': notes,
        'orderDate': orderDate.toIso8601String(),
        'receivedDate': receivedDate?.toIso8601String(),
      };

  PurchaseOrder copyWith({
    String? status,
    DateTime? receivedDate,
  }) => PurchaseOrder(
        id: id,
        orderNumber: orderNumber,
        supplierId: supplierId,
        supplierName: supplierName,
        items: items,
        status: status ?? this.status,
        notes: notes,
        orderDate: orderDate,
        receivedDate: receivedDate ?? this.receivedDate,
      );
}

/// Stable-ish, human-friendly order number: PO-YYYYMMDD-HHMMSS
String _generateOrderNumber() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'PO-$stamp';
}