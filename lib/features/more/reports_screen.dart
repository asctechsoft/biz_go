import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../models/fleet.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo')),
      body: StreamBuilder<List<Order>>(
        stream: db.orders(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snap.data!;
          final active =
              orders.where((o) => o.orderStatus != OrderStatus.CANCELLED).toList();
          final revenue = active.fold<int>(0, (s, o) => s + o.total);
          final debt = active.fold<int>(
              0, (s, o) => s + (o.remaining > 0 ? o.remaining : 0));
          final completed = orders
              .where((o) => o.orderStatus == OrderStatus.COMPLETED)
              .length;
          final cancelled = orders
              .where((o) => o.orderStatus == OrderStatus.CANCELLED)
              .length;
          final failed = orders
              .where((o) => o.deliveryStatus == DeliveryStatus.FAILED)
              .length;

          // product sales
          final byProduct = <String, (int qty, int revenue)>{};
          for (final o in active) {
            for (final it in o.items) {
              final k = it.displayName;
              final prev = byProduct[k] ?? (0, 0);
              byProduct[k] =
                  (prev.$1 + it.quantity, prev.$2 + it.lineTotal);
            }
          }
          final topProducts = byProduct.entries.toList()
            ..sort((a, b) => b.value.$2.compareTo(a.value.$2));

          return StreamBuilder<List<Payment>>(
            stream: _allPayments(db),
            builder: (context, psnap) {
              final actualCollected =
                  (psnap.data ?? []).fold<int>(0, (s, p) => s + p.amount);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Tổng quan kinh doanh',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(children: [
                    _metric('Doanh số', money(revenue), AppColors.primary),
                    const SizedBox(width: 12),
                    _metric('Tiền thực thu', money(actualCollected),
                        AppColors.success),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _metric('Công nợ', money(debt), AppColors.danger),
                    const SizedBox(width: 12),
                    _metric('Tổng đơn', '${active.length}',
                        AppColors.textPrimary),
                  ]),
                  const SizedBox(height: 20),
                  SectionCard(
                    child: Column(
                      children: [
                        KVRow('Đơn hoàn thành', '$completed'),
                        KVRow('Đơn giao thất bại', '$failed'),
                        KVRow('Đơn đã hủy', '$cancelled'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Sản phẩm bán chạy',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SectionCard(
                    child: Column(
                      children: [
                        if (topProducts.isEmpty)
                          const Text('Chưa có dữ liệu',
                              style: TextStyle(color: AppColors.textSecondary)),
                        for (final e in topProducts.take(10))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text(e.key)),
                                Text('x${e.value.$1}',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary)),
                                const SizedBox(width: 12),
                                Text(money(e.value.$2),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Doanh số 7 ngày',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _SevenDayChart(orders: active),
                  const SizedBox(height: 20),
                  const Text('Công nợ theo khách',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _DebtByCustomer(db: db),
                  const SizedBox(height: 20),
                  const Text('Hiệu suất chuyến xe',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _TripStats(db: db),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Stream<List<Payment>> _allPayments(Db db) => db.paymentsAll();

  Widget _metric(String label, String value, Color color) => Expanded(
        child: SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ),
      );
}

/// Simple 7-day revenue bar chart (no external chart lib).
class _SevenDayChart extends StatelessWidget {
  final List<Order> orders;
  const _SevenDayChart({required this.orders});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      return d;
    });
    final totals = [
      for (final d in days)
        orders
            .where((o) =>
                o.createdAt.year == d.year &&
                o.createdAt.month == d.month &&
                o.createdAt.day == d.day)
            .fold<int>(0, (s, o) => s + o.total)
    ];
    final maxV = totals.fold<int>(1, (m, v) => v > m ? v : m);
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return SectionCard(
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      totals[i] == 0 ? '' : '${(totals[i] / 1000).round()}k',
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 90 * (totals[i] / maxV),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(labels[days[i].weekday - 1],
                        style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DebtByCustomer extends StatelessWidget {
  final Db db;
  const _DebtByCustomer({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Customer>>(
      stream: db.customers(),
      builder: (context, snap) {
        final debtors = (snap.data ?? [])
            .where((c) => c.debt > 0)
            .toList()
          ..sort((a, b) => b.debt.compareTo(a.debt));
        return SectionCard(
          child: Column(
            children: [
              if (debtors.isEmpty)
                const Text('Không có công nợ',
                    style: TextStyle(color: AppColors.textSecondary)),
              for (final c in debtors.take(10))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(c.name)),
                      Text(money(c.debt),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.danger)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TripStats extends StatelessWidget {
  final Db db;
  const _TripStats({required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Trip>>(
      stream: db.trips(),
      builder: (context, snap) {
        final trips = snap.data ?? [];
        final totalOrders = trips.fold<int>(0, (s, t) => s + t.orderCount);
        final delivered = trips.fold<int>(0, (s, t) => s + t.deliveredCount);
        final rate =
            totalOrders == 0 ? 0 : (delivered * 100 / totalOrders).round();
        return SectionCard(
          child: Column(
            children: [
              KVRow('Số chuyến', '${trips.length}'),
              KVRow('Tổng đơn giao', '$totalOrders'),
              KVRow('Giao thành công', '$delivered'),
              KVRow('Tỷ lệ thành công', '$rate%',
                  valueColor:
                      rate >= 80 ? AppColors.success : AppColors.warning,
                  bold: true),
            ],
          ),
        );
      },
    );
  }
}
