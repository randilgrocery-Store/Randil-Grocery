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
  })  : id = id ?? const Uuid().v4(),
        expenseDate = expenseDate ?? DateTime.now();

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] as String,
        description: map['description'] as String,
        category: map['category'] as String,
        amount: (map['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(map['expenseDate'] as String),
        notes: map['notes'] as String? ?? '',
        recordedBy: map['recordedBy'] as String? ?? '',
      );

  final String id;
  final String description;
  final String category;
  final double amount;
  final DateTime expenseDate;
  final String notes;
  final String recordedBy;

  Map<String, dynamic> toMap() => {
        'id': id,
        'description': description,
        'category': category,
        'amount': amount,
        'expenseDate': expenseDate.toIso8601String(),
        'notes': notes,
        'recordedBy': recordedBy,
      };

  @override
  String toString() =>
      'Expense(id: $id, description: $description, amount: $amount, date: $expenseDate)';
}