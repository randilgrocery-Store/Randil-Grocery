import 'package:uuid/uuid.dart';

class RecipeItem {
  RecipeItem({
    required this.id,
    required this.recipeId,
    required this.componentProductId,
    required this.componentName,
    required this.quantityNeeded,
    this.unit = 'pcs',
  });

  factory RecipeItem.fromMap(Map<String, dynamic> map) => RecipeItem(
        id: map['id'] as String,
        recipeId: map['recipeId'] as String,
        componentProductId: map['componentProductId'] as String,
        componentName: map['componentName'] as String,
        quantityNeeded: (map['quantityNeeded'] as num).toDouble(),
        unit: map['unit'] as String? ?? 'pcs',
      );

  final String id;
  final String recipeId;
  final String componentProductId;
  final String componentName;
  final double quantityNeeded;
  final String unit;

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipeId': recipeId,
        'componentProductId': componentProductId,
        'componentName': componentName,
        'quantityNeeded': quantityNeeded,
        'unit': unit,
      };

  RecipeItem copyWith({
    String? id,
    String? recipeId,
    String? componentProductId,
    String? componentName,
    double? quantityNeeded,
    String? unit,
  }) =>
      RecipeItem(
        id: id ?? this.id,
        recipeId: recipeId ?? this.recipeId,
        componentProductId: componentProductId ?? this.componentProductId,
        componentName: componentName ?? this.componentName,
        quantityNeeded: quantityNeeded ?? this.quantityNeeded,
        unit: unit ?? this.unit,
      );
}

class Recipe {
  Recipe({
    required this.name,
    required this.finishedProductId,
    required this.finishedProductName,
    required this.yieldQuantity,
    String? id,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.items = const [],
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Recipe.fromMap(Map<String, dynamic> map) => Recipe(
        id: map['id'] as String,
        name: map['name'] as String,
        finishedProductId: map['finishedProductId'] as String,
        finishedProductName: map['finishedProductName'] as String,
        yieldQuantity: (map['yieldQuantity'] as num).toDouble(),
        notes: map['notes'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        items: const [],
      );

  final String id;
  final String name;
  final String finishedProductId;
  final String finishedProductName;
  final double yieldQuantity;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RecipeItem> items;

  Recipe copyWith({
    String? id,
    String? name,
    String? finishedProductId,
    String? finishedProductName,
    double? yieldQuantity,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<RecipeItem>? items,
  }) =>
      Recipe(
        id: id ?? this.id,
        name: name ?? this.name,
        finishedProductId: finishedProductId ?? this.finishedProductId,
        finishedProductName: finishedProductName ?? this.finishedProductName,
        yieldQuantity: yieldQuantity ?? this.yieldQuantity,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        items: items ?? this.items,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'finishedProductId': finishedProductId,
        'finishedProductName': finishedProductName,
        'yieldQuantity': yieldQuantity,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
