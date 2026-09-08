import 'package:flutter/material.dart';
import 'theme.dart';

/// All status sets from spec §18. Stored in Firestore as the enum `name`.

/// 3 vai trò (§3 rút gọn theo mô hình vận hành thực tế).
///
/// KHÔNG còn vai trò `shipper` (Giao hàng): khách không có công đoạn tài xế
/// nhận chuyến. Kho đóng hàng xong bấm "Xuất phát", cuối ngày Chủ đối soát
/// đơn nào giao thành công + thu tiền.
enum UserRole {
  owner, // Chủ — toàn quyền: tạo đơn, giá, khách, báo cáo, đối soát giao hàng
  checker, // Kiểm hàng — chuẩn bị, đóng hàng, in phiếu, cho đơn xuất phát
  warehouse, // Kiểm kho — thao tác kho, xem đơn
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.owner => 'Chủ',
    UserRole.checker => 'Kiểm hàng',
    UserRole.warehouse => 'Kiểm kho',
  };
}

/// Hồ sơ cũ còn `role: 'shipper'` (vai trò đã bỏ) rơi về [UserRole.warehouse]
/// — quyền thấp nhất, đúng nguyên tắc fallback an toàn.
UserRole roleFromName(String? n) => UserRole.values.firstWhere(
  (e) => e.name == n,
  orElse: () => UserRole.warehouse,
);

// §18.1 Order Status
enum OrderStatus { NEW, CONFIRMED, PROCESSING, COMPLETED, CANCELLED }

// §18.2 Warehouse Status
//
// Luồng kho hiện tại chỉ dùng: WAITING (đơn vừa tạo, chờ đóng hàng) → PACKED
// (bấm "Đóng hàng" là xong, không cấp mã kiện, không nhập khối lượng).
// PREPARING · PREPARED · PACKING là **legacy** của luồng "chuẩn bị hàng" đã bỏ
// — giữ lại để đơn cũ trong Firestore vẫn đọc/hiển thị đúng, KHÔNG ghi mới.
enum WarehouseStatus { WAITING, PREPARING, PREPARED, PACKING, PACKED }

// §18.3 Delivery Status
//
// Luồng hiện tại chỉ dùng: WAITING_ASSIGNMENT (đóng hàng xong, chờ xuất phát)
// → ON_THE_WAY (đã xuất phát) → DELIVERED / FAILED / RESCHEDULED / RETURNED.
// ASSIGNED · LOADING · ARRIVED là **legacy** của luồng chuyến xe + tài xế đã
// bỏ — giữ lại để đơn cũ trong Firestore vẫn đọc/hiển thị đúng, KHÔNG ghi mới.
enum DeliveryStatus {
  WAITING_ASSIGNMENT,
  ASSIGNED,
  LOADING,
  ON_THE_WAY,
  ARRIVED,
  DELIVERED,
  FAILED,
  RESCHEDULED,
  RETURNED,
}

/// Trạng thái giao hàng còn dùng — đổ vào ô lọc để người dùng không phải chọn
/// giữa mấy trạng thái chết của luồng chuyến xe cũ.
const deliveryStatusFilterValues = [
  DeliveryStatus.WAITING_ASSIGNMENT,
  DeliveryStatus.ON_THE_WAY,
  DeliveryStatus.DELIVERED,
  DeliveryStatus.FAILED,
  DeliveryStatus.RESCHEDULED,
  DeliveryStatus.RETURNED,
];

// §18.4 Payment Status
// CARRIER = nhà xe thu hộ rồi chuyển tiền lại. Về nghiệp vụ giống COD (chưa
// thu, thu lúc giao) nhưng người thu là nhà xe — `Db` đối xử y như COD/DEBT:
// người tạo đơn tự chốt, không tự suy lại.
enum PaymentStatus { UNPAID, PARTIAL, PAID, REFUNDED, COD, DEBT, CARRIER }

/// Hình thức thu tiền.
///
/// `ewallet` (Ví điện tử) là **legacy** — đã bỏ khỏi UI, chỉ giữ lại để đọc
/// đúng các doc `payments` cũ trong Firestore (xoá khỏi enum là payment cũ rơi
/// về "Tiền mặt", sai lịch sử thu tiền). Danh sách cho người dùng chọn là
/// [paymentMethodOptions], KHÔNG phải `PaymentMethod.values`.
enum PaymentMethod { cash, transfer, carrier, ewallet }

