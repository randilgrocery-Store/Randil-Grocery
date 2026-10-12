import 'package:uuid/uuid.dart';

class Expense {
  Expense({
    required this.description,
    required this.category,
    required this.amount,
    String? id,
    DateTime? expenseDate,
    this.notes = '',
    this.recordedBy = '',
    this.paidTo = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        expenseDate = expenseDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] as String,
        description: map['description'] as String,
        category: map['category'] as String,
        amount: (map['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(map['expenseDate'] as String),
        notes: map['notes'] as String? ?? '',
        recordedBy: map['recordedBy'] as String? ?? '',
        paidTo: map['paidTo'] as String? ?? '',
        createdAt: map['createdAt'] != null && (map['createdAt'] as String).isNotEmpty
            ? DateTime.parse(map['createdAt'] as String)
            : DateTime.parse(map['expenseDate'] as String),
      );

  final String id;
  final String description;
  final String category;
  final double amount;
  final DateTime expenseDate;
  final String notes;
  final String recordedBy;

  /// Who received the money (supplier, worker, landlord...). Optional for old
  /// rows, required by the entry form so the cash drawer can be reconciled.
  final String paidTo;

  /// When the record was entered (the user may back-date [expenseDate]).
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'description': description,
        'category': category,
        'amount': amount,
        'expenseDate': expenseDate.toIso8601String(),
        'notes': notes,
        'recordedBy': recordedBy,
        'paidTo': paidTo,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() =>
      'Expense(id: $id, description: $description, amount: $amount, date: $expenseDate)';
}