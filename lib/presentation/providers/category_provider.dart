import 'package:flutter/material.dart';
import '../../data/database/database_service.dart';
import '../../data/models/category.dart';

class CategoryProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  List<Category> _categories = [];
  bool _isLoading = false;
  String _errorMessage = '';

  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  Future<void> loadCategories() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    try {
      _categories = await _dbService.getAllCategories();
      _categories.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      _errorMessage = 'Error loading categories: $e';
      debugPrint(_errorMessage);
      _categories = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addCategory(Category category) async {
    try {
      // Check if category name already exists
      final existing = await _dbService.getCategoryByName(category.name);
      if (existing != null) {
        _errorMessage = 'Category "${category.name}" already exists';
        notifyListeners();
        throw Exception(_errorMessage);
      }

      await _dbService.insertCategory(category);
      await loadCategories();
      _errorMessage = '';
    } catch (e) {
      _errorMessage = 'Error adding category: $e';
      debugPrint(_errorMessage);
      rethrow;
    }
  }

  Future<void> updateCategory(Category category) async {
    try {
      await _dbService.updateCategory(category);
      await loadCategories();
      _errorMessage = '';
    } catch (e) {
      _errorMessage = 'Error updating category: $e';
      debugPrint(_errorMessage);
      rethrow;
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await _dbService.deleteCategory(id);
      await loadCategories();
      _errorMessage = '';
    } catch (e) {
      _errorMessage = 'Error deleting category: $e';
      debugPrint(_errorMessage);
      rethrow;
    }
  }

  Category? getCategoryById(String id) {
    try {
      return _categories.firstWhere((category) => category.id == id);
    } catch (e) {
      return null;
    }
  }

  String getCategoryName(String id) {
    final category = getCategoryById(id);
    return category?.name ?? 'Unknown';
  }
}
