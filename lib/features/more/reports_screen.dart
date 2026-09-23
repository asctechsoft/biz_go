import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../services/db.dart';
import '../../services/excel_export.dart';
import '../../widgets/common.dart';

enum ReportPeriod { week, month, quarter, year }

/// Màu thanh trong "Sản phẩm bán chạy" — lặp lại nếu quá 4 sản phẩm.
const _productBarColors = [
  AppColors.primary,
  AppColors.warning,
  AppColors.info,
  Color(0xFF8E5FD9),
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.week;

  /// Mốc ngày để tính kỳ — mặc định hôm nay. Bấm nút lịch chọn tháng khác thì
  /// đổi mốc này để xem lại kỳ cũ; các kỳ Quý/Năm cũng suy theo mốc này nên
  /// đổi nhất quán, không phải chỉ mỗi Tháng "nghe lời".
  DateTime _anchor = DateTime.now();

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _anchor.year == now.year && _anchor.month == now.month;
  }

  /// Khoảng thời gian [từ, đến] theo kỳ đang chọn, quanh [_anchor]. Kỳ đang
  /// diễn ra (chứa hôm nay) thì đến = bây giờ; kỳ đã qua hẳn thì đến = cuối kỳ.
  DateTimeRange _range() {
    final now = DateTime.now();
    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59);
    switch (_period) {
      case ReportPeriod.week:
        final end = _anchor;
        return DateTimeRange(
            start: DateTime(end.year, end.month, end.day)
                .subtract(const Duration(days: 6)),
            end: end);
      case ReportPeriod.month:
        final start = DateTime(_anchor.year, _anchor.month, 1);
        final lastDay = DateTime(_anchor.year, _anchor.month + 1, 0);
        return DateTimeRange(
            start: start, end: _isCurrentMonth ? now : endOfDay(lastDay));
      case ReportPeriod.quarter:
        final startMonth = ((_anchor.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(_anchor.year, startMonth, 1);
        final lastDay = DateTime(_anchor.year, startMonth + 3, 0);
        final isCurrent = _anchor.year == now.year &&
            startMonth == ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(
            start: start, end: isCurrent ? now : endOfDay(lastDay));
      case ReportPeriod.year:
        final start = DateTime(_anchor.year, 1, 1);
        final isCurrent = _anchor.year == now.year;
        return DateTimeRange(
            start: start,
            end: isCurrent ? now : endOfDay(DateTime(_anchor.year, 12, 31)));
    }
  }

  String get _periodLabel {
    switch (_period) {
      case ReportPeriod.week:
        return '7 ngày qua';
      case ReportPeriod.month:
        return 'Tháng ${_anchor.month}/${_anchor.year}';
      case ReportPeriod.quarter:
        return 'Quý ${((_anchor.month - 1) ~/ 3) + 1}/${_anchor.year}';
      case ReportPeriod.year:
        return 'Năm ${_anchor.year}';
    }
  }

  /// Mở bottom sheet chọn tháng/năm muốn xem lại — thay [_anchor].
  Future<void> _pickMonth() async {
    var y = _anchor.year;
    final now = DateTime.now();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader('Chọn tháng xem lại'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setSheet(() => y--),
                  ),
                  Text('$y',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: y >= now.year ? null : () => setSheet(() => y++),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    for (var m = 1; m <= 12; m++)
                      _MonthCell(
                        label: 'Th $m',
                        selected: y == _anchor.year && m == _anchor.month,
                        // Chưa tới tháng đó thì chưa có dữ liệu để xem.
                        enabled: DateTime(y, m, 1)
                            .isBefore(DateTime(now.year, now.month + 1, 1)),
                        onTap: () => Navigator.pop(ctx, DateTime(y, m, 1)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _anchor = picked);
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
      // Báo cáo phải quét cả đơn cũ — người dùng tự chọn khoảng thời gian.
      final orders = await db.allOrders().first;
      final customers = await db.customers().first;
      await ExcelExport.exportReport(
        orders: orders,
        customers: customers,
        from: range.start,
        to: range.end,
      );
    } catch (e) {
      debugPrint('EXPORT-EXCEL ERROR: $e');
      if (context.mounted) {
        toast(
            context,
            friendlyError(e,
                fallback: 'Xuất Excel không thành công. Thử lại giúp tôi.'));
      }
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
        stream: db.allOrders(),
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
              final k = it.reportLabel;
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
                  // Tab Năm gộp cả 12 tháng nên 3 con số này không còn nói
                  // lên điều gì rõ ràng (vd "đơn hoàn thành" cả năm) — ẩn đi,
                  // các kỳ ngắn hơn (tuần/tháng/quý) vẫn hiện bình thường.
                  if (_period != ReportPeriod.year) ...[
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
                  ],
                  const SizedBox(height: 20),
                  const Text('Sản phẩm bán chạy',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final top = topProducts.take(10).toList();
                    // Thanh dài/ngắn so theo mục doanh số cao nhất — vẫn thấy
                    // rõ ai hơn ai dù góc phải giờ hiện số lượng bán, không
                    // phải %.
                    final maxRevenue =
                        top.isEmpty ? 0 : top.first.value.$2;
                    return SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (top.isEmpty)
                            const Text('Chưa có dữ liệu',
                                style: TextStyle(color: AppColors.textSecondary)),
                          for (final (i, e) in top.indexed)
                            Padding(
                              padding:
                                  EdgeInsets.only(bottom: i == top.length - 1 ? 0 : 16),
                              child: _ProductBar(
                                label: e.key,
                                amount: e.value.$2,
                                qty: e.value.$1,
                                barFactor: maxRevenue == 0
                                    ? 0
                                    : e.value.$2 / maxRevenue,
                                color: _productBarColors[
                                    i % _productBarColors.length],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),
                  Text('Doanh số · $_periodLabel',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _PeriodChart(orders: active, period: _period, range: range),
                  const SizedBox(height: 20),
                  const Text('Công nợ theo khách',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _DebtByCustomer(db: db),
                  const SizedBox(height: 20),
                  const Text('Hiệu suất giao hàng',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _DeliveryStats(orders: active),
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
    // Một Wrap DUY NHẤT cho cả chip kỳ lẫn nút chọn tháng/về hiện tại — tách
    // riêng nút lịch ra ngoài Row từng làm nó lẻ loi khi "Năm" xuống dòng.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in ReportPeriod.values)
          ChoiceChip(
            label: Text(label(p)),
            selected: _period == p,
            onSelected: (_) => setState(() => _period = p),
          ),
        // Chỉ hiện khi đang xem lại tháng cũ — bấm về ngay kỳ hiện tại.
        if (!_isCurrentMonth)
          ActionChip(
            avatar: const Icon(Icons.today, size: 16),
            label: const Text('Hiện tại'),
            onPressed: () => setState(() => _anchor = DateTime.now()),
          ),
        ActionChip(
          avatar: const Icon(Icons.calendar_month, size: 16),
          label: const Text('Chọn tháng'),
          onPressed: _pickMonth,
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
  final DateTimeRange range;
  const _PeriodChart(
      {required this.orders, required this.period, required this.range});

  /// Danh sách cột (nhãn, tổng tiền) theo kỳ — dựa thẳng vào [range] (đã tính
  /// sẵn "đến = bây giờ" cho kỳ đang diễn ra, "đến = cuối kỳ" cho kỳ đã qua)
  /// nên chart tự vẽ đủ cột dù đang xem tháng/quý/năm hiện tại hay đã cũ.
  List<(String, int)> _buckets() {
    int sumDay(DateTime d) => orders
        .where((o) =>
            o.createdAt.year == d.year &&
            o.createdAt.month == d.month &&
            o.createdAt.day == d.day)
        .fold<int>(0, (s, o) => s + o.total);
    int sumMonth(int y, int m) => orders
        .where((o) => o.createdAt.year == y && o.createdAt.month == m)
        .fold<int>(0, (s, o) => s + o.total);

    final start = DateTime(range.start.year, range.start.month, range.start.day);
    switch (period) {
      case ReportPeriod.week:
        const wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
        return [
          for (var i = 0; i < 7; i++)
            () {
              final d = start.add(Duration(days: i));
              return (wd[d.weekday - 1], sumDay(d));
            }()
        ];
      case ReportPeriod.month:
        return [
          for (var day = 1; day <= range.end.day; day++)
            ('$day', sumDay(DateTime(start.year, start.month, day)))
        ];
      case ReportPeriod.quarter:
      case ReportPeriod.year:
        return [
          for (var m = start.month; m <= range.end.month; m++)
            ('T$m', sumMonth(start.year, m))
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

/// Một dòng trong "Sản phẩm bán chạy": tên + doanh số + % rồi tới thanh màu,
/// thay cho dòng chữ thuần trước đây — nhìn ra ngay ai hơn ai mà không phải
/// so số.
class _ProductBar extends StatelessWidget {
  final String label;
  final int amount;
  final int qty;
  final double barFactor;
  final Color color;
  const _ProductBar({
    required this.label,
    required this.amount,
    required this.qty,
    required this.barFactor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(money(amount),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const Spacer(),
              Text('x$qty',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barFactor.clamp(0, 1),
              minHeight: 8,
              backgroundColor: AppColors.border,
              color: color,
            ),
          ),
        ],
      );
}

/// Ô chọn 1 tháng trong lưới 12 tháng của bottom sheet chọn tháng xem lại.
class _MonthCell extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(
          label,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: TextStyle(color: selected ? Colors.white : null),
        ),
        showCheckmark: false,
        selected: selected,
        selectedColor: AppColors.primary,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        onSelected: enabled ? (_) => onTap() : null,
      );
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

/// Hiệu suất giao hàng trong kỳ đang xem — tính thẳng trên đơn (không còn
/// chuyến xe để lấy `orderCount`/`deliveredCount`).
class _DeliveryStats extends StatelessWidget {
  final List<Order> orders;
  const _DeliveryStats({required this.orders});

  @override
  Widget build(BuildContext context) {
    // Chỉ tính đơn đã rời kho — đơn còn nằm chờ không phải "giao trượt".
    const shipped = {
      DeliveryStatus.ON_THE_WAY,
      DeliveryStatus.ARRIVED,
      DeliveryStatus.DELIVERED,
      DeliveryStatus.FAILED,
      DeliveryStatus.RETURNED,
    };
    final out = orders.where((o) => shipped.contains(o.deliveryStatus)).toList();
    final delivered = out
        .where((o) => o.deliveryStatus == DeliveryStatus.DELIVERED)
        .length;
    final failed = out
        .where((o) =>
            o.deliveryStatus == DeliveryStatus.FAILED ||
            o.deliveryStatus == DeliveryStatus.RETURNED)
        .length;
    final rate = out.isEmpty ? 0 : (delivered * 100 / out.length).round();
    return SectionCard(
      child: Column(
        children: [
          KVRow('Đơn đã xuất phát', '${out.length}'),
          KVRow('Giao thành công', '$delivered'),
          KVRow('Thất bại / hoàn hàng', '$failed'),
          KVRow('Tỷ lệ thành công', '$rate%',
              valueColor: rate >= 80 ? AppColors.success : AppColors.warning,
              bold: true),
        ],
      ),
    );
  }
}
