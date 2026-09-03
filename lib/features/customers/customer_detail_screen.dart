import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import 'customer_edit_screen.dart';

class CustomerDetailScreen extends StatelessWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<Customer>(
      stream: db.customer(customerId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final c = snap.data!;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CustomerEditScreen(customer: c)),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Container(
                  color: AppColors.primary,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Avatar(c.name, size: 52),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          Text(c.phone,
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      KVRow('Công nợ hiện tại', money(c.debt),
                          valueColor: c.debt > 0
                              ? AppColors.danger
                              : AppColors.success,
                          bold: true),
                      KVRow('Tổng mua hàng', money(c.totalPurchased),
                          valueColor: AppColors.primary, bold: true),
                      KVRow('Tổng đã thanh toán', money(c.totalPaid),
                          valueColor: AppColors.success, bold: true),
                    ],
                  ),
                ),
                const TabBar(
                  labelColor: AppColors.primary,
                  indicatorColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  tabs: [
                    Tab(text: 'Đơn hàng'),
                    Tab(text: 'Công nợ'),
                    Tab(text: 'Thông tin'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OrdersTab(customerId: customerId),
                      _DebtTab(customerId: customerId, customerName: c.name),
                      _InfoTab(customer: c),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/orders/create', extra: c),
                icon: const Icon(Icons.add),
                label: const Text('Tạo đơn'),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrdersTab extends StatelessWidget {
  final String customerId;
  const _OrdersTab({required this.customerId});
  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<List<Order>>(
      stream: db.ordersByCustomer(customerId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!;
        if (orders.isEmpty) return const EmptyState(text: 'Chưa có đơn hàng');
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final o = orders[i];
            return Card(
              child: ListTile(
                onTap: () => context.push('/orders/${o.id}'),
                title: Text(o.code,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(fmtDate(o.createdAt)),
                trailing: Text(
                  o.remaining > 0 ? 'Còn nợ ${money(o.remaining)}' : 'Đã thanh toán',
                  style: TextStyle(
                    color: o.remaining > 0 ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DebtTab extends StatelessWidget {
  final String customerId;
  final String customerName;
  const _DebtTab({required this.customerId, required this.customerName});
  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<List<Payment>>(
      stream: db.paymentsByCustomer(customerId),
      builder: (context, snap) {
        final payments = snap.data ?? [];
        return StreamBuilder<List<Order>>(
          stream: db.ordersByCustomer(customerId),
          builder: (context, osnap) {
            final debtOrders = (osnap.data ?? [])
                .where((o) =>
                    o.remaining > 0 && o.orderStatus != OrderStatus.CANCELLED)
                .toList();
            final totalDebt =
                debtOrders.fold<int>(0, (s, o) => s + o.remaining);
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (totalDebt > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ElevatedButton.icon(
                      onPressed: () => _collectDebt(
                          context, db, debtOrders, totalDebt),
                      icon: const Icon(Icons.payments),
                      label: Text('Thu công nợ (${money(totalDebt)})'),
                    ),
                  ),
                const Text('Đơn còn nợ',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (debtOrders.isEmpty)
                  const Text('Không có công nợ',
                      style: TextStyle(color: AppColors.textSecondary)),
                for (final o in debtOrders)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => context.push('/orders/${o.id}'),
                      title: Text(o.code),
                      subtitle: Text(fmtDate(o.createdAt)),
                      trailing: Text(money(o.remaining),
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text('Lịch sử thu tiền',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (payments.isEmpty)
                  const Text('Chưa có giao dịch',
                      style: TextStyle(color: AppColors.textSecondary)),
                for (final p in payments)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.payments, color: AppColors.success),
                      title: Text('${money(p.amount)} · ${p.method.label}'),
                      subtitle: Text('${p.orderCode} · ${fmtDateTime(p.at)}'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _collectDebt(BuildContext context, Db db,
      List<Order> debtOrders, int totalDebt) async {
    final amountC = TextEditingController(text: '$totalDebt');
    final noteC = TextEditingController();
    PaymentMethod method = PaymentMethod.transfer;
    final user = context.read<AuthProvider>().user!;
    final sorted = [...debtOrders]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final amount = int.tryParse(
                  amountC.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
              0;
          // FIFO preview.
          final plan = <(String, int)>[];
          var left = amount;
          for (final o in sorted) {
            if (left <= 0) break;
            final take = left < o.remaining ? left : o.remaining;
            plan.add((o.code, take));
            left -= take;
          }
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
                    child: Text('Thu công nợ',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 16),
                  KVRow('Tổng nợ', money(totalDebt),
                      valueColor: AppColors.danger, bold: true),
                  const Divider(),
                  TextField(
                    controller: amountC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Số tiền thu', suffixText: 'đ'),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Hình thức'),
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
                  const SizedBox(height: 16),
                  const Text('Phân bổ (đơn cũ trước)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final e in plan) KVRow(e.$1, money(e.$2)),
                  if (plan.isEmpty)
                    const Text('Nhập số tiền để xem phân bổ',
                        style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed:
                        amount <= 0 ? null : () => Navigator.pop(ctx, true),
                    child: const Text('Xác nhận thu'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok == true) {
      final amount = int.tryParse(
              amountC.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      await db.collectCustomerDebt(
        customerId: customerId,
        amount: amount,
        method: method,
        actorId: user.id,
        actorName: user.name,
        note: noteC.text.trim(),
      );
      if (context.mounted) toast(context, 'Đã thu ${money(amount)}');
    }
  }
}

class _InfoTab extends StatelessWidget {
  final Customer customer;
  const _InfoTab({required this.customer});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KVRow('Số đơn', '${customer.orderCount}'),
              KVRow('Ghi chú', customer.note.isEmpty ? '--' : customer.note),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('Địa chỉ giao hàng',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final a in customer.addresses)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                  a.isDefault ? Icons.check_circle : Icons.location_on_outlined,
                  color: a.isDefault ? AppColors.success : AppColors.textSecondary),
              title: Text(a.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${a.address}\n${a.receiver} · ${a.phone}'),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }
}
