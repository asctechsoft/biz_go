import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/fleet.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class DeliveryHubScreen extends StatelessWidget {
  const DeliveryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final user = context.watch<AuthProvider>().user;
    final isShipper = user?.role == UserRole.shipper;
    // Tài xế chỉ thấy chuyến được phân công (§22); Chủ thấy tất cả.
    final tripStream = isShipper && user != null
        ? db.tripsForDriver(user.id)
        : db.trips();
    return Scaffold(
      appBar: AppBar(
        title: Text(isShipper ? 'Chuyến của tôi' : 'Chuyến xe'),
        actions: [
          if (user != null && Perm.warehouseOps(user.role))
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Kho & đóng hàng',
              onPressed: () => context.push('/warehouse'),
            ),
        ],
      ),
      body: StreamBuilder<List<Trip>>(
        stream: tripStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final trips = snap.data!;
          if (trips.isEmpty) {
            return const EmptyState(
                icon: Icons.local_shipping_outlined,
                text: 'Chưa có chuyến xe');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: trips.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final t = trips[i];
              final ui = tripStatusUi(t.status);
              return Card(
                child: ListTile(
                  onTap: () => context.push('/trips/${t.id}'),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: const Icon(Icons.local_shipping,
                        color: AppColors.primary),
                  ),
                  title: Text(t.code,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${t.vehiclePlate} · ${t.driverName}\n${fmtDate(t.runDate)} · ${t.deliveredCount}/${t.orderCount} đơn'),
                  isThreeLine: true,
                  trailing: StatusChip(ui, dense: true),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isShipper
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              onPressed: () => context.push('/trips/new'),
              icon: const Icon(Icons.add, color: Colors.white),
              label:
                  const Text('Tạo chuyến', style: TextStyle(color: Colors.white)),
            ),
    );
  }
}
