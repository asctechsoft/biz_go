import '../core/enums.dart';

class AppUser {
  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final bool active;

  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.active = true,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
        role: roleFromName(m['role']),
        active: m['active'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'role': role.name,
        'active': active,
      };
}
