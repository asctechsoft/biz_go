import 'enums.dart';

/// RBAC 3 vai trò (§3). Chủ toàn quyền; Kiểm hàng lo kho/đóng/in;
/// Giao hàng lo chuyến/giao/thu COD.
class Perm {
  static bool owner(UserRole r) => r == UserRole.owner;

  // Chủ độc quyền.
  static bool createOrder(UserRole r) => r == UserRole.owner;
  static bool editCatalog(UserRole r) => r == UserRole.owner; // sản phẩm/giá
  static bool manageCustomers(UserRole r) => r == UserRole.owner;
  static bool viewReports(UserRole r) => r == UserRole.owner;
  static bool manageFleet(UserRole r) => r == UserRole.owner;
  static bool manageUsers(UserRole r) => r == UserRole.owner;
  static bool viewAudit(UserRole r) => r == UserRole.owner;
  static bool cancelOrder(UserRole r) => r == UserRole.owner;

  // Kiểm hàng (+ chủ).
  static bool warehouseOps(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;
  static bool printInvoice(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  // Giao hàng (+ chủ).
  static bool dispatchOps(UserRole r) =>
      r == UserRole.owner || r == UserRole.shipper; // tạo/xếp chuyến
  static bool deliveryOps(UserRole r) =>
      r == UserRole.owner || r == UserRole.shipper;
  static bool collectPayment(UserRole r) =>
      r == UserRole.owner || r == UserRole.shipper;

  /// Tab hiện ở bottom nav theo vai trò.
  static List<String> tabs(UserRole r) => switch (r) {
        UserRole.owner => const [
            '/dashboard',
            '/orders',
            '/delivery',
            '/more'
          ],
        UserRole.checker => const ['/dashboard', '/orders', '/more'],
        UserRole.shipper => const ['/delivery', '/more'],
      };

  /// Route đầu tiên hợp lệ — dùng khi redirect sau đăng nhập.
  static String home(UserRole r) => tabs(r).first;

  /// Vai trò có được mở route [loc] không (khớp tiền tố).
  static bool canRoute(UserRole r, String loc) {
    if (r == UserRole.owner) return true;
    bool p(String x) => loc == x || loc.startsWith('$x/');
    if (r == UserRole.checker) {
      return p('/dashboard') ||
          p('/orders') ||
          p('/warehouse') ||
          p('/more') ||
          p('/notifications') ||
          p('/filter');
    }
    // shipper
    return p('/delivery') ||
        p('/trips') ||
        p('/orders') ||
        p('/more') ||
        p('/notifications');
  }
}
