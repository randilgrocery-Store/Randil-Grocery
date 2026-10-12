import 'product.dart';

class CartItem { // discount is in percentage (0-100)

  CartItem({
    required this.id,
    required this.product,
    this.quantity = 1,
    this.discount = 0.0,
    double? unitPrice,
    this.loose = false,
    this.piecesPerBox = 1,
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

  /// True when this line sells loose single pieces taken from the box rather
  /// than whole boxes. [quantity] then counts pieces and [unitPrice] is the
  /// price of one piece.
  final bool loose;

  /// Pieces per box, copied from the product when the line was added. Only
  /// meaningful for a [loose] line (used to work out the fraction of a box the
  /// pieces take off stock).
  final int piecesPerBox;

  /// True when this line sells whole boxes (the box carries the only barcode).
  bool get isBox => product.isBreakBulk && !loose;

  /// How much this line removes from the product's stock, expressed in the
  /// product's stock unit (boxes). A loose line takes `quantity / piecesPerBox`
  /// of a box; every other line takes its quantity box for box.
  double get stockQuantity =>
      loose && piecesPerBox > 0 ? quantity / piecesPerBox : quantity;

  double get subtotal => unitPrice * quantity;
  double get discountAmount => (subtotal * discount) / 100;
  double get total => subtotal - discountAmount;

  CartItem copyWith({
    String? id,
    Product? product,
    double? quantity,
    double? discount,
    double? unitPrice,
    bool? loose,
    int? piecesPerBox,
  }) => CartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      unitPrice: unitPrice ?? this.unitPrice,
      loose: loose ?? this.loose,
      piecesPerBox: piecesPerBox ?? this.piecesPerBox,
    );

  @override
  String toString() =>
      'CartItem(id: $id, product: ${product.name}, quantity: $quantity, total: $total)';
}
