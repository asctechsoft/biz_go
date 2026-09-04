import 'enums.dart';

/// 3 tài khoản demo cố định. Dùng chung cho seed + auto-provision khi login.
class DemoAccounts {
  static const password = '123456';

  // Chỉ có tài khoản Chủ ban đầu. Các vai trò khác do Chủ tạo qua
  // "Quản lý người dùng" sau khi đăng nhập.
  static const list = <(String phone, String name, UserRole role)>[
    ('0900000000', 'Admin', UserRole.owner),
  ];

  /// Tìm tài khoản demo theo số điện thoại (bỏ ký tự không phải số).
  static (String, String, UserRole)? find(String phone) {
    final p = phone.replaceAll(RegExp(r'[^0-9]'), '');
    for (final a in list) {
      if (a.$1 == p) return a;
    }
    return null;
  }
}
