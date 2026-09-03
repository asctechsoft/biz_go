import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/fleet.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});
  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  List<Order> _local = [];
  String _syncKey = '';

  void _sync(List<Order> orders) {
    final key = orders.map((o) => o.id).join(',');
    if (key != _syncKey) {
      _local = List.of(orders);
      _syncKey = key;
    } else {
      // refresh statuses in-place while keeping user's order
      _local = _local
          .map((o) => orders.firstWhere((n) => n.id == o.id, orElse: () => o))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<Trip>(
      stream: db.trip(widget.tripId),
      builder: (context, tsnap) {
        if (!tsnap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final trip = tsnap.data!;
        return StreamBuilder<List<Order>>(
          stream: db.ordersByTrip(widget.tripId),
          builder: (context, osnap) {
            final orders = osnap.data ?? [];
            _sync(orders);
            return Scaffold(
              appBar: AppBar(title: Text(trip.code)),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SectionCard(
                      child: Column(
                        children: [
                          KVRow('Xe', trip.vehiclePlate),
                          KVRow('Tài xế', '${trip.driverName}\n${trip.driverPhone}'),
                          KVRow('Trạng thái', tripStatusUi(trip.status).label),
                          KVRow('Giờ dự kiến',
                              fmtTime(trip.plannedDeparture)),
                          if (trip.actualDeparture != null)
                            KVRow('Giờ xuất phát', fmtTime(trip.actualDeparture)),
                          KVRow('Số đơn',
                              '${trip.deliveredCount}/${trip.orderCount} đã giao'),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text('Danh sách đơn (kéo để sắp thứ tự)',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _addOrders(context, db, trip),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm đơn'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _local.isEmpty
                        ? const EmptyState(text: 'Chưa có đơn trong chuyến')
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _local.length,
                            onReorder: (oldI, newI) {
                              setState(() {
                                if (newI > oldI) newI--;
                                final o = _local.removeAt(oldI);
                                _local.insert(newI, o);
                              });
                            },
                            itemBuilder: (context, i) {
                              final o = _local[i];
                              return Card(
                                key: ValueKey(o.id),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  onTap: () => context.push('/orders/${o.id}'),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryLight,
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  title: Text(o.code,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      '${o.customerName}\n${money(o.total)}'),
                                  isThreeLine: true,
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      StatusChip(
                                          deliveryStatusUi(o.deliveryStatus),
                                          dense: true),
                                      const SizedBox(height: 4),
                                      const Icon(Icons.drag_handle,
                                          color: AppColors.textSecondary),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              bottomNavigationBar: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _local.isEmpty
                              ? null
                              : () async {
                                  await db.reorderTripSequences(
                                      trip.id, _local);
                                  if (context.mounted) {
                                    toast(context, 'Đã lưu thứ tự giao');
                                  }
                                },
                          child: const Text('Lưu thứ tự'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (trip.status == TripStatus.READY &&
                                  _local.isNotEmpty)
                              ? () => _depart(context, db, trip)
                              : null,
                          child: Text(trip.status == TripStatus.IN_PROGRESS
                              ? 'Đang giao'
                              : 'Xuất phát'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _depart(BuildContext context, Db db, Trip trip) async {
    final user = context.read<AuthProvider>().user!;
    final ok = await confirmDialog(context,
        title: 'Xuất phát',
        message:
            'Xác nhận xe xuất phát? Tất cả đơn trong chuyến sẽ chuyển sang "Đang giao".',
        confirm: 'Xuất phát');
    if (!ok) return;
    await db.reorderTripSequences(trip.id, _local);
    await db.departTrip(trip, user.id, user.name);
    if (context.mounted) toast(context, 'Chuyến ${trip.code} đã xuất phát');
  }

  Future<void> _addOrders(BuildContext context, Db db, Trip trip) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => StreamBuilder<List<Order>>(
          stream: db.ordersReadyForTrip(),
          builder: (context, snap) {
            final pool = snap.data ?? [];
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Đơn đã đóng hàng, chờ xếp chuyến',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: pool.isEmpty
                      ? const EmptyState(text: 'Không có đơn nào chờ xếp')
                      : ListView(
                          controller: scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final o in pool)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Avatar(o.customerName),
                                  title: Text(o.code,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      '${o.customerName}\n${o.deliveryAddress}'),
                                  isThreeLine: true,
                                  trailing: IconButton.filledTonal(
                                    icon: const Icon(Icons.add),
                                    onPressed: () async {
                                      try {
                                        await db.assignOrderToTrip(
                                            o, trip, _local.length + 1);
                                        if (context.mounted) {
                                          toast(context,
                                              'Đã thêm ${o.code} vào chuyến');
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          toast(context, '$e');
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
