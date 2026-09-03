import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final role = user?.role;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary,
                  Color(0xFF2E9E5B),
                  Color(0xFF3A7BD6),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Cài đặt',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Avatar(user?.name ?? '?', size: 50),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${user?.role.label ?? ''} · ${user?.phone ?? ''}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (role != null && Perm.manageCustomers(role))
            _tile(
              context,
              Icons.people_alt_outlined,
              'Khách hàng',
              '/customers',
            ),
          if (role != null && Perm.editCatalog(role))
            _tile(
              context,
              Icons.shopping_bag_outlined,
              'Sản phẩm & bảng giá',
              '/products',
            ),
          if (role != null && Perm.warehouseOps(role))
            _tile(
              context,
              Icons.inventory_2_outlined,
              'Kho & đóng hàng',
              '/warehouse',
            ),
          if (role != null && Perm.dispatchOps(role))
            _tile(
              context,
              Icons.local_shipping_outlined,
              'Chuyến xe',
              '/delivery',
            ),
          if (role != null && Perm.manageUsers(role))
            _tile(
              context,
              Icons.manage_accounts_outlined,
              'Quản lý người dùng',
              '/users',
            ),
          if (role != null && Perm.manageFleet(role))
            _tile(
              context,
              Icons.directions_car_outlined,
              'Quản lý xe',
              '/fleet',
            ),
          if (role != null && Perm.viewReports(role))
            _tile(context, Icons.bar_chart, 'Báo cáo', '/reports'),
          if (role != null && Perm.viewAudit(role))
            _tile(context, Icons.history, 'Nhật ký hệ thống', '/audit'),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Phiên bản'),
            trailing: const Text('1.0.0'),
          ),
          if (role != null && Perm.owner(role))
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: AppColors.danger,
              ),
              title: const Text(
                'Xóa toàn bộ dữ liệu',
                style: TextStyle(color: AppColors.danger),
              ),
              subtitle: const Text('Đơn, khách, sản phẩm, chuyến, công nợ...'),
              onTap: () => _clearData(context),
            ),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text(
              'Đăng xuất',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () async {
              final ok = await confirmDialog(
                context,
                title: 'Đăng xuất',
                message: 'Bạn chắc chắn muốn đăng xuất?',
                confirm: 'Đăng xuất',
              );
              if (ok) await auth.signOut();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _clearData(BuildContext context) async {
    final db = context.read<Db>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      title: 'Xóa toàn bộ dữ liệu',
      message:
          'Xóa TẤT CẢ đơn hàng, khách, sản phẩm, chuyến, công nợ, nhật ký? '
          'KHÔNG THỂ hoàn tác. Tài khoản đăng nhập được giữ lại.',
      confirm: 'Xóa hết',
    );
    if (!ok) return;

    // Snackbar tiến trình (không push dialog → tránh khóa navigator).
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Đang xóa dữ liệu...'),
        duration: Duration(minutes: 1),
      ),
    );
    try {
      await db.clearAllData();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Đã xóa toàn bộ dữ liệu. Vào lại màn đăng nhập để tạo dữ liệu mẫu.',
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Lỗi xóa dữ liệu: $e')));
    }
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String route,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
