part of 'database_service.dart';

extension RepackCrud on DatabaseService {
  Future<String> insertRecipe(Recipe recipe) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('recipes', recipe.toMap());
      for (final item in recipe.items) {
        final m = item.toMap()..['recipeId'] = recipe.id;
        m['id'] = const Uuid().v4();
        await txn.insert('recipe_items', m);
      }
    });
    BackupService.notifyTransaction('repack recipe');
    return recipe.id;
  }

  Future<List<Recipe>> getAllRecipes() async {
    final db = await database;
    final maps = await db.query('recipes', orderBy: 'name ASC');
    final recipes = <Recipe>[];
    for (final m in maps) {
      final r = Recipe.fromMap(m);
      final items = await db.query('recipe_items', where: 'recipeId = ?', whereArgs: [r.id]);
      recipes.add(r.copyWith(items: items.map((e) => RecipeItem.fromMap(e)).toList()));
    }
    return recipes;
  }

  Future<Recipe?> getRecipeById(String id) async {
    final db = await database;
    final maps = await db.query('recipes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final r = Recipe.fromMap(maps.first);
    final items = await db.query('recipe_items', where: 'recipeId = ?', whereArgs: [id]);
    return r.copyWith(items: items.map((e) => RecipeItem.fromMap(e)).toList());
  }

  Future<void> deleteRecipe(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('recipe_items', where: 'recipeId = ?', whereArgs: [id]);
      await txn.delete('recipes', where: 'id = ?', whereArgs: [id]);
    });
    BackupService.notifyTransaction('repack recipe');
  }

  Future<void> updateRecipe(Recipe recipe) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('recipes', recipe.toMap()..['updatedAt'] = DateTime.now().toIso8601String(),
          where: 'id = ?', whereArgs: [recipe.id]);
      await txn.delete('recipe_items', where: 'recipeId = ?', whereArgs: [recipe.id]);
      for (final item in recipe.items) {
        final m = item.toMap()..['recipeId'] = recipe.id;
        m['id'] = m['id'] ?? const Uuid().v4();
        await txn.insert('recipe_items', m);
      }
    });
    BackupService.notifyTransaction('repack recipe');
  }

  Future<List<Production>> getAllProductions() async {
    final db = await database;
    final maps = await db.query('productions', orderBy: 'producedAt DESC');
    final list = <Production>[];
    for (final m in maps) {
      final p = Production.fromMap(m);
      final comps = await db.query('production_components', where: 'productionId = ?', whereArgs: [p.id]);
      list.add(p.copyWith(components: comps.map((e) => ProductionComponent.fromMap(e)).toList()));
    }
    return list;
  }
}