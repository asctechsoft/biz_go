import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_notification.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _icons = <String, (IconData, Color)>{
    'new': (Icons.fiber_new, AppColors.danger),
    'box': (Icons.inventory_2, AppColors.info),
    'truck': (Icons.local_shipping, AppColors.warning),
    'depart': (Icons.rocket_launch, AppColors.info),
    'success': (Icons.check_circle, AppColors.success),
    'fail': (Icons.error, AppColors.danger),
    'debt': (Icons.account_balance_wallet, AppColors.danger),
    'bell': (Icons.notifications, AppColors.primary),
  };

  void _open(BuildContext c, AppNotification n) {
    context_read(c).markNotifRead(n.id);
    switch (n.refType) {
      case NotifRefType.order:
        c.push('/orders/${n.refId}');
      case NotifRefType.trip:
        break; // legacy — chuyến xe đã bỏ, không còn màn để mở
      case NotifRefType.customer:
      case NotifRefType.debt:
        c.push('/customers/${n.refId}');
    }
  }

  Db context_read(BuildContext c) => c.read<Db>();

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final role = context.read<AuthProvider>().user!.role;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          TextButton(
            onPressed: () => db.markAllNotifsRead(role),
            child: const Text('Đánh dấu đã đọc',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: db.notifications(role),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const EmptyState(
                icon: Icons.notifications_off_outlined,
                text: 'Chưa có thông báo');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final n = items[i];
              final ic = _icons[n.icon] ?? _icons['bell']!;
              return Card(
                color: n.read ? Colors.white : AppColors.primaryLight,
                child: ListTile(
                  onTap: () => _open(context, n),
                  leading: CircleAvatar(
                    backgroundColor: ic.$2.withValues(alpha: 0.12),
                    child: Icon(ic.$1, color: ic.$2),
                  ),
                  title: Text(n.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(fmtDateTime(n.at),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
