import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../models/order.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class WarehouseScreen extends StatelessWidget {
  const WarehouseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
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
              Tab(text: 'Đã đóng'),
            ],
          ),
        ),
        body: StreamBuilder<List<Order>>(
          stream: db.orders(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!
                .where((o) => o.orderStatus != OrderStatus.CANCELLED)
                .toList();
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
                _list(context,
                    all.where((o) => o.warehouseStatus == WarehouseStatus.PACKED).toList()),
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
}
