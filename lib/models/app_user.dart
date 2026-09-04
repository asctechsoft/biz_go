import '../core/enums.dart';

class AppUser {
  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final bool active;

  /// Bắt buộc đổi SĐT đăng nhập + mật khẩu trước khi dùng app.
  /// Bật cho tài khoản Chủ được tạo tự động lần đầu (bootstrap demo).
  /// KHÔNG nằm trong [toMap] — cờ này chỉ được ghi/xoá ở chỗ cố ý, để các
  /// lệnh `set(..., merge: true)` khác không vô tình reset nó.
  final bool mustChangeCredentials;

  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.active = true,
    this.mustChangeCredentials = false,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
        role: roleFromName(m['role']),
        active: m['active'] ?? true,
        mustChangeCredentials: m['mustChangeCredentials'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'role': role.name,
        'active': active,
      };
}
