import 'enums.dart';

/// 3 tài khoản demo cố định. Dùng chung cho seed + auto-provision khi login.
class DemoAccounts {
  static const password = '123456';

  static const list = <(String phone, String name, UserRole role)>[
    ('0900000000', 'Chủ Demo', UserRole.owner),
    ('0900000001', 'Kiểm Hàng Demo', UserRole.checker),
    ('0900000002', 'Giao Hàng Demo', UserRole.shipper),
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
