part of 'database_service.dart';

extension RepackProduction on DatabaseService {
  /// Runs one [recipe] to make [quantityToProduce] finished units.
  ///
  /// Consumes components oldest-batch-first (recording each batch's cost),
  /// falls back to on-hand "no batch" stock, reduces the component products'
  /// totals, produces an output batch for the packed product, and logs every
  /// movement to [stock_history] so the stock ledger always reconciles the
  /// same way [completeSale] and GRN receipt do.
  Future<Production> createProduction(Recipe recipe, double quantityToProduce,
      {String producedBy = '', String notes = ''}) async {
    if (quantityToProduce <= 0) {
      throw ArgumentError('Enter how many units to produce.');
    }
    final db = await database;
    final yieldQty = recipe.yieldQuantity <= 0 ? 1.0 : recipe.yieldQuantity;
    final multiplier = quantityToProduce / yieldQty;

    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();

      // Validate every component BEFORE deducting anything, so a short run
      // can never leave stock half-consumed.
      for (final ri in recipe.items) {
        final needed = ri.quantityNeeded * multiplier;
        if (needed <= 0) continue;
        final pmaps = await txn.query('products',
            where: 'id = ?', whereArgs: [ri.componentProductId]);
        final available =
            pmaps.isNotEmpty ? Product.fromMap(pmaps.first).quantity : 0.0;
        if (pmaps.isEmpty || available + 1e-9 < needed) {
          final have = pmaps.isEmpty ? 0.0 : available;
          throw StateError(
              'Not enough ${ri.componentName} in stock to produce. '
              'Need ${needed.toStringAsFixed(2)}, only ${have.toStringAsFixed(2)} available.');
        }
      }

      final componentsAlloc = <ProductionComponent>[];
      double totalCompCost = 0.0;

      for (final ri in recipe.items) {
        var remaining = ri.quantityNeeded * multiplier;
        if (remaining <= 0) continue;
        double used = 0.0;

        // 1) Take as much as possible from FIFO batches.
        final batches = await _fifoBatches(txn, ri.componentProductId);
        for (final batch in batches) {
          if (remaining <= 1e-9) break;
          final take = batch.quantity.toDouble() < remaining
              ? batch.quantity.toDouble()
              : remaining;
          if (take <= 1e-9) continue;
          await txn.update(
            'product_batches',
            {'quantity': batch.quantity - take},
            where: 'id = ?',
            whereArgs: [batch.id],
          );
          remaining -= take;
          used += take;
          totalCompCost += batch.price * take;
          componentsAlloc.add(ProductionComponent(
            id: const Uuid().v4(),
            productionId: 'tmp',
            componentProductId: ri.componentProductId,
            componentName: ri.componentName,
            quantityUsed: take,
            costPerUnit: batch.price,
            batchId: batch.id,
            batchNumber: batch.batchNumber,
          ));
        }

        // 2) The validated remainder is on-hand stock with no batch.
        if (remaining > 1e-9) {
          final pmaps = await txn.query('products',
              where: 'id = ?', whereArgs: [ri.componentProductId]);
          final p = Product.fromMap(pmaps.first);
          final take = remaining;
          used += take;
          totalCompCost += p.buyingPrice * take;
          componentsAlloc.add(ProductionComponent(
            id: const Uuid().v4(),
            productionId: 'tmp',
            componentProductId: ri.componentProductId,
            componentName: ri.componentName,
            quantityUsed: take,
            costPerUnit: p.buyingPrice,
            batchId: '',
            batchNumber: '',
          ));
        }

        // 3) Keep the on-hand total in sync (same rule as completeSale) and
        //    log the movement so the ledger reconciles.
        if (used > 0) {
          final pmaps = await txn.query('products',
              where: 'id = ?', whereArgs: [ri.componentProductId]);
          if (pmaps.isNotEmpty) {
            final p = Product.fromMap(pmaps.first);
            final newQty = (p.quantity - used).clamp(0.0, double.infinity);
            await txn.update(
              'products',
              {'quantity': newQty, 'updatedAt': now},
              where: 'id = ?',
              whereArgs: [p.id],
            );
          }
          await txn.insert('stock_history', {
            'productId': ri.componentProductId,
            'productName': ri.componentName,
            'quantityChanged': -used,
            'reason': 'Production ${recipe.name}',
            'createdAt': now,
          });
        }
      }

      final unitCost =
          quantityToProduce > 0 ? totalCompCost / quantityToProduce : 0.0;
      final prod = Production(
        id: const Uuid().v4(),
        recipeId: recipe.id,
        recipeName: recipe.name,
        finishedProductId: recipe.finishedProductId,
        finishedProductName: recipe.finishedProductName,
        quantityProduced: quantityToProduce,
        totalComponentCost: totalCompCost,
        unitCost: unitCost,
        batchNumber: 'REPACK-${DateTime.now().millisecondsSinceEpoch}',
        notes: notes,
        producedAt: DateTime.now(),
        createdAt: DateTime.now(),
        producedBy: producedBy,
        components: componentsAlloc,
      );
      await txn.insert('productions', prod.toMap());
      for (final c in componentsAlloc) {
        await txn.insert(
            'production_components', c.copyWith(productionId: prod.id).toMap());
      }

      // Produce the finished product: add to its on-hand total and create the
      // output batch at the computed unit cost so later FIFO sales charge the
      // true packed cost (feeds straight into the profit report).
      final fMaps = await txn.query('products',
          where: 'id = ?', whereArgs: [recipe.finishedProductId]);
      if (fMaps.isNotEmpty) {
        final fp = Product.fromMap(fMaps.first);
        final newQty = fp.quantity + quantityToProduce;
        await txn.update(
          'products',
          {
            'quantity': newQty,
            'buyingPrice': unitCost > 0 ? unitCost : fp.buyingPrice,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [fp.id],
        );
        await txn.insert('product_batches', {
          'id': const Uuid().v4(),
          'productId': fp.id,
          'batchNumber': prod.batchNumber,
          'price': unitCost,
          'sellingPrice': fp.sellingPrice,
          'expiryDate': null,
          'quantity': quantityToProduce,
          'initialQuantity': quantityToProduce,
          'receivedDate': now,
          'supplierId': fp.supplierId ?? '',
          'notes': 'Repacked via ${prod.id}',
          'createdAt': now,
        });
        await txn.insert('stock_history', {
          'productId': fp.id,
          'productName': fp.name,
          'quantityChanged': quantityToProduce,
          'reason': 'Production ${recipe.name}',
          'createdAt': now,
        });
      } else {
        throw StateError(
            'Finished product "${recipe.finishedProductName}" no longer exists. '
            'Update the recipe before producing.');
      }
      return prod;
    }).whenComplete(() {
      BackupService.notifyTransaction('repack production');
    });
  }
}