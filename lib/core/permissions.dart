import 'enums.dart';

/// RBAC (§3) — luồng KHÔNG có tài xế:
/// - Chủ (owner): toàn quyền. Là người duy nhất đối soát giao hàng + thu tiền.
/// - Kiểm hàng (checker): kho/đóng hàng/in phiếu + bấm "Xuất phát" cho đơn.
/// - Kiểm kho (warehouse): chỉ thao tác kho + xem đơn.
class Perm {
  static bool owner(UserRole r) => r == UserRole.owner;

  // Chủ độc quyền.
  static bool createOrder(UserRole r) => r == UserRole.owner;
  static bool editCatalog(UserRole r) => r == UserRole.owner; // sản phẩm/giá
  static bool manageCustomers(UserRole r) => r == UserRole.owner;
  static bool viewReports(UserRole r) => r == UserRole.owner;
  static bool manageUsers(UserRole r) => r == UserRole.owner;
  static bool viewAudit(UserRole r) => r == UserRole.owner;
  static bool cancelOrder(UserRole r) => r == UserRole.owner;

  // Kho / đóng hàng / in phiếu — Chủ + Kiểm hàng + Kiểm kho.
  static bool warehouseOps(UserRole r) =>
      r == UserRole.owner ||
      r == UserRole.checker ||
      r == UserRole.warehouse;
  static bool printInvoice(UserRole r) =>
      r == UserRole.owner ||
      r == UserRole.checker ||
      r == UserRole.warehouse;

  /// Bấm "Xuất phát" — đơn đã đóng hàng → Đang giao. Chủ + Kiểm hàng.
  /// Kiểm kho soạn/đóng hàng thôi, không quyết định cho hàng đi.
  static bool startDelivery(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  /// Đối soát cuối ngày: đánh dấu giao thành công / không giao được.
  /// **Chỉ Chủ** — đây là bước chốt tiền.
  static bool confirmDelivery(UserRole r) => r == UserRole.owner;

  /// Thu tiền (COD lúc đối soát + thu công nợ). **Chỉ Chủ**.
  static bool collectPayment(UserRole r) => r == UserRole.owner;

  /// Tab hiện ở bottom nav theo vai trò.
  static List<String> tabs(UserRole r) => switch (r) {
        UserRole.owner => const [
            '/dashboard',
            '/orders',
            '/delivery',
            '/more'
          ],
        UserRole.checker => const [
            '/dashboard',
            '/orders',
            '/delivery',
            '/more'
          ],
        UserRole.warehouse => const ['/dashboard', '/orders', '/more'],
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
          p('/delivery') ||
          p('/warehouse') ||
          p('/more') ||
          p('/notifications') ||
          p('/filter');
    }
    // warehouse — kho + xem đơn
    return p('/dashboard') ||
        p('/orders') ||
        p('/warehouse') ||
        p('/more') ||
        p('/notifications') ||
        p('/filter');
  }
}
