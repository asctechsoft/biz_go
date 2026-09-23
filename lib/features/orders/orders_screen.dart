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
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import 'order_tile.dart';

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

  /// Chỉ Chủ thấy tiền. Kho chỉ cần mã đơn + khách + trạng thái để soạn hàng.
  bool get _showMoney {
    final role = context.read<AuthProvider>().user?.role;
    return role != null && Perm.viewMoney(role);
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
              icon: const Icon(Icons.search),
              tooltip: 'Tìm đơn',
              onPressed: () => context.push('/order-search'),
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
            final all = snap.data!;
            return TabBarView(
              children: [
                _grouped(all),
                _grouped(all.where(isOrderPending).toList()),
                _grouped(all.where(isOrderDelivering).toList()),
                _grouped(all.where(isOrderDone).toList()),
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
                child: OrderTile(o: o, showMoney: _showMoney),
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
