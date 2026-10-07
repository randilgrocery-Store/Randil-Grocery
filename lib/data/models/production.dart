import 'package:uuid/uuid.dart';

class ProductionComponent {
  ProductionComponent({
    required this.id,
    required this.productionId,
    required this.componentProductId,
    required this.componentName,
    required this.quantityUsed,
    required this.costPerUnit,
    this.batchId = '',
    this.batchNumber = '',
  });

  factory ProductionComponent.fromMap(Map<String, dynamic> map) => ProductionComponent(
        id: map['id'] as String,
        productionId: map['productionId'] as String,
        componentProductId: map['componentProductId'] as String,
        componentName: map['componentName'] as String,
        quantityUsed: (map['quantityUsed'] as num).toDouble(),
        costPerUnit: (map['costPerUnit'] as num).toDouble(),
        batchId: map['batchId'] as String? ?? '',
        batchNumber: map['batchNumber'] as String? ?? '',
      );

  final String id;
  final String productionId;
  final String componentProductId;
  final String componentName;
  final double quantityUsed;
  final double costPerUnit;
  final String batchId;
  final String batchNumber;

  double get totalCost => costPerUnit * quantityUsed;

  Map<String, dynamic> toMap() => {
        'id': id,
        'productionId': productionId,
        'componentProductId': componentProductId,
        'componentName': componentName,
        'quantityUsed': quantityUsed,
        'costPerUnit': costPerUnit,
        'batchId': batchId,
        'batchNumber': batchNumber,
      };

  ProductionComponent copyWith({
    String? id,
    String? productionId,
    String? componentProductId,
    String? componentName,
    double? quantityUsed,
    double? costPerUnit,
    String? batchId,
    String? batchNumber,
  }) =>
      ProductionComponent(
        id: id ?? this.id,
        productionId: productionId ?? this.productionId,
        componentProductId: componentProductId ?? this.componentProductId,
        componentName: componentName ?? this.componentName,
        quantityUsed: quantityUsed ?? this.quantityUsed,
        costPerUnit: costPerUnit ?? this.costPerUnit,
        batchId: batchId ?? this.batchId,
        batchNumber: batchNumber ?? this.batchNumber,
      );
}

class Production {
  Production({
    required this.recipeId,
    required this.recipeName,
    required this.finishedProductId,
    required this.finishedProductName,
    required this.quantityProduced,
    required this.totalComponentCost,
    required this.unitCost,
    String? id,
    this.batchNumber = '',
    this.notes = '',
    DateTime? producedAt,
    DateTime? createdAt,
    this.components = const [],
    this.producedBy = '',
  })  : id = id ?? const Uuid().v4(),
        producedAt = producedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory Production.fromMap(Map<String, dynamic> map) => Production(
        id: map['id'] as String,
        recipeId: map['recipeId'] as String,
        recipeName: map['recipeName'] as String,
        finishedProductId: map['finishedProductId'] as String,
        finishedProductName: map['finishedProductName'] as String,
        quantityProduced: (map['quantityProduced'] as num).toDouble(),
        totalComponentCost: (map['totalComponentCost'] as num).toDouble(),
        unitCost: (map['unitCost'] as num).toDouble(),
        batchNumber: map['batchNumber'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        producedAt: DateTime.parse(map['producedAt'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
        producedBy: map['producedBy'] as String? ?? '',
        components: const [],
      );

  final String id;
  final String recipeId;
  final String recipeName;
  final String finishedProductId;
  final String finishedProductName;
  final double quantityProduced;
  final double totalComponentCost;
  final double unitCost;
  final String batchNumber;
  final String notes;
  final DateTime producedAt;
  final DateTime createdAt;
  final String producedBy;
  final List<ProductionComponent> components;

  Production copyWith({
    String? id,
    String? recipeId,
    String? recipeName,
    String? finishedProductId,
    String? finishedProductName,
    double? quantityProduced,
    double? totalComponentCost,
    double? unitCost,
    String? batchNumber,
    String? notes,
    DateTime? producedAt,
    DateTime? createdAt,
    String? producedBy,
    List<ProductionComponent>? components,
  }) =>
      Production(
        id: id ?? this.id,
        recipeId: recipeId ?? this.recipeId,
        recipeName: recipeName ?? this.recipeName,
        finishedProductId: finishedProductId ?? this.finishedProductId,
        finishedProductName: finishedProductName ?? this.finishedProductName,
        quantityProduced: quantityProduced ?? this.quantityProduced,
        totalComponentCost: totalComponentCost ?? this.totalComponentCost,
        unitCost: unitCost ?? this.unitCost,
        batchNumber: batchNumber ?? this.batchNumber,
        notes: notes ?? this.notes,
        producedAt: producedAt ?? this.producedAt,
        createdAt: createdAt ?? this.createdAt,
        producedBy: producedBy ?? this.producedBy,
        components: components ?? this.components,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'recipeId': recipeId,
        'recipeName': recipeName,
        'finishedProductId': finishedProductId,
        'finishedProductName': finishedProductName,
        'quantityProduced': quantityProduced,
        'totalComponentCost': totalComponentCost,
        'unitCost': unitCost,
        'batchNumber': batchNumber,
        'notes': notes,
        'producedAt': producedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'producedBy': producedBy,
      };
}
