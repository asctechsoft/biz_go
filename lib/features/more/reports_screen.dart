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
import '../../services/excel_export.dart';
import '../../widgets/common.dart';

enum ReportPeriod { week, month, quarter, year }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.week;

  /// Khoảng thời gian [từ, đến] theo kỳ đang chọn (đến = bây giờ).
  DateTimeRange _range() {
    final now = DateTime.now();
    switch (_period) {
      case ReportPeriod.week:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day)
                .subtract(const Duration(days: 6)),
            end: now);
      case ReportPeriod.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case ReportPeriod.quarter:
        final startMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
            start: DateTime(now.year, startMonth, 1), end: now);
      case ReportPeriod.year:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
    }
  }

  String get _periodLabel {
    final now = DateTime.now();
    switch (_period) {
      case ReportPeriod.week:
        return '7 ngày qua';
      case ReportPeriod.month:
        return 'Tháng ${now.month}/${now.year}';
      case ReportPeriod.quarter:
        return 'Quý ${((now.month - 1) ~/ 3) + 1}/${now.year}';
      case ReportPeriod.year:
        return 'Năm ${now.year}';
    }
  }

  bool _inRange(DateTime t, DateTimeRange r) {
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
    return !t.isBefore(start) && !t.isAfter(end);
  }

  Future<void> _exportExcel(BuildContext context, Db db) async {
    final range = _range();
    toast(context, 'Đang tạo Excel ($_periodLabel)...');
    try {
      final orders = await db.orders().first;
      final customers = await db.customers().first;
      await ExcelExport.exportReport(
        orders: orders,
        customers: customers,
        from: range.start,
        to: range.end,
      );
    } catch (e) {
      if (context.mounted) toast(context, 'Lỗi xuất Excel: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final range = _range();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Xuất Excel ($_periodLabel)',
            onPressed: () => _exportExcel(context, db),
          ),
        ],
      ),
      body: StreamBuilder<List<Order>>(
        stream: db.orders(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // Lọc đơn theo kỳ đang chọn.
          final orders = snap.data!
              .where((o) => _inRange(o.createdAt, range))
              .toList();
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
              final actualCollected = (psnap.data ?? [])
                  .where((p) => _inRange(p.at, range))
                  .fold<int>(0, (s, p) => s + p.amount);
              return ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, 24 + MediaQuery.of(context).padding.bottom),
                children: [
                  _periodSelector(),
                  const SizedBox(height: 16),
                  Text('Tổng quan · $_periodLabel',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
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
                  Text('Doanh số · $_periodLabel',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _PeriodChart(orders: active, period: _period),
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

  Widget _periodSelector() {
    String label(ReportPeriod p) => switch (p) {
          ReportPeriod.week => 'Tuần',
          ReportPeriod.month => 'Tháng',
          ReportPeriod.quarter => 'Quý',
          ReportPeriod.year => 'Năm',
        };
    return Row(
      children: [
        for (final p in ReportPeriod.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label(p)),
              selected: _period == p,
              onSelected: (_) => setState(() => _period = p),
            ),
          ),
      ],
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

/// Biểu đồ cột doanh số theo kỳ (tuần: theo ngày; tháng: theo ngày;
/// quý/năm: theo tháng). Không dùng thư viện chart ngoài.
class _PeriodChart extends StatelessWidget {
  final List<Order> orders;
  final ReportPeriod period;
  const _PeriodChart({required this.orders, required this.period});

  /// Danh sách cột (nhãn, tổng tiền) theo kỳ.
  List<(String, int)> _buckets() {
    final now = DateTime.now();
    int sumDay(DateTime d) => orders
        .where((o) =>
            o.createdAt.year == d.year &&
            o.createdAt.month == d.month &&
            o.createdAt.day == d.day)
        .fold<int>(0, (s, o) => s + o.total);
    int sumMonth(int y, int m) => orders
        .where((o) => o.createdAt.year == y && o.createdAt.month == m)
        .fold<int>(0, (s, o) => s + o.total);

    switch (period) {
      case ReportPeriod.week:
        const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
        return [
          for (var i = 0; i < 7; i++)
            () {
              final d = DateTime(now.year, now.month, now.day)
                  .subtract(Duration(days: 6 - i));
              return (wd[d.weekday - 1], sumDay(d));
            }()
        ];
      case ReportPeriod.month:
        return [
          for (var day = 1; day <= now.day; day++)
            ('$day', sumDay(DateTime(now.year, now.month, day)))
        ];
      case ReportPeriod.quarter:
        final startMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return [
          for (var m = startMonth; m <= now.month; m++)
            ('T$m', sumMonth(now.year, m))
        ];
      case ReportPeriod.year:
        return [
          for (var m = 1; m <= now.month; m++)
            ('T$m', sumMonth(now.year, m))
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _buckets();
    final maxV = data.fold<int>(1, (m, e) => e.$2 > m ? e.$2 : m);
    // Nhiều cột (tháng) → cho cuộn ngang, cột đủ rộng để đọc.
    final many = data.length > 8;
    final barW = many ? 34.0 : null;
    final bars = <Widget>[
      for (final e in data)
        SizedBox(
          width: barW,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                e.$2 == 0 ? '' : '${(e.$2 / 1000).round()}k',
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 90 * (e.$2 / maxV),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(e.$1, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
    ];
    return SectionCard(
      child: SizedBox(
        height: 140,
        child: many
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: bars),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (final b in bars) Expanded(child: b)],
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
