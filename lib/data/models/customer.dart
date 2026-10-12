import 'package:uuid/uuid.dart';

class Customer {
  Customer({
    required this.name,
    required this.phone,
    String? email,
    String? id,
    this.address,
    this.totalSpent = 0.0,
    this.totalTransactions = 0,
    DateTime? createdAt,
    DateTime? lastPurchaseDate,
    DateTime? updatedAt,
    this.isActive = true,
  })  : email = email ?? '',
        id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        lastPurchaseDate = lastPurchaseDate ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        email: (map['email'] as String?)?.isEmpty ?? true ? null : map['email'],
        address: (map['address'] as String?)?.isEmpty ?? true
            ? null
            : map['address'],
        totalSpent: (map['totalSpent'] as num).toDouble(),
        totalTransactions: map['totalTransactions'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        lastPurchaseDate: DateTime.parse(map['lastPurchaseDate'] as String),
        updatedAt: map['updatedAt'] != null &&
                (map['updatedAt'] as String).isNotEmpty
            ? DateTime.parse(map['updatedAt'] as String)
            : DateTime.parse(map['lastPurchaseDate'] as String),
        isActive: (map['isActive'] as int) == 1,
      );
  final String id;
  final String name;
  final String phone;
  final String email;
  final String? address;
  final double totalSpent;
  final int totalTransactions;
  final DateTime createdAt;
  final DateTime lastPurchaseDate;

  /// Last time any field changed — the LAN mirror's clock for this row.
  final DateTime updatedAt;
  final bool isActive;

  Customer copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    double? totalSpent,
    int? totalTransactions,
    DateTime? lastPurchaseDate,
    DateTime? updatedAt,
    bool? isActive,
  }) =>
      Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        totalSpent: totalSpent ?? this.totalSpent,
        totalTransactions: totalTransactions ?? this.totalTransactions,
        createdAt: createdAt,
        lastPurchaseDate: lastPurchaseDate ?? this.lastPurchaseDate,
        updatedAt: updatedAt ?? this.updatedAt,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address ?? '',
        'totalSpent': totalSpent,
        'totalTransactions': totalTransactions,
        'createdAt': createdAt.toIso8601String(),
        'lastPurchaseDate': lastPurchaseDate.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isActive': isActive ? 1 : 0,
      };

  @override
  String toString() => 'Customer(id: $id, name: $name, phone: $phone)';
}
