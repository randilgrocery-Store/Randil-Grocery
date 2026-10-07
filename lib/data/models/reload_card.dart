class ReloadCard {
  final String id;
  final String cardNumber;
  final String supplier;
  final double value;
  final double cost;
  final String status; // 'bought' | 'sold' (+ legacy 'sent'/'used')
  final String? customerPhone;
  final String? customerName;
  final DateTime createdAt;
  final DateTime? usedAt;
  final String? notes;

  /// For a Sold row, the id of the Bought batch it was sold from. Empty for
  /// rows that were never linked (legacy data or a plain buy).
  final String batchId;

  ReloadCard({
    required this.id,
    this.cardNumber = '',
    this.supplier = '',
    required this.value,
    this.cost = 0.0,
    required this.status,
    this.customerPhone,
    this.customerName,
    required this.createdAt,
    this.usedAt,
    this.notes,
    this.batchId = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'cardNumber': cardNumber,
        'batchId': batchId,
        'supplier': supplier,
        'value': value,
        'cost': cost,
        'status': status,
        'customerPhone': customerPhone ?? '',
        'customerName': customerName ?? '',
        'createdAt': createdAt.toIso8601String(),
        'usedAt': usedAt?.toIso8601String() ?? '',
        'notes': notes ?? '',
      };

  factory ReloadCard.fromMap(Map<String, dynamic> map) => ReloadCard(
        id: map['id'] as String,
        cardNumber: map['cardNumber'] as String? ?? '',
        batchId: map['batchId'] as String? ?? '',
        supplier: map['supplier'] as String? ?? '',
        value: (map['value'] as num).toDouble(),
        cost: (map['cost'] as num?)?.toDouble() ?? 0.0,
        status: map['status'] as String,
        customerPhone: map['customerPhone'] as String?,
        customerName: map['customerName'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        usedAt: map['usedAt'] != null && (map['usedAt'] as String).isNotEmpty
            ? DateTime.parse(map['usedAt'] as String)
            : null,
        notes: map['notes'] as String?,
      );

  ReloadCard copyWith({
    String? id,
    String? cardNumber,
    String? batchId,
    String? supplier,
    double? value,
    double? cost,
    String? status,
    String? customerPhone,
    String? customerName,
    DateTime? createdAt,
    DateTime? usedAt,
    String? notes,
  }) =>
      ReloadCard(
        id: id ?? this.id,
        cardNumber: cardNumber ?? this.cardNumber,
        batchId: batchId ?? this.batchId,
        supplier: supplier ?? this.supplier,
        value: value ?? this.value,
        cost: cost ?? this.cost,
        status: status ?? this.status,
        customerPhone: customerPhone ?? this.customerPhone,
        customerName: customerName ?? this.customerName,
        createdAt: createdAt ?? this.createdAt,
        usedAt: usedAt ?? this.usedAt,
        notes: notes ?? this.notes,
      );
}