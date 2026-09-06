import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/app_notification.dart';
import '../../models/order.dart';
import '../../models/order_filter.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Danh sách đơn — gom theo NGÀY, trong ngày sắp theo mức ưu tiên.
///
/// Không đổ một mạch tất cả đơn ra list phẳng: mỗi ngày ~20 đơn thì sau 1 tuần
/// là cuộn mỏi tay mà không biết đơn nào của ngày nào.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  /// Số ngày đang tải. Bấm "Tải thêm" thì cộng dồn — xem [Db.orders].
  int _days = 30;

  /// Danh sách phải dài tối thiểu bấy nhiêu đơn mới hiện hàng "Tải thêm".
  static const _loadMoreThreshold = 20;

  OrderFilter _filter = OrderFilter.empty;

  /// Chỉ Chủ thấy tiền. Kho chỉ cần mã đơn + khách + trạng thái để soạn hàng.
  bool get _showMoney {
    final role = context.read<AuthProvider>().user?.role;
    return role != null && Perm.viewMoney(role);
  }

  /// Mở màn Lọc nhanh, nhận bộ lọc trả về.
  Future<void> _openFilter() async {
    final f = await context.push<OrderFilter>('/filter', extra: _filter);
    if (f == null || !mounted) return;
    setState(() {
      _filter = f;
      // Lọc khoảng ngày cũ hơn dữ liệu đang tải thì phải nới cửa sổ, kẻo lọc
      // ra rỗng dù đơn có thật.
      if (f.daysNeeded > _days) _days = f.daysNeeded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final role = context.watch<AuthProvider>().user?.role;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Đơn hàng'),
          actions: [
            // Vai trò không có màn Tổng quan thì đây là lối vào DUY NHẤT tới
            // hộp thông báo — Kiểm hàng chính là người nhận báo "Đơn mới".
            if (role != null && !Perm.viewDashboard(role))
              _NotifButton(role: role),
            IconButton(
              icon: Badge(
                isLabelVisible: _filter.isActive,
                label: Text('${_filter.count}'),
                child: const Icon(Icons.tune),
              ),
              onPressed: _openFilter,
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xCCFFFFFF), // trắng 80% — vẫn rõ
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(text: 'Tất cả'),
              Tab(text: 'Chờ xử lý'),
              Tab(text: 'Đang giao'),
              Tab(text: 'Đã giao'),
            ],
          ),
        ),
        body: StreamBuilder<List<Order>>(
          stream: db.orders(days: _days),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Bộ lọc nhanh áp trước, tab lọc tiếp bên trên kết quả đó.
            final all = snap.data!.where(_filter.matches).toList();
            bool pending(Order o) =>
                o.orderStatus != OrderStatus.CANCELLED &&
                o.deliveryStatus != DeliveryStatus.DELIVERED &&
                o.deliveryStatus != DeliveryStatus.ON_THE_WAY;
            bool delivering(Order o) =>
                o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
                o.deliveryStatus == DeliveryStatus.ARRIVED;
            bool done(Order o) => o.deliveryStatus == DeliveryStatus.DELIVERED;
            return Column(
              children: [
                if (_filter.isActive) _filterBar(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _grouped(all),
                      _grouped(all.where(pending).toList()),
                      _grouped(all.where(delivering).toList()),
                      _grouped(all.where(done).toList()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: (role != null && Perm.createOrder(role))
            ? FloatingActionButton(
                backgroundColor: AppColors.primary,
                onPressed: () => context.push('/orders/create'),
                child: const Icon(Icons.add, color: Colors.white),
              )
            : null,
      ),
    );
  }

  /// Thanh báo đang lọc — không có thì user tưởng mất đơn.
  Widget _filterBar() {
    final f = _filter;
    final parts = <String>[
      if (f.custom != null)
        '${fmtDate(f.custom!.start)} - ${fmtDate(f.custom!.end)}',
      if (f.orderStatus != null) orderStatusUi(f.orderStatus!).label,
      if (f.deliveryStatus != null) deliveryStatusUi(f.deliveryStatus!).label,
      if (_showMoney && f.paymentStatus != null)
        paymentStatusUi(f.paymentStatus!).label,
      if (f.staffId != null) f.staffName,
    ];
    return Material(
      color: AppColors.primaryLight,
      child: InkWell(
        onTap: _openFilter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  parts.join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.primary,
                tooltip: 'Xoá bộ lọc',
                onPressed: () =>
                    setState(() => _filter = OrderFilter.empty),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Gom nhóm + sắp xếp ----------

  /// Mức khẩn để sắp trong cùng một ngày — nhỏ hơn = lên trước.
  ///
  /// Đơn gấp luôn đầu bảng; sau đó là việc còn phải làm (chờ xử lý → đang
  /// giao), rồi mới tới đơn đã xong và đơn huỷ nằm đáy.
  int _rank(Order o) {
    if (o.orderStatus == OrderStatus.CANCELLED) return 4;
    if (o.priority) return 0;
    if (o.deliveryStatus == DeliveryStatus.DELIVERED) return 3;
    if (o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
        o.deliveryStatus == DeliveryStatus.ARRIVED) {
      return 2;
    }
    return 1; // còn phải xử lý
  }

  Widget _grouped(List<Order> orders) {
    if (orders.isEmpty) return const EmptyState(text: 'Không có đơn');

    // Gom theo ngày tạo. `orders` đã sort giảm dần theo createdAt từ Db nên
    // thứ tự ngày giữ nguyên, chỉ cần sắp lại BÊN TRONG mỗi ngày.
    final byDay = <DateTime, List<Order>>{};
    for (final o in orders) {
      final d = DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day);
      byDay.putIfAbsent(d, () => []).add(o);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final r = _rank(a).compareTo(_rank(b));
        if (r != 0) return r;
        // Việc còn phải làm: xếp theo giờ dự kiến xuất phát (đi sớm lên trước),
        // khớp với hàng đợi ở màn Kho và Giao hàng. Đơn đã xong/huỷ thì mới
        // lấy đơn mới nhất lên đầu vì đó chỉ là danh sách để tra lại.
        if (_rank(a) <= 2) return a.departAt.compareTo(b.departAt);
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    // Danh sách còn ngắn thì giấu hàng "Tải thêm" — mới dùng mà đã thấy nút
    // tải thêm là rối, trong khi cuộn vài cái là hết đơn rồi.
    final showLoadMore = orders.length >= _loadMoreThreshold;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: days.length + (showLoadMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == days.length) return _loadMore();
        final day = days[i];
        final list = byDay[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dayHeader(day, list),
            for (final o in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _tile(o),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// Tiêu đề ngày + số đơn + tổng tiền của ngày đó.
  Widget _dayHeader(DateTime day, List<Order> list) {
    final total = list
        .where((o) => o.orderStatus != OrderStatus.CANCELLED)
        .fold(0, (s, o) => s + o.total);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          Text(
            _dayLabel(day),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _showMoney
                  ? '${list.length} đơn · ${money(total)}'
                  : '${list.length} đơn',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static final _dayFmt = DateFormat('EEEE, dd/MM/yyyy', 'vi_VN');

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Hôm qua';
    // Viết hoa thứ: DateFormat trả "thứ năm, 04/09/2026".
    final s = _dayFmt.format(day);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  Widget _loadMore() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          children: [
            Text(
              'Đang xem đơn trong $_days ngày gần nhất',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _days += 30),
              icon: const Icon(Icons.history),
              label: const Text('Tải thêm 30 ngày'),
            ),
          ],
        ),
      );

  // ---------- Thẻ đơn ----------

  Widget _tile(Order o) {
    // Chọn trạng thái nhiều thông tin nhất để hiện.
    final StatusUi ui;
    if (o.orderStatus == OrderStatus.CANCELLED) {
      ui = orderStatusUi(OrderStatus.CANCELLED);
    } else if (o.deliveryStatus != DeliveryStatus.WAITING_ASSIGNMENT) {
      ui = deliveryStatusUi(o.deliveryStatus);
    } else {
      ui = warehouseStatusUi(o.warehouseStatus);
    }
    final urgent = o.priority && o.orderStatus != OrderStatus.CANCELLED;
    return Card(
      margin: EdgeInsets.zero,
      // Viền đỏ mảnh bên trái để lướt mắt là thấy đơn gấp.
      shape: urgent
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.danger, width: 1.4),
            )
          : null,
      child: ListTile(
        onTap: () => context.push('/orders/${o.id}'),
        leading: Avatar(o.customerName),
        title: Row(
          children: [
            if (urgent) ...[
              const _UrgentBadge(),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                o.code,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o.customerName),
            // Ghi rõ "tạo" vì ngay dưới có thể là giờ xuất phát — hai mốc giờ
            // trần trụi cạnh nhau thì không biết cái nào là cái nào.
            Text(
              _showMoney
                  ? '${money(o.total)} · tạo ${fmtTime(o.createdAt)}'
                  : 'Tạo lúc ${fmtTime(o.createdAt)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            // Giờ dự kiến xuất phát — chính là thứ quyết định thứ tự đơn
            // trong ngày, nên phải thấy ngay ở danh sách.
            if (o.plannedDepartAt != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'Xuất phát ${fmtDepartAt(o.plannedDepartAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: StatusChip(ui, dense: true),
        isThreeLine: true,
      ),
    );
  }
}

/// Nhãn "GẤP" đỏ trên thẻ đơn ưu tiên.
class _UrgentBadge extends StatelessWidget {
  const _UrgentBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'GẤP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
        ),
      );
}

/// Chuông thông báo + số chưa đọc, cho vai trò KHÔNG thấy màn Tổng quan.
/// Thiếu nút này thì `/notifications` thành route mồ côi: Kiểm hàng nhận push
/// "Đơn mới" mà không có chỗ nào trong app để mở lại danh sách.
class _NotifButton extends StatelessWidget {
  final UserRole role;
  const _NotifButton({required this.role});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<List<AppNotification>>(
      stream: db.notifications(role),
      builder: (context, snap) {
        final unread = (snap.data ?? []).where((n) => !n.read).length;
        return IconButton(
          tooltip: 'Thông báo',
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_none),
          ),
        );
      },
    );
  }
}
