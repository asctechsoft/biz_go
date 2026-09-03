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

/// Mockup 6.5 — Thanh toán / thu tiền.
Future<PaymentResult?> showPaymentSheet(BuildContext context, Order order) {
  final remaining = order.remaining > 0 ? order.remaining : 0;
  final amountC = TextEditingController(text: '$remaining');
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
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
                  decoration: const InputDecoration(
                      labelText: 'Tiền thực thu', suffixText: 'đ'),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Hình thức thu'),
                  items: [
                    for (final m in PaymentMethod.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setSheet(() => method = m!),
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
