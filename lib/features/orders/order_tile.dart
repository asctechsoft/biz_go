import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../widgets/common.dart';

/// Đơn còn phải xử lý — dùng cho tab "Chờ xử lý" ở màn Đơn hàng lẫn Tìm kiếm.
bool isOrderPending(Order o) =>
    o.orderStatus != OrderStatus.CANCELLED &&
    o.deliveryStatus != DeliveryStatus.DELIVERED &&
    o.deliveryStatus != DeliveryStatus.ON_THE_WAY;

/// Đơn đang trên đường giao.
bool isOrderDelivering(Order o) =>
    o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
    o.deliveryStatus == DeliveryStatus.ARRIVED;

/// Đơn đã giao xong.
bool isOrderDone(Order o) => o.deliveryStatus == DeliveryStatus.DELIVERED;

/// Thẻ đơn dùng chung giữa màn Đơn hàng và Tìm kiếm đơn.
///
/// `showMoney` gate tiền theo vai trò (`Perm.viewMoney`, xem CLAUDE.md) — mỗi
/// nơi dựng widget này phải tự truyền đúng giá trị, không suy ngầm bên trong.
class OrderTile extends StatelessWidget {
  final Order o;
  final bool showMoney;
  const OrderTile({super.key, required this.o, required this.showMoney});

  @override
  Widget build(BuildContext context) {
    // Chọn trạng thái nhiều thông tin nhất để hiện.
    final StatusUi ui;
    if (o.orderStatus == OrderStatus.CANCELLED) {
      ui = orderStatusUi(OrderStatus.CANCELLED);
    } else if (o.deliveryStatus != DeliveryStatus.WAITING_ASSIGNMENT) {
      ui = deliveryStatusUi(o.deliveryStatus);
    } else {
      ui = warehouseStatusUi(o.warehouseStatus);
    }
    final urgent = o.priority && o.orderStatus != OrderStatus.CANCELLED;
    return Card(
      margin: EdgeInsets.zero,
      // Viền đỏ mảnh bên trái để lướt mắt là thấy đơn gấp.
      shape: urgent
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.danger, width: 1.4),
            )
          : null,
      child: ListTile(
        onTap: () => context.push('/orders/${o.id}'),
        leading: Avatar(o.customerName),
        title: Row(
          children: [
            if (urgent) ...[
              const _UrgentBadge(),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                o.code,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o.customerName),
            // Ghi rõ "tạo" vì ngay dưới có thể là giờ xuất phát — hai mốc giờ
            // trần trụi cạnh nhau thì không biết cái nào là cái nào.
            Text(
              showMoney
                  ? '${money(o.total)} · tạo ${fmtTime(o.createdAt)}'
                  : 'Tạo lúc ${fmtTime(o.createdAt)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            // Giờ dự kiến xuất phát — chính là thứ quyết định thứ tự đơn
            // trong ngày, nên phải thấy ngay ở danh sách.
            if (o.plannedDepartAt != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'Xuất phát ${fmtDepartAt(o.plannedDepartAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: StatusChip(ui, dense: true),
        isThreeLine: true,
      ),
    );
  }
}

/// Nhãn "GẤP" đỏ trên thẻ đơn ưu tiên.
class _UrgentBadge extends StatelessWidget {
  const _UrgentBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'GẤP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
        ),
      );
}
