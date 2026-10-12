import 'package:uuid/uuid.dart';

/// One shopping-bag tier — the bag price points a shop sells at
/// (e.g. Rs 3 / Rs 5 / Rs 10 / Rs 20).
///
/// Bags are deliberately NOT part of the grocery catalog: their stock lives in
/// this table, so the Shopping Bags section owns its own stock, profit & loss
/// and history without ever mixing with the inventory screens.
class ShoppingBag {
  ShoppingBag({
    required this.label,
    required this.price,
    required this.buyingPrice,
    this.quantity = 0,
    String? id,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory ShoppingBag.fromMap(Map<String, dynamic> map) => ShoppingBag(
        id: map['id'] as String,
        label: map['label'] as String,
        price: (map['price'] as num).toDouble(),
        buyingPrice: (map['buyingPrice'] as num).toDouble(),
        quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );

  final String id;
  final String label;
  final double price;

  /// Cost price of a single bag (used for profit & loss and shop-use costing).
  final double buyingPrice;

  /// Bags on hand, tracked in this table only.
  double quantity;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Margin made when one bag is sold.
  double get profitPerBag => price - buyingPrice;

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'price': price,
        'buyingPrice': buyingPrice,
        'quantity': quantity,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// One movement of shopping bags: sold to a customer, taken for the shop's own
/// use, or restocked. Rides the LAN mirror so both PCs see the same sold and
/// used totals.
class ShoppingBagUsage {
  ShoppingBagUsage({
    required this.bagId,
    required this.bagLabel,
    required this.bagPrice,
    required this.bagCost,
    required this.quantity,
    required this.type,
    this.saleId = '',
    String? id,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory ShoppingBagUsage.fromMap(Map<String, dynamic> map) =>
      ShoppingBagUsage(
        id: map['id'] as String,
        bagId: map['bagId'] as String,
        bagLabel: map['bagLabel'] as String? ?? '',
        bagPrice: (map['bagPrice'] as num).toDouble(),
        bagCost: (map['bagCost'] as num?)?.toDouble() ?? 0,
        quantity: (map['quantity'] as num).toDouble(),
        type: map['type'] as String,
        saleId: map['saleId'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  final String id;
  final String bagId;
  final String bagLabel;
  final double bagPrice;
  final double bagCost;

  /// Bags moved (always positive; the direction is carried by [type]).
  final double quantity;

  /// 'customer_sell' | 'shop_use' | 'restock'.
  final String type;

  /// Sale id when the movement was rung up on the POS, otherwise ''.
  final String saleId;
  final DateTime createdAt;

  /// Money this movement represents (sale value for sells, cost for shop use).
  double get value => bagPrice * quantity;
  double get cost => bagCost * quantity;

  Map<String, dynamic> toMap() => {
        'id': id,
        'bagId': bagId,
        'bagLabel': bagLabel,
        'bagPrice': bagPrice,
        'bagCost': bagCost,
        'quantity': quantity,
        'value': value,
        'type': type,
        'saleId': saleId,
        'createdAt': createdAt.toIso8601String(),
      };
}