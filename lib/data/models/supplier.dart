import 'package:uuid/uuid.dart';

class Supplier {

  Supplier({
    required this.name, required this.contactPerson, required this.phone, required this.email, required this.address, String? id,
    this.paymentTerms = 'COD',
    this.creditLimit,
    this.currentBalance = 0.0,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
      id: map['id'] as String,
      name: map['name'] as String,
      contactPerson: map['contactPerson'] as String,
      phone: map['phone'] as String,
      email: map['email'] as String,
      address: map['address'] as String,
      paymentTerms: map['paymentTerms'] as String? ?? 'COD',
      creditLimit: map['creditLimit'] != null
          ? (map['creditLimit'] as num).toDouble()
          : null,
      currentBalance: (map['currentBalance'] as num?)?.toDouble() ?? 0.0,
      isActive: (map['isActive'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  final String id;
  final String name;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final String paymentTerms; // e.g., "Net 30", "COD"
  final double? creditLimit;
  final double currentBalance; // Amount owed
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier copyWith({
    String? id,
    String? name,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    String? paymentTerms,
    double? creditLimit,
    double? currentBalance,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      contactPerson: contactPerson ?? this.contactPerson,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      creditLimit: creditLimit ?? this.creditLimit,
      currentBalance: currentBalance ?? this.currentBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );

  Map<String, dynamic> toMap() => {
      'id': id,
      'name': name,
      'contactPerson': contactPerson,
      'phone': phone,
      'email': email,
      'address': address,
      'paymentTerms': paymentTerms,
      'creditLimit': creditLimit,
      'currentBalance': currentBalance,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };

  @override
  String toString() => 'Supplier(id: $id, name: $name)';
}
