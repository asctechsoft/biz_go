import 'package:flutter/material.dart' show DateTimeRange;

import '../core/enums.dart';
import 'order.dart';

/// Điều kiện lọc đơn của màn "Lọc nhanh".
///
/// `null` ở mỗi trường = "Tất cả" (không lọc theo tiêu chí đó).
class OrderFilter {
  /// Số ngày gần nhất. `null` khi dùng [custom].
  final int? days;

  /// Khoảng ngày tự chọn. `null` khi dùng [days].
  final DateTimeRange? custom;

  final OrderStatus? orderStatus;
  final DeliveryStatus? deliveryStatus;
  final PaymentStatus? paymentStatus;

  /// uid nhân viên. Khớp nếu người đó **có mặt trong timeline** của đơn —
  /// tạo đơn, đóng hàng, giao hàng, thu tiền... Đơn không lưu "nhân viên phụ
  /// trách" nên timeline là nguồn duy nhất biết ai đã đụng vào đơn.
  final String? staffId;
  final String staffName;

  const OrderFilter({
    this.days,
    this.custom,
    this.orderStatus,
    this.deliveryStatus,
    this.paymentStatus,
    this.staffId,
    this.staffName = '',
  });

  static const empty = OrderFilter();

  /// Có tiêu chí nào đang bật không (bỏ qua khoảng thời gian mặc định).
  bool get isActive =>
      custom != null ||
      orderStatus != null ||
      deliveryStatus != null ||
      paymentStatus != null ||
      staffId != null;

  /// Số tiêu chí đang bật — hiện lên thanh báo ở màn Đơn hàng.
  int get count => [
        custom,
        orderStatus,
        deliveryStatus,
        paymentStatus,
        staffId,
      ].where((e) => e != null).length;

  /// Khoảng thời gian thực tế đang lọc.
  DateTimeRange get range {
    if (custom != null) return custom!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: today.subtract(Duration(days: (days ?? 30) - 1)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  /// Cần tải bao nhiêu ngày dữ liệu để phủ hết khoảng lọc — màn Đơn hàng dùng
  /// để nới `Db.orders(days:)`, kẻo lọc khoảng cũ mà dữ liệu chưa tải về.
  int get daysNeeded {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    return today.difference(start).inDays + 1;
  }

  bool matches(Order o) {
    final r = range;
    if (o.createdAt.isBefore(r.start) || o.createdAt.isAfter(r.end)) {
      return false;
    }
    if (orderStatus != null && o.orderStatus != orderStatus) return false;
    if (deliveryStatus != null && o.deliveryStatus != deliveryStatus) {
      return false;
    }
    if (paymentStatus != null && o.paymentStatus != paymentStatus) return false;
    if (staffId != null &&
        !o.timeline.any((e) => e.actorId == staffId)) {
      return false;
    }
    return true;
  }

  OrderFilter copyWith({
    int? days,
    DateTimeRange? custom,
    OrderStatus? orderStatus,
    DeliveryStatus? deliveryStatus,
    PaymentStatus? paymentStatus,
    String? staffId,
    String? staffName,
    bool clearCustom = false,
    bool clearOrderStatus = false,
    bool clearDeliveryStatus = false,
    bool clearPaymentStatus = false,
    bool clearStaff = false,
  }) =>
      OrderFilter(
        days: days ?? this.days,
        custom: clearCustom ? null : (custom ?? this.custom),
        orderStatus:
            clearOrderStatus ? null : (orderStatus ?? this.orderStatus),
        deliveryStatus: clearDeliveryStatus
            ? null
            : (deliveryStatus ?? this.deliveryStatus),
        paymentStatus:
            clearPaymentStatus ? null : (paymentStatus ?? this.paymentStatus),
        staffId: clearStaff ? null : (staffId ?? this.staffId),
        staffName: clearStaff ? '' : (staffName ?? this.staffName),
      );
}
