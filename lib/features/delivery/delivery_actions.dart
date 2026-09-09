import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/error_text.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../services/sound_service.dart';
import '../../widgets/common.dart';
import '../orders/payment_sheet.dart';

/// Thao tác giao hàng dùng chung cho màn Giao hàng, màn Kho và chi tiết đơn —
/// một chỗ duy nhất để sửa khi nghiệp vụ đổi.
///
/// Luồng: kho đóng hàng xong → [departOrder] (Chủ/Kiểm hàng) → cuối ngày Chủ
/// [deliverOrder] (thu tiền) hoặc [failOrder].

AppUser _me(BuildContext context) => context.read<AuthProvider>().user!;

/// Cho **một đơn** xuất phát. Trả về true nếu đã đổi trạng thái.
Future<bool> departOrder(BuildContext context, Order o) async {
  final db = context.read<Db>();
  final me = _me(context);
  try {
    await db.departOrder(o, me.id, me.name);
    if (context.mounted) toast(context, 'Đơn ${o.code} đã xuất phát');
    return true;
  } catch (e) {
    debugPrint('DEPART-ORDER ERROR: $e');
    if (context.mounted) {
      toast(
        context,
        friendlyError(e, fallback: 'Không cho đơn xuất phát được. Thử lại.'),
      );
    }
    return false;
  }
}

/// Cho **tất cả** đơn đang chờ đi cùng lúc. Trả về số đơn đã xuất phát.
Future<int> departAllOrders(BuildContext context, List<Order> orders) async {
  if (orders.isEmpty) return 0;
  final db = context.read<Db>();
  final me = _me(context);
  final ok = await confirmDialog(
    context,
    title: 'Xuất phát tất cả',
    message:
        'Cho ${orders.length} đơn đã đóng hàng xuất phát? Tất cả sẽ chuyển '
        'sang "Đang giao".',
    confirm: 'Xuất phát',
  );
  if (!ok || !context.mounted) return 0;
  try {
    final n = await db.departOrders(orders, me.id, me.name);
    if (context.mounted) toast(context, '$n đơn đã xuất phát');
    return n;
  } catch (e) {
    debugPrint('DEPART-ALL ERROR: $e');
    if (context.mounted) {
      toast(
        context,
        friendlyError(e, fallback: 'Không cho đơn xuất phát được. Thử lại.'),
      );
    }
    return 0;
  }
}

/// Đối soát: giao thành công + thu tiền trong một bước.
/// [onDone] chạy sau khi ghi xong (chi tiết đơn dùng để pop về màn trước).
Future<bool> deliverOrder(
  BuildContext context,
  Order o, {
  VoidCallback? onDone,
}) async {
  final db = context.read<Db>();
  final me = _me(context);
  final result = await showPaymentSheet(context, o, allowDebt: true);
  if (result == null) return false;
  try {
    await db.markDelivered(
      order: o,
      collected: result.amount,
      method: result.method,
      actorId: me.id,
      actorName: me.name,
      note: result.note,
      markAsDebt: result.isDebt,
    );
  } catch (e) {
    debugPrint('DELIVER-ORDER ERROR: $e');
    if (context.mounted) {
      toast(
        context,
        friendlyError(e, fallback: 'Không ghi nhận được. Thử lại giúp tôi.'),
      );
    }
    return false;
  }
  SoundService.cash();
  if (context.mounted) {
    toast(context, 'Đã giao thành công ${o.code}');
    onDone?.call();
  }
  return true;
}

/// Đối soát: không giao được (thất bại / hẹn lại / hoàn hàng).
Future<bool> failOrder(BuildContext context, Order o) async {
  final db = context.read<Db>();
  final me = _me(context);
  final choice = await showModalBottomSheet<DeliveryStatus>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cancel, color: AppColors.danger),
            title: const Text('Giao thất bại'),
            onTap: () => Navigator.pop(ctx, DeliveryStatus.FAILED),
          ),
          ListTile(
            leading: const Icon(Icons.schedule, color: AppColors.warning),
            title: const Text('Hẹn giao lại'),
            subtitle: const Text('Đơn quay lại danh sách chờ xuất phát'),
            onTap: () => Navigator.pop(ctx, DeliveryStatus.RESCHEDULED),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_return),
            title: const Text('Hoàn hàng về kho'),
            onTap: () => Navigator.pop(ctx, DeliveryStatus.RETURNED),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final reason = await askReason(context, 'Lý do');
  if (reason == null || !context.mounted) return false;
  await db.markDeliveryFailed(
    order: o,
    status: choice,
    reason: reason,
    actorId: me.id,
    actorName: me.name,
  );
  if (context.mounted) toast(context, 'Đã cập nhật ${o.code}');
  return true;
}

/// Hỏi lý do (hủy đơn / giao không thành công).
Future<String?> askReason(BuildContext context, String title) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nhập lý do'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () => Navigator.pop(
            ctx,
            c.text.trim().isEmpty ? 'Không rõ' : c.text.trim(),
          ),
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  );
}
