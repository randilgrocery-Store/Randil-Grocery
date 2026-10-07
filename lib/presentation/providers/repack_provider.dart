import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/recipe.dart';
import '../../data/models/production.dart';

class RepackProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  List<Recipe> _recipes = [];
  List<Production> _productions = [];
  bool _isLoading = false;

  List<Recipe> get recipes => _recipes;
  List<Production> get productions => _productions;
  bool get isLoading => _isLoading;

  Future<void> loadRecipes() async {
    _setLoading(true);
    try {
      _recipes = await _db.getAllRecipes();
    } catch (e) {
      debugPrint('loadRecipes error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadProductions() async {
    _setLoading(true);
    try {
      _productions = await _db.getAllProductions();
    } catch (e) {
      debugPrint('loadProductions error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAll() async {
    _setLoading(true);
    try {
      _recipes = await _db.getAllRecipes();
      _productions = await _db.getAllProductions();
    } catch (e) {
      debugPrint('repack loadAll error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<String> createRecipe(Recipe recipe) async {
    final id = await _db.insertRecipe(recipe);
    await loadRecipes();
    return id;
  }

  Future<void> updateRecipe(Recipe recipe) async {
    await _db.updateRecipe(recipe);
    await loadRecipes();
  }

  Future<void> deleteRecipe(String id) async {
    await _db.deleteRecipe(id);
    await loadRecipes();
  }

  Future<Production> produce(Recipe recipe, double qty,
      {String producedBy = '', String notes = ''}) async {
    final p = await _db.createProduction(recipe, qty,
        producedBy: producedBy, notes: notes);
    await loadProductions();
    return p;
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
