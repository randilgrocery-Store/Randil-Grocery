import 'package:uuid/uuid.dart';

/// A payment made TO a supplier for goods they supplied.
/// Grocery stores settle suppliers with cash on delivery or a cheque
/// written against the shop's bank account — those are the only two
/// methods this record supports.
class SupplierPayment {
  SupplierPayment({
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    required this.method,
    this.chequeNumber = '',
    this.bankName = '',
    this.chequeDate,
    this.note = '',
    String? id,
    DateTime? paymentDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        paymentDate = paymentDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  static const String methodCash = 'cash';
  static const String methodCheque = 'cheque';

  factory SupplierPayment.fromMap(Map<String, dynamic> map) =>
      SupplierPayment(
        id: map['id'] as String,
        supplierId: map['supplierId'] as String,
        supplierName: map['supplierName'] as String? ?? '',
        amount: (map['amount'] as num).toDouble(),
        method: map['method'] as String? ?? methodCash,
        chequeNumber: map['chequeNumber'] as String? ?? '',
        bankName: map['bankName'] as String? ?? '',
        chequeDate: map['chequeDate'] != null
            ? DateTime.parse(map['chequeDate'] as String)
            : null,
        note: map['note'] as String? ?? '',
        paymentDate: DateTime.parse(map['paymentDate'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
      );

  final String id;
  final String supplierId;
  final String supplierName;
  final double amount;

  /// 'cash' or 'cheque'
  final String method;
  final String chequeNumber;
  final String bankName;
  final DateTime? chequeDate;
  final String note;
  final DateTime paymentDate;
  final DateTime createdAt;

  bool get isCheque => method == methodCheque;

  Map<String, dynamic> toMap() => {
        'id': id,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'amount': amount,
        'method': method,
        'chequeNumber': chequeNumber,
        'bankName': bankName,
        'chequeDate': chequeDate?.toIso8601String(),
        'note': note,
        'paymentDate': paymentDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}
