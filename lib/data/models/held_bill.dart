import 'package:uuid/uuid.dart';
import 'cart_item.dart';

class HeldBill {
  HeldBill({
    required this.items,
    String? id,
    this.discountPercentage = 0.0,
    this.customerName,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory HeldBill.fromMap(Map<String, dynamic> map) => HeldBill(
        id: map['id'] as String,
        items: [],
        discountPercentage: (map['discountPercentage'] as num).toDouble(),
        customerName: map['customerName'] as String?,
        notes: map['notes'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
  final String id;
  final List<CartItem> items;
  final double discountPercentage;
  final String? customerName;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get subtotal =>
      items.fold<double>(0, (sum, item) => sum + item.subtotal);
  double get totalDiscount =>
      items.fold<double>(0, (sum, item) => sum + item.discountAmount) +
      ((subtotal * discountPercentage) / 100);
  double get total => subtotal - totalDiscount;

  HeldBill copyWith({
    String? id,
    List<CartItem>? items,
    double? discountPercentage,
    String? customerName,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      HeldBill(
        id: id ?? this.id,
        items: items ?? this.items,
        discountPercentage: discountPercentage ?? this.discountPercentage,
        customerName: customerName ?? this.customerName,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'discountPercentage': discountPercentage,
        'customerName': customerName,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  @override
  String toString() =>
      'HeldBill(id: $id, items: ${items.length}, total: $total)';
}
