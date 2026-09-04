import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_notification.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: StreamBuilder<List<Order>>(
        stream: db.orders(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          }
          final orders = snap.data!;
          final now = DateTime.now();
          final yest = now.subtract(const Duration(days: 1));

          final today = orders
              .where((o) => _sameDay(o.createdAt, now))
              .toList();
          final yesterday = orders
              .where((o) => _sameDay(o.createdAt, yest))
              .toList();
          final active = orders.where(
            (o) => o.orderStatus != OrderStatus.CANCELLED,
          );

          final revenueToday = today.fold<int>(0, (s, o) => s + o.total);
          final revenueYest = yesterday.fold<int>(0, (s, o) => s + o.total);
          final delivering = orders
              .where((o) => o.deliveryStatus == DeliveryStatus.ON_THE_WAY)
              .length;
          final debt = active.fold<int>(
            0,
            (s, o) => s + (o.remaining > 0 ? o.remaining : 0),
          );

          return Column(
            children: [
              // ---- Phần trên cố định (không scroll) ----
              _Header(name: user?.name ?? '', now: now, db: db),
              // Card đè lên đáy header (-30) nhưng layout chỉ chiếm 98px
              // (128 - 30) để không tạo khoảng trống bên dưới.
              SizedBox(
                height: 98,
                child: OverflowBox(
                  minHeight: 0,
                  maxHeight: 128,
                  alignment: Alignment.topCenter,
                  child: Transform.translate(
                    offset: const Offset(0, -30),
                    child: _StatRow(
                      todayCount: today.length,
                      yestCount: yesterday.length,
                      revenueToday: revenueToday,
                      revenueYest: revenueYest,
                      delivering: delivering,
                      debt: debt,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // ---- Phần dưới scroll ----
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration,
                        child: _StatusSection(orders: orders),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration,
                        child: _RevenueSection(orders: orders),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _TodoCard(orders: orders),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _RecentCard(orders: orders),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------- Header -------------------------
class _Header extends StatelessWidget {
  final String name;
  final DateTime now;
  final Db db;
  const _Header({required this.name, required this.now, required this.db});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    final dateStr = DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(now);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 46),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF2E9E5B), Color(0xFF3A7BD6)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào, ${name.isEmpty ? 'bạn' : name} 👋',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tổng quan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _capitalize(dateStr),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _BellButton(db: db, role: role),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Avatar(name, size: 44),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _BellButton extends StatelessWidget {
  final Db db;
  final UserRole? role;
  const _BellButton({required this.db, required this.role});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: role == null ? null : db.notifications(role!),
      builder: (context, snap) {
        final unread = (snap.data ?? []).where((n) => !n.read).length;
        return GestureDetector(
          onTap: () => context.push('/notifications'),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none,
                  color: AppColors.primary,
                  size: 22,
                ),
                if (unread > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '${unread > 9 ? '9+' : unread}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------- Stat cards (4 in a row) -------------------------
class _StatRow extends StatelessWidget {
  final int todayCount, yestCount, revenueToday, revenueYest, delivering, debt;
  const _StatRow({
    required this.todayCount,
    required this.yestCount,
    required this.revenueToday,
    required this.revenueYest,
    required this.delivering,
    required this.debt,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        physics: const BouncingScrollPhysics(),
        children: [
          _StatCard(
            icon: Icons.receipt_long,
            color: AppColors.primary,
            label: 'Đơn hôm nay',
            value: '$todayCount',
            trend: _pct(todayCount, yestCount),
          ),
          _StatCard(
            icon: Icons.bar_chart,
            color: AppColors.info,
            label: 'Doanh thu',
            value: money(revenueToday),
            trend: _pct(revenueToday, revenueYest),
          ),
          _StatCard(
            icon: Icons.local_shipping,
            color: AppColors.success,
            label: 'Đang giao',
            value: '$delivering',
          ),
          _StatCard(
            icon: Icons.account_balance_wallet,
            color: AppColors.danger,
            label: 'Công nợ',
            value: money(debt),
          ),
        ],
      ),
    );
  }

  double? _pct(int today, int yest) {
    if (yest <= 0) return today > 0 ? 100 : null;
    return (today - yest) * 100 / yest;
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double? trend;
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 3),
          if (trend != null)
            Row(
              children: [
                Icon(
                  trend! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: trend! >= 0 ? AppColors.success : AppColors.danger,
                ),
                const SizedBox(width: 2),
                Text(
                  '${trend!.abs().toStringAsFixed(0)}% so với hôm qua',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: trend! >= 0 ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  final List<Order> orders;
  const _StatusSection({required this.orders});

  @override
  Widget build(BuildContext context) {
    final total = orders.length;
    final done = orders
        .where(
          (o) =>
              o.deliveryStatus == DeliveryStatus.DELIVERED ||
              o.orderStatus == OrderStatus.COMPLETED,
        )
        .length;
    final shipping = orders
        .where(
          (o) =>
              o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
              o.deliveryStatus == DeliveryStatus.ARRIVED,
        )
        .length;
    final cancelled = orders
        .where((o) => o.orderStatus == OrderStatus.CANCELLED)
        .length;
    final waiting = (total - done - shipping - cancelled).clamp(0, total);

    final data = <(String, Color, int)>[
      ('Hoàn thành', AppColors.success, done),
      ('Đang giao', AppColors.info, shipping),
      ('Chờ lấy hàng', AppColors.warning, waiting),
      ('Đã hủy', AppColors.textSecondary, cancelled),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tình trạng đơn hàng',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: total == 0 ? 0 : 2,
                      centerSpaceRadius: 42,
                      sections: total == 0
                          ? [
                              PieChartSectionData(
                                value: 1,
                                color: AppColors.border,
                                radius: 12,
                                showTitle: false,
                              ),
                            ]
                          : [
                              for (final d in data)
                                if (d.$3 > 0)
                                  PieChartSectionData(
                                    value: d.$3.toDouble(),
                                    color: d.$2,
                                    radius: 14,
                                    showTitle: false,
                                  ),
                            ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Tổng đơn',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final d in data)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: d.$2,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              d.$1,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${d.$3}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${total == 0 ? 0 : (d.$3 * 100 / total).round()}%)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RevenueSection extends StatelessWidget {
  final List<Order> orders;
  const _RevenueSection({required this.orders});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = orders
        .where((o) => o.orderStatus != OrderStatus.CANCELLED)
        .toList();
    final days = List.generate(
      7,
      (i) => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i)),
    );
    int dayTotal(DateTime d) => active
        .where(
          (o) =>
              o.createdAt.year == d.year &&
              o.createdAt.month == d.month &&
              o.createdAt.day == d.day,
        )
        .fold<int>(0, (s, o) => s + o.total);
    final totals = [for (final d in days) dayTotal(d)];
    final weekTotal = totals.fold<int>(0, (s, v) => s + v);
    // Trend so với 7 ngày trước đó.
    final prevTotal = List.generate(7, (i) {
      final d = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 13 - i));
      return dayTotal(d);
    }).fold<int>(0, (s, v) => s + v);
    final pct = prevTotal <= 0
        ? (weekTotal > 0 ? 100.0 : null)
        : (weekTotal - prevTotal) * 100 / prevTotal;
    final maxV = totals.fold<int>(1, (m, v) => v > m ? v : m).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Doanh thu 7 ngày qua',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                money(weekTotal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (pct != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (pct >= 0 ? AppColors.success : AppColors.danger)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 11,
                      color: pct >= 0 ? AppColors.success : AppColors.danger,
                    ),
                    Text(
                      '${pct.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pct >= 0 ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 156,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxV * 1.25,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipColor: (_) => AppColors.textPrimary,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        money(s.y.toInt()),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxV / 2 <= 0 ? 1 : maxV / 2,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: maxV / 2 <= 0 ? 1 : maxV / 2,
                    getTitlesWidget: (v, _) => Text(
                      v >= 1000000
                          ? '${(v / 1000000).toStringAsFixed(0)}M'
                          : '${(v / 1000).toStringAsFixed(0)}k',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i > 6) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          DateFormat('d/M').format(days[i]),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: AppColors.success,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                      radius: 2.5,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: AppColors.success,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.success.withValues(alpha: 0.25),
                        AppColors.success.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  spots: [
                    for (var i = 0; i < 7; i++)
                      FlSpot(i.toDouble(), totals[i].toDouble()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------- Việc cần làm -------------------------
class _TodoCard extends StatelessWidget {
  final List<Order> orders;
  const _TodoCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    final packing = orders
        .where(
          (o) =>
              o.warehouseStatus == WarehouseStatus.PREPARED &&
              o.orderStatus != OrderStatus.CANCELLED,
        )
        .length;
    final loading = orders
        .where(
          (o) =>
              o.warehouseStatus == WarehouseStatus.PACKED &&
              o.tripId == null &&
              o.orderStatus != OrderStatus.CANCELLED,
        )
        .length;
    final debtCount = orders
        .where((o) => o.remaining > 0 && o.orderStatus != OrderStatus.CANCELLED)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Việc cần làm',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              GestureDetector(
                onTap: () => context.push('/orders'),
                child: const Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 106,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _todo(
                  context,
                  Icons.inventory_2,
                  AppColors.warning,
                  'Đơn chờ đóng gói',
                  packing,
                  '/warehouse',
                ),
                _todo(
                  context,
                  Icons.local_shipping,
                  AppColors.info,
                  'Đơn chờ xếp xe',
                  loading,
                  '/delivery',
                ),
                _todo(
                  context,
                  Icons.account_balance_wallet,
                  AppColors.success,
                  'Công nợ cần thu',
                  debtCount,
                  '/customers',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todo(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
    int count,
    String route,
  ) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        width: 172,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------- Recent orders -------------------------
class _RecentCard extends StatelessWidget {
  final List<Order> orders;
  const _RecentCard({required this.orders});

  @override
  Widget build(BuildContext context) {
    final recent = [...orders]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final top = recent.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Đơn hàng gần đây',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              GestureDetector(
                onTap: () => context.push('/orders'),
                child: const Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (top.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chưa có đơn',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final o in top) _row(context, o),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Order o) {
    final StatusUi ui;
    if (o.orderStatus == OrderStatus.CANCELLED) {
      ui = orderStatusUi(OrderStatus.CANCELLED);
    } else if (o.deliveryStatus != DeliveryStatus.WAITING_ASSIGNMENT) {
      ui = deliveryStatusUi(o.deliveryStatus);
    } else {
      ui = warehouseStatusUi(o.warehouseStatus);
    }
    return InkWell(
      onTap: () => context.push('/orders/${o.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: ui.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.code,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  fmtTime(o.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    o.customerPhone,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(ui, dense: true),
                const SizedBox(height: 2),
                Text(
                  money(o.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

const _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.all(Radius.circular(16)),
  boxShadow: [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ],
);
