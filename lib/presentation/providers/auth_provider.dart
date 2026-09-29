import 'package:flutter/material.dart';

import '../../core/utils/password_hasher.dart';
import '../../data/database/database_service.dart';
import '../../data/models/user.dart';
import '../../data/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();

  User? get currentUser => _authService.currentUser;
  bool get isLoggedIn => _authService.isLoggedIn;
  bool get isAdmin => _authService.isAdmin();
  bool get isCashier => _authService.isCashier();

  Future<bool> login(String username, String password) async {
    try {
      final user = await _dbService.getUserByUsername(username.trim());

      if (user != null &&
          user.isActive &&
          PasswordHasher.verify(password, user.password)) {
        await _authService.setCurrentUser(user);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }

  Future<List<User>> getAllUsers() async => _dbService.getAllUsers();

  Future<bool> createUser({
    required String username,
    required String password,
    required UserRole role,
    required String fullName,
  }) async {
    try {
      final existing = await _dbService.getUserByUsername(username.trim());
      if (existing != null) {
        return false;
      }
      final user = User(
        username: username.trim(),
        password: PasswordHasher.hash(password),
        role: role,
        fullName: fullName,
      );
      await _dbService.insertUser(user);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateUser({
    required String id,
    String? username,
    String? newPassword,
    UserRole? role,
    String? fullName,
    bool? isActive,
  }) async {
    try {
      final existing = await _dbService.getUserById(id);
      if (existing == null) {
        return false;
      }
      final updated = existing.copyWith(
        username: username,
        password: newPassword == null || newPassword.isEmpty
            ? existing.password
            : PasswordHasher.hash(newPassword),
        role: role,
        fullName: fullName,
        isActive: isActive,
      );
      await _dbService.updateUser(updated);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteUser(String id) async {
    try {
      final users = await _dbService.getAllUsers();
      final user = users.where((u) => u.id == id).firstOrNull;
      // Never allow deleting the last remaining admin.
      if (user != null && user.role == UserRole.admin) {
        final adminCount =
            users.where((u) => u.role == UserRole.admin).length;
        if (adminCount <= 1) {
          return false;
        }
      }
      await _dbService.deleteUser(id);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }
}