/// Các hình thức còn dùng — dùng cái này ở mọi chỗ cho chọn hình thức thu.
const paymentMethodOptions = [
  PaymentMethod.cash,
  PaymentMethod.transfer,
  PaymentMethod.carrier,
];

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
    PaymentMethod.cash => 'Tiền mặt',
    PaymentMethod.transfer => 'Chuyển khoản',
    // Nhà xe thu hộ rồi chuyển lại — hàng gửi qua nhà xe thì tiền cũng về
    // theo đường đó, xem `order.deliveryCarrierName`.
    PaymentMethod.carrier => 'Thu qua nhà xe',
    PaymentMethod.ewallet => 'Ví điện tử', // legacy
  };
}

/// Vietnamese labels + colors used across the UI.
class StatusUi {
  final String label;
  final Color color;
  const StatusUi(this.label, this.color);
}

StatusUi orderStatusUi(OrderStatus s) => switch (s) {
  OrderStatus.NEW => const StatusUi('Đơn mới', AppColors.info),
  OrderStatus.CONFIRMED => const StatusUi('Đã xác nhận', AppColors.info),
  OrderStatus.PROCESSING => const StatusUi('Đang xử lý', AppColors.warning),
  OrderStatus.COMPLETED => const StatusUi('Hoàn thành', AppColors.success),
  OrderStatus.CANCELLED => const StatusUi('Đã hủy', AppColors.danger),
};

StatusUi warehouseStatusUi(WarehouseStatus s) => switch (s) {
  WarehouseStatus.WAITING => const StatusUi('Chờ đóng hàng', AppColors.info),
  // 3 nhãn dưới đây chỉ còn gặp ở đơn cũ (luồng "chuẩn bị hàng" đã bỏ).
  WarehouseStatus.PREPARING => const StatusUi(
    'Đang chuẩn bị',
    AppColors.warning,
  ),
  WarehouseStatus.PREPARED => const StatusUi('Đã chuẩn bị', AppColors.success),
  WarehouseStatus.PACKING => const StatusUi(
    'Đang đóng hàng',
    AppColors.warning,
  ),
  WarehouseStatus.PACKED => const StatusUi('Đã đóng hàng', AppColors.success),
};

StatusUi deliveryStatusUi(DeliveryStatus s) => switch (s) {
  DeliveryStatus.WAITING_ASSIGNMENT => const StatusUi(
    'Chờ xuất phát',
    AppColors.textSecondary,
  ),
  // legacy — luồng chuyến xe cũ
  DeliveryStatus.ASSIGNED => const StatusUi('Chờ xuất phát', AppColors.info),
  DeliveryStatus.LOADING => const StatusUi('Đang lên xe', AppColors.warning),
  DeliveryStatus.ON_THE_WAY => const StatusUi('Đang giao', AppColors.info),
  DeliveryStatus.ARRIVED => const StatusUi('Đã tới', AppColors.warning),
  DeliveryStatus.DELIVERED => const StatusUi(
    'Giao thành công',
    AppColors.success,
  ),
  DeliveryStatus.FAILED => const StatusUi('Giao thất bại', AppColors.danger),
  DeliveryStatus.RESCHEDULED => const StatusUi('Hẹn lại', AppColors.warning),
  DeliveryStatus.RETURNED => const StatusUi('Hoàn hàng', AppColors.danger),
};

StatusUi paymentStatusUi(PaymentStatus s) => switch (s) {
  PaymentStatus.UNPAID => const StatusUi('Chưa thanh toán', AppColors.danger),
  PaymentStatus.PARTIAL => const StatusUi(
    'Thanh toán 1 phần',
    AppColors.warning,
  ),
  PaymentStatus.PAID => const StatusUi('Đã thanh toán', AppColors.success),
  PaymentStatus.REFUNDED => const StatusUi(
    'Đã hoàn tiền',
    AppColors.textSecondary,
  ),
  PaymentStatus.COD => const StatusUi('Thu khi giao', AppColors.info),
  PaymentStatus.DEBT => const StatusUi('Công nợ', AppColors.danger),
  PaymentStatus.CARRIER => const StatusUi('Thu qua nhà xe', AppColors.info),
};

T enumFromName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);
