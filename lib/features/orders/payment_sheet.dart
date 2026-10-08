import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class PaymentResult {
  /// Phần thu cho CHÍNH đơn này.
  final int amount;

  /// Phần thu thêm cho công nợ cũ của khách (đơn khác) — 0 nếu không có.
  /// Người gọi phải ghi riêng bằng `Db.collectCustomerDebt` SAU khi ghi xong
  /// phần [amount], vì đó là các payment của đơn khác.
  final int debtAmount;
  final PaymentMethod method;
  final String note;

  /// Khách hẹn trả sau (không thu gì lúc giao) — chỉ `showPaymentSheet` gọi
  /// với `allowDebt: true` mới trả về `true` được. [amount] luôn 0 khi cờ
  /// này bật, [method] không có ý nghĩa (không sinh payment nào).
  final bool isDebt;
  PaymentResult(this.amount, this.method, this.note,
      {this.isDebt = false, this.debtAmount = 0});
}

/// Ô chọn **hình thức thu tiền** — bấm vào mở bottom sheet chọn.
///
/// KHÔNG dùng `DropdownButtonFormField`: ô này luôn nằm trong một bottom sheet
/// (sheet Thanh toán, sheet Thu công nợ), mà dropdown trong sheet hay bung
/// ngược lên / đè lên nội dung (xem CLAUDE.md › Gotchas). Dùng chung ở mọi chỗ
/// cho chọn hình thức để 3 lựa chọn không bị lệch nhau giữa các màn.
class PaymentMethodField extends StatelessWidget {
  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;
  final String label;
  const PaymentMethodField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Hình thức thu',
  });

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await pickPaymentMethod(context, value);
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
}

/// Bottom sheet chọn hình thức thu. Chỉ hiện [paymentMethodOptions] — "Ví điện
/// tử" là legacy nên không cho chọn mới nữa.
Future<PaymentMethod?> pickPaymentMethod(
  BuildContext context,
  PaymentMethod current,
) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader('Hình thức thu'),
          for (final m in paymentMethodOptions)
            ListTile(
              title: Text(m.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: current == m
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, m),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Mockup 6.5 — Thanh toán / thu tiền.
///
/// [allowDebt] true → thêm nút "Nợ chưa trả": giao hàng xong nhưng khách hẹn
/// trả sau, không thu đồng nào lúc này. Chỉ màn **Giao thành công** truyền cờ
/// này ([deliverOrder]) — nút "Thu tiền" độc lập (thu công nợ còn lại) không
/// cần vì không thu gì thì đóng sheet là xong, không có trạng thái mới nào để
/// ghi nhận.
Future<PaymentResult?> showPaymentSheet(
  BuildContext context,
  Order order, {
  bool allowDebt = false,
}) async {
  final remaining = order.remaining > 0 ? order.remaining : 0;

  // Công nợ cũ của khách (ngoài đơn này) — chỉ Chủ thấy, cùng quyền với dialog
  // "Khách đang nợ". `customers.debt` đã gồm phần còn thiếu của đơn này nên
  // phải trừ ra. Đọc lỗi/khách đã xoá → coi như không có nợ cũ.
  var oldDebt = 0;
  final role = context.read<AuthProvider>().user?.role;
  if (role != null &&
      Perm.manageCustomers(role) &&
      order.orderStatus != OrderStatus.CANCELLED) {
    try {
      final c = await context.read<Db>().customer(order.customerId).first;
      oldDebt = c.debt - remaining > 0 ? c.debt - remaining : 0;
    } catch (_) {}
  }
  if (!context.mounted) return null;

  final amountC =
      TextEditingController(text: moneyPlain(remaining + oldDebt));
  final noteC = TextEditingController();
  PaymentMethod method = PaymentMethod.cash;

  return showModalBottomSheet<PaymentResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final collected = int.tryParse(
                amountC.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
            0;
        // Thu vào đơn này trước, dư mới chuyển sang nợ cũ.
        var orderPart = collected;
        var debtPart = 0;
        if (oldDebt > 0) {
          orderPart = collected < remaining ? collected : remaining;
          debtPart = collected - orderPart;
          if (debtPart > oldDebt) {
            orderPart += debtPart - oldDebt;
            debtPart = oldDebt;
          }
        }
        final afterRemaining = remaining + oldDebt - collected;
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text('Thanh toán',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 16),
                KVRow('Tổng tiền', money(order.total)),
                KVRow('Đã trả trước', money(order.prepaid)),
                KVRow('Đã thu', money(order.paidAmount)),
                KVRow(oldDebt > 0 ? 'Cần thu đơn này (COD)' : 'Cần thu (COD)',
                    money(remaining),
                    valueColor: AppColors.danger, bold: true),
                if (oldDebt > 0) ...[
                  KVRow('Công nợ cũ', money(oldDebt)),
                  KVRow('Tổng cần thu', money(remaining + oldDebt),
                      valueColor: AppColors.danger, bold: true),
                ],
                const Divider(),
                const SizedBox(height: 4),
                TextField(
                  controller: amountC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Tiền thực thu', suffixText: 'đ'),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 12),
                PaymentMethodField(
                  value: method,
                  onChanged: (m) => setSheet(() => method = m),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                ),
                const SizedBox(height: 12),
                if (oldDebt > 0) ...[
                  KVRow('Thu cho đơn này', money(orderPart)),
                  KVRow('Thu công nợ cũ', money(debtPart)),
                ],
                KVRow(
                  afterRemaining > 0 ? 'Còn thiếu' : 'Trạng thái',
                  afterRemaining > 0 ? money(afterRemaining) : 'Đủ tiền',
                  valueColor:
                      afterRemaining > 0 ? AppColors.danger : AppColors.success,
                  bold: true,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    PaymentResult(orderPart, method, noteC.text.trim(),
                        debtAmount: debtPart),
                  ),
                  child: const Text('Xác nhận'),
                ),
                if (allowDebt && remaining > 0) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    onPressed: () async {
                      // Ghi nợ là bấm 1 lần xong, không sửa lại được như số
                      // tiền — hỏi lại để khỏi lỡ tay bỏ qua cả khoản cần thu.
                      final ok = await confirmDialog(
                        ctx,
                        title: 'Giao hàng, khách hẹn trả sau?',
                        message:
                            'Đơn chuyển sang "Giao thành công" nhưng KHÔNG thu '
                            'đồng nào lúc này — ${money(remaining)} còn lại ghi '
                            'vào công nợ của khách, thu sau bằng nút "Thu tiền" '
                            'ở chi tiết đơn.',
                        confirm: 'Xác nhận nợ',
                      );
                      if (ok && ctx.mounted) {
                        Navigator.pop(
                          ctx,
                          PaymentResult(0, method, noteC.text.trim(),
                              isDebt: true),
                        );
                      }
                    },
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Nợ chưa trả'),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}
