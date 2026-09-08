import 'package:flutter/material.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../widgets/common.dart';

class PaymentResult {
  final int amount;
  final PaymentMethod method;
  final String note;
  PaymentResult(this.amount, this.method, this.note);
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
Future<PaymentResult?> showPaymentSheet(BuildContext context, Order order) {
  final remaining = order.remaining > 0 ? order.remaining : 0;
  final amountC = TextEditingController(text: moneyPlain(remaining));
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
        final afterRemaining = order.total - order.paidAmount - collected;
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
                KVRow('Cần thu (COD)', money(remaining),
                    valueColor: AppColors.danger, bold: true),
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
                    PaymentResult(collected, method, noteC.text.trim()),
                  ),
                  child: const Text('Xác nhận'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}
