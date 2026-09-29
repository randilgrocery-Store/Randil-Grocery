import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class AuthService {

  factory AuthService() => _instance;

  AuthService._internal();
  static final AuthService _instance = AuthService._internal();
  User? _currentUser;

  User? get currentUser => _currentUser;

  bool get isLoggedIn => _currentUser != null;

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');
  }

  Future<void> setCurrentUser(User? user) async {
    _currentUser = user;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user', user.username);
    }
  }

  /// Check if user has admin role
  bool isAdmin() => _currentUser?.role == UserRole.admin;

  /// Check if user has cashier role
  bool isCashier() => _currentUser?.role == UserRole.cashier;
}
