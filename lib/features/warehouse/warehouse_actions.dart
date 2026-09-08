import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_text.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Thao tác kho dùng chung cho màn Kho và chi tiết đơn — một chỗ duy nhất để
/// sửa khi nghiệp vụ đổi (giống `delivery_actions.dart`).
///
/// Kho chỉ còn ĐÚNG MỘT bước: đơn tạo xong → [packOrder] → chờ xuất phát.
/// Không hỏi mã kiện, không hỏi khối lượng: bấm một cái là xong.

/// Đóng hàng cho **một đơn**. Trả về true nếu đã đổi trạng thái.
Future<bool> packOrder(BuildContext context, Order o) async {
  final db = context.read<Db>();
  final me = context.read<AuthProvider>().user!;
  try {
    await db.markPacked(o, me.id, me.name);
    if (context.mounted) toast(context, 'Đã đóng hàng, chờ xuất phát');
    return true;
  } catch (e) {
    debugPrint('PACK-ORDER ERROR: $e');
    if (context.mounted) {
      toast(context, friendlyError(e, fallback: 'Không đóng hàng được.'));
    }
    return false;
  }
}
