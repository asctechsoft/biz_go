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

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

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
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () => context.push('/filter'),
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
          stream: db.orders(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!;
            bool pending(Order o) =>
                o.orderStatus != OrderStatus.CANCELLED &&
                o.deliveryStatus != DeliveryStatus.DELIVERED &&
                o.deliveryStatus != DeliveryStatus.ON_THE_WAY;
            bool delivering(Order o) =>
                o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
                o.deliveryStatus == DeliveryStatus.ARRIVED;
            bool done(Order o) =>
                o.deliveryStatus == DeliveryStatus.DELIVERED;
            return TabBarView(
              children: [
                _list(context, all),
                _list(context, all.where(pending).toList()),
                _list(context, all.where(delivering).toList()),
                _list(context, all.where(done).toList()),
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

  Widget _list(BuildContext context, List<Order> orders) {
    if (orders.isEmpty) return const EmptyState(text: 'Không có đơn');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final o = orders[i];
        // Pick the most informative status to show.
        final StatusUi ui;
        if (o.orderStatus == OrderStatus.CANCELLED) {
          ui = orderStatusUi(OrderStatus.CANCELLED);
        } else if (o.deliveryStatus != DeliveryStatus.WAITING_ASSIGNMENT) {
          ui = deliveryStatusUi(o.deliveryStatus);
        } else {
          ui = warehouseStatusUi(o.warehouseStatus);
        }
        return Card(
          child: ListTile(
            onTap: () => context.push('/orders/${o.id}'),
            leading: Avatar(o.customerName),
            title: Text(o.code,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.customerName),
                Text('${money(o.total)} · ${fmtTime(o.createdAt)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            trailing: StatusChip(ui, dense: true),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
