import 'product.dart';

class CartItem { // discount is in percentage (0-100)

  CartItem({
    required this.id,
    required this.product,
    this.quantity = 1,
    this.discount = 0.0,
    double? unitPrice,
  }) : unitPrice = unitPrice ?? product.sellingPrice;
  final String id;
  final Product product;
  double quantity;
  double discount;

  /// The price actually being charged for this line, resolved from the
  /// oldest (FIFO) stock batch(es) for the product. Falls back to the product's
  /// current selling price when no batch price is available. Recalculated when
  /// the quantity changes so a line spanning batches is priced as a weighted
  /// average (matching what is actually charged).
  double unitPrice;

  double get subtotal => unitPrice * quantity;
  double get discountAmount => (subtotal * discount) / 100;
  double get total => subtotal - discountAmount;

  CartItem copyWith({
    String? id,
    Product? product,
    double? quantity,
    double? discount,
    double? unitPrice,
  }) => CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      unitPrice: unitPrice ?? this.unitPrice,
    );

  @override
  String toString() =>
      'CartItem(id: $id, product: ${product.name}, quantity: $quantity, total: $total)';
}
