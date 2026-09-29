import 'package:uuid/uuid.dart';

enum UserRole { admin, cashier }

class User {

  User({
    required this.username, required this.password, required this.role, required this.fullName, String? id,
    DateTime? createdAt,
    this.isActive = true,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory User.fromMap(Map<String, dynamic> map) => User(
      id: map['id'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      role: UserRole.values
          .firstWhere((e) => e.name == (map['role'] as String)),
      fullName: map['fullName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isActive: (map['isActive'] as int) == 1,
    );
  final String id;
  final String username;
  final String password;
  final UserRole role;
  final String fullName;
  final DateTime createdAt;
  final bool isActive;

  User copyWith({
    String? username,
    String? password,
    UserRole? role,
    String? fullName,
    bool? isActive,
  }) => User(
      id: id,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
    );

  Map<String, dynamic> toMap() => {
      'id': id,
      'username': username,
      'password': password,
      'role': role.name,
      'fullName': fullName,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive ? 1 : 0,
    };

  @override
  String toString() => 'User(id: $id, username: $username, fullName: $fullName)';
}
