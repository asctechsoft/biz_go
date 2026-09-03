import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/permissions.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _all = [
    ('/dashboard', Icons.home_outlined, Icons.home, 'Tổng quan'),
    ('/orders', Icons.receipt_long_outlined, Icons.receipt_long, 'Đơn hàng'),
    ('/delivery', Icons.local_shipping_outlined, Icons.local_shipping, 'Giao hàng'),
    ('/more', Icons.settings_outlined, Icons.settings, 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    final allowed = role == null ? const <String>[] : Perm.tabs(role);
    // Chỉ giữ tab được phép, theo đúng thứ tự gốc.
    final tabs = _all.where((t) => allowed.contains(t.$1)).toList();
    if (tabs.isEmpty) return Scaffold(body: child);

    final loc = GoRouterState.of(context).uri.path;
    var index = tabs.indexWhere((t) => loc.startsWith(t.$1));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: i == index ? tabs[i].$3 : tabs[i].$2,
                      label: tabs[i].$4,
                      active: i == index,
                      onTap: () => context.go(tabs[i].$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một ô tab — bấm cả vùng, active đổi màu icon + chữ và có card nền.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
