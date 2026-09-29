import 'package:uuid/uuid.dart';

class Product {
  Product({
    required this.name,
    required this.barcode,
    required this.categoryId,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.quantity,
    String? id,
    this.expiryDate,
    this.supplierId,
    this.reorderLevel,
    this.imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Create from Map (from database)
  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String,
        barcode: map['barcode'] as String,
        categoryId: map['categoryId'] as String,
        buyingPrice: (map['buyingPrice'] as num).toDouble(),
        sellingPrice: (map['sellingPrice'] as num).toDouble(),
        quantity: map['quantity'] as int,
        expiryDate: map['expiryDate'] != null
            ? DateTime.parse(map['expiryDate'] as String)
            : null,
        supplierId: map['supplierId'] as String?,
        reorderLevel: map['reorderLevel'] as int?,
        imagePath: map['imagePath'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
  final String id;
  final String name;
  final String barcode;
  final String categoryId;
  final double buyingPrice;
  final double sellingPrice;
  final int quantity;
  final DateTime? expiryDate; // For grocery products
  final String? supplierId; // Link to primary supplier
  final int? reorderLevel; // Auto-reorder when below this quantity
  final String? imagePath; // Path to product image
  final DateTime createdAt;
  final DateTime updatedAt;

  // Getters for profit calculation
  double get profit => sellingPrice - buyingPrice;
  double get profitMargin => (profit / sellingPrice) * 100;

  // Getters for expiry tracking
  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());
  bool get isExpiringSoon {
    if (expiryDate == null) {
      return false;
    }
    final daysUntilExpiry = expiryDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry > 0;
  }

  // NEW: Getters for inventory management
  bool get needsReorder => reorderLevel != null && quantity <= reorderLevel!;
  bool get isLowStock => reorderLevel != null && quantity < (reorderLevel! * 2);

  int? get daysUntilExpiry {
    if (expiryDate == null) {
      return null;
    }
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    String? categoryId,
    double? buyingPrice,
    double? sellingPrice,
    int? quantity,
    DateTime? expiryDate,
    String? supplierId,
    int? reorderLevel,
    String? imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        categoryId: categoryId ?? this.categoryId,
        buyingPrice: buyingPrice ?? this.buyingPrice,
        sellingPrice: sellingPrice ?? this.sellingPrice,
        quantity: quantity ?? this.quantity,
        expiryDate: expiryDate ?? this.expiryDate,
        supplierId: supplierId ?? this.supplierId,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        imagePath: imagePath ?? this.imagePath,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  // Convert to Map for database
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'barcode': barcode,
        'categoryId': categoryId,
        'buyingPrice': buyingPrice,
        'sellingPrice': sellingPrice,
        'quantity': quantity,
        'expiryDate': expiryDate?.toIso8601String(),
        'supplierId': supplierId,
        'reorderLevel': reorderLevel,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  @override
  String toString() =>
      'Product(id: $id, name: $name, barcode: $barcode, quantity: $quantity)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
