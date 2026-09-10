import 'enums.dart';

/// RBAC (§3) — luồng KHÔNG có tài xế:
/// - Chủ (owner): toàn quyền. Là người duy nhất đối soát giao hàng + thu tiền.
/// - Kiểm hàng (checker): kho/đóng hàng/in phiếu + bấm "Xuất phát" cho đơn.
/// - Sale: CHỈ tạo đơn (kể cả "Đặt lại đơn"). Không sửa/xóa/hủy đơn, không
///   thao tác kho, không xem tiền — vai trò cũ "Kiểm kho" (warehouse) đã đổi
///   quyền thành cái này, kho giờ gộp hẳn vào việc của Kiểm hàng.
class Perm {
  static bool owner(UserRole r) => r == UserRole.owner;

  /// Chủ tạo đơn đầy đủ (sửa giá, đặt cọc, trạng thái thanh toán...). Sale
  /// cũng tạo được — nhưng KHÔNG có [editOrder]/[deleteOrder]/[cancelOrder]
  /// nên đơn tạo xong là xong, đụng gì tiếp phải nhờ Chủ.
  static bool createOrder(UserRole r) =>
      r == UserRole.owner || r == UserRole.sale;

  /// Sửa đơn đã tạo (thêm/bớt hàng, đổi giá, phí). Chỉ Chủ — đụng vào tiền.
  static bool editOrder(UserRole r) => r == UserRole.owner;

  /// Xoá hẳn đơn tạo nhầm. Chỉ Chủ. Điều kiện đơn còn xoá được: `Db.canDelete`.
  static bool deleteOrder(UserRole r) => r == UserRole.owner;
  static bool editCatalog(UserRole r) => r == UserRole.owner; // sản phẩm/giá

  /// Sửa Cài đặt phiếu (tiêu đề/SĐT in trên phiếu + mặc định ẩn giá). Chủ +
  /// Kiểm hàng. Kiểm hàng có [viewMoney] nên chỉnh được cả toggle giá.
  static bool editInvoiceSettings(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;
  static bool manageCustomers(UserRole r) => r == UserRole.owner;

  /// Danh mục nhà xe (Cài đặt › Nhà xe). Chỉ Chủ — cùng nhóm với danh mục
  /// khách hàng / sản phẩm.
  static bool manageCarriers(UserRole r) => r == UserRole.owner;
  // Báo cáo doanh thu — Chủ + Kiểm hàng (kiêm kế toán). Chỉ đọc số liệu.
  static bool viewReports(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  /// Màn **Tổng quan** — doanh thu, biểu đồ, công nợ. Chủ + Kiểm hàng
  /// (kiêm kế toán, cần theo dõi số liệu). Kiểm kho không thấy.
  static bool viewDashboard(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;
  static bool manageUsers(UserRole r) => r == UserRole.owner;
  static bool viewAudit(UserRole r) => r == UserRole.owner;
  static bool cancelOrder(UserRole r) => r == UserRole.owner;

  // Kho / đóng hàng — Chủ + Kiểm hàng. Sale không còn thao tác kho (đã đổi
  // từ Kiểm kho sang chỉ tạo đơn).
  static bool warehouseOps(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  // In phiếu — Chủ + Kiểm hàng + Sale (Sale tạo đơn xong vẫn cần in/chia sẻ
  // phiếu cho khách, `viewMoney` vẫn ẩn giá với Sale như cũ).
  static bool printInvoice(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker || r == UserRole.sale;

  /// Bấm "Xuất phát" — đơn đã đóng hàng → Đang giao. Chủ + Kiểm hàng.
  /// Sale chỉ tạo đơn, không quyết định cho hàng đi.
  static bool startDelivery(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  /// Đối soát cuối ngày: đánh dấu giao thành công / không giao được.
  /// **Chỉ Chủ** — đây là bước chốt tiền.
  static bool confirmDelivery(UserRole r) => r == UserRole.owner;

  /// Thu tiền (COD lúc đối soát + thu công nợ). **Chỉ Chủ**.
  static bool collectPayment(UserRole r) => r == UserRole.owner;

  /// Được nhìn thấy **mọi con số tiền**: đơn giá, thành tiền, tổng cộng, đã
  /// thu, còn thiếu — trong app lẫn trên phiếu in. Chủ + Kiểm hàng (kiêm
  /// kế toán). Chỉ **Sale** bị ẩn tiền — họ chỉ cần mặt hàng + số lượng.
  ///
  /// Gate này áp ở TỪNG chỗ hiện tiền — danh sách đơn, chi tiết đơn, màn
  /// giao hàng, phiếu xem trước và PDF — chứ không có một chỗ chặn chung nào.
  /// XEM tiền ≠ THU tiền: [collectPayment]/[confirmDelivery] vẫn chỉ Chủ.
  static bool viewMoney(UserRole r) =>
      r == UserRole.owner || r == UserRole.checker;

  /// Tab hiện ở bottom nav theo vai trò.
  ///
  /// `/dashboard` có ở Chủ + Kiểm hàng — [home] lấy tab đầu tiên, nên hai vai
  /// trò này vào thẳng Tổng quan. Sale không có, vào thẳng màn Đơn hàng (bấm
  /// nút "+" ở đó để tạo đơn — [createOrder] gate cái nút, không phải tab).
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
        UserRole.sale => const ['/orders', '/more'],
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
          p('/invoice-settings') ||
          p('/notifications') ||
          p('/filter');
    }
    // sale — chỉ tạo đơn + xem đơn, KHÔNG có kho
    return p('/orders') ||
        p('/more') ||
        p('/notifications') ||
        p('/filter');
  }
}
