import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import '../delivery/delivery_actions.dart';

class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final role = context.watch<AuthProvider>().user?.role;
    // Đóng hàng xong là cho đi luôn — không còn bước xếp chuyến.
    final canDepart = role != null && Perm.startDelivery(role);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kho & đóng hàng'),
          bottom: const TabBar(
            isScrollable: false,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xCCFFFFFF),
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(text: 'Chờ chuẩn bị'),
              Tab(text: 'Chuẩn bị'),
              Tab(text: 'Chờ xuất phát'),
            ],
          ),
        ),
        body: StreamBuilder<List<Order>>(
          // Kho nhìn việc tồn: nới rộng hơn tab Đơn hàng để đơn kẹt lâu
          // không bị rơi khỏi tầm mắt.
          stream: db.orders(days: 90),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!
                .where((o) => o.orderStatus != OrderStatus.CANCELLED)
                .toList();
            // Đã đóng hàng mà CHƯA lên đường — đây là lô chờ bấm "Xuất phát".
            final packed = all
                .where((o) =>
                    o.warehouseStatus == WarehouseStatus.PACKED &&
                    (o.deliveryStatus == DeliveryStatus.WAITING_ASSIGNMENT ||
                        o.deliveryStatus == DeliveryStatus.ASSIGNED ||
                        o.deliveryStatus == DeliveryStatus.LOADING ||
                        o.deliveryStatus == DeliveryStatus.RESCHEDULED))
                .toList()
              // Cùng quy tắc với màn Giao hàng: GẤP lên đầu, rồi tới giờ dự
              // kiến xuất phát. Hai màn xếp khác nhau là kho làm sai thứ tự.
              ..sort(Order.byDepartOrder);
            return TabBarView(
              children: [
                _list(context,
                    all.where((o) => o.warehouseStatus == WarehouseStatus.WAITING).toList()),
                _list(
                    context,
                    all
                        .where((o) =>
                            o.warehouseStatus == WarehouseStatus.PREPARING ||
                            o.warehouseStatus == WarehouseStatus.PREPARED ||
                            o.warehouseStatus == WarehouseStatus.PACKING)
                        .toList()),
                _packedList(context, packed, canDepart),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<Order> orders) {
    if (orders.isEmpty) return const EmptyState(text: 'Không có đơn');
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
            subtitle: Text(
                '${o.customerName} · ${o.items.length} mặt hàng\n${fmtTime(o.createdAt)}'),
            isThreeLine: true,
            trailing: StatusChip(warehouseStatusUi(o.warehouseStatus), dense: true),
          ),
        );
      },
    );
  }

  /// Tab "Chờ xuất phát" — mỗi đơn có nút đi riêng, dưới cùng là nút đi cả lô.
  Widget _packedList(
      BuildContext context, List<Order> orders, bool canDepart) {
    if (orders.isEmpty) {
      return const EmptyState(text: 'Không có đơn nào chờ xuất phát');
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = orders[i];
              return Card(
                child: ListTile(
                  onTap: () => context.push('/orders/${o.id}'),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(o.code,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (o.priority)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('GẤP',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.danger)),
                        ),
                      if (o.plannedDepartAt != null)
                        Text(fmtDepartAt(o.plannedDepartAt),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                    ],
                  ),
                  subtitle: Text(
                      '${o.customerName}\n${o.packageCode ?? ''} · ${fmtWeight(o.weightKg, o.weightUnit)}'),
                  isThreeLine: true,
                  trailing: canDepart
                      ? FilledButton(
                          onPressed: () => departOrder(context, o),
                          child: const Text('Xuất phát'),
                        )
                      : StatusChip(deliveryStatusUi(o.deliveryStatus),
                          dense: true),
                ),
              );
            },
          ),
        ),
        if (canDepart)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => departAllOrders(context, orders),
                  icon: const Icon(Icons.local_shipping),
                  label: Text('Xuất phát tất cả (${orders.length} đơn)'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
