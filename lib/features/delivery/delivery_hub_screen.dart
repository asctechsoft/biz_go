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
import 'delivery_actions.dart';

/// Màn Giao hàng — thay cho phân hệ chuyến xe cũ.
///
/// - **Chờ xuất phát:** đơn đã đóng hàng. Kiểm hàng/Chủ bấm đi từng đơn hoặc
///   "Xuất phát tất cả".
/// - **Đang giao:** cuối ngày Chủ đối soát — giao thành công (thu tiền) hoặc
///   không giao được.
/// - **Xong hôm nay:** đã chốt trong ngày, để soát lại cho yên tâm.
class DeliveryHubScreen extends StatelessWidget {
  const DeliveryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final user = context.watch<AuthProvider>().user;
    final role = user?.role;
    // Kiểm hàng vào được cả 3 tab (chỉ nút bấm mới bị chặn), nên tiền phải ẩn
    // theo VAI TRÒ chứ không theo "tab này ai thao tác".
    final showMoney = role != null && Perm.viewMoney(role);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Giao hàng'),
          actions: [
            if (role != null && Perm.warehouseOps(role))
              IconButton(
                icon: const Icon(Icons.inventory_2_outlined),
                tooltip: 'Kho & đóng hàng',
                onPressed: () => context.push('/warehouse'),
              ),
          ],
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
              Tab(text: 'Chờ xuất phát'),
              Tab(text: 'Đang giao'),
              Tab(text: 'Xong hôm nay'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _WaitingTab(
              db: db,
              canDepart: role != null && Perm.startDelivery(role),
              showMoney: showMoney,
            ),
            _DeliveringTab(
              db: db,
              canConfirm: role != null && Perm.confirmDelivery(role),
              showMoney: showMoney,
            ),
            _SettledTab(db: db, showMoney: showMoney),
          ],
        ),
      ),
    );
  }
}

// ------------------------- Chờ xuất phát -------------------------
class _WaitingTab extends StatelessWidget {
  final Db db;
  final bool canDepart;
  final bool showMoney;
  const _WaitingTab({
    required this.db,
    required this.canDepart,
    required this.showMoney,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: db.ordersWaitingDepart(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            text: 'Không có đơn nào chờ xuất phát',
          );
        }
        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _OrderCard(
                  order: orders[i],
                  showMoney: showMoney,
                  action: canDepart
                      ? _CardAction(
                          label: 'Xuất phát',
                          icon: Icons.local_shipping_outlined,
                          onTap: () => departOrder(context, orders[i]),
                        )
                      : null,
                ),
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
      },
    );
  }
}

// ------------------------- Đang giao (đối soát) -------------------------
class _DeliveringTab extends StatelessWidget {
  final Db db;
  final bool canConfirm;
  final bool showMoney;
  const _DeliveringTab({
    required this.db,
    required this.canConfirm,
    required this.showMoney,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: db.ordersDelivering(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            icon: Icons.local_shipping_outlined,
            text: 'Không có đơn nào đang giao',
          );
        }
        final totalCod = orders.fold<int>(
          0,
          (s, o) => s + (o.remaining > 0 ? o.remaining : 0),
        );
        return Column(
          children: [
            // Tổng tiền còn phải thu của cả lô — con số Chủ cần khi đối soát.
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('${orders.length} đơn đang giao',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (showMoney)
                    Text('Cần thu ${money(totalCod)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  return _OrderCard(
                    order: o,
                    showMoney: showMoney,
                    action: canConfirm
                        ? _CardAction(
                            label: 'Giao thành công',
                            icon: Icons.check_circle_outline,
                            onTap: () => deliverOrder(context, o),
                            secondaryLabel: 'Không giao được',
                            onSecondary: () => failOrder(context, o),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------- Xong hôm nay -------------------------
class _SettledTab extends StatelessWidget {
  final Db db;
  final bool showMoney;
  const _SettledTab({required this.db, required this.showMoney});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: db.ordersSettledOn(DateTime.now()),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const EmptyState(
            icon: Icons.check_circle_outline,
            text: 'Hôm nay chưa chốt đơn nào',
          );
        }
        final collected = orders
            .where((o) => o.deliveryStatus == DeliveryStatus.DELIVERED)
            .fold<int>(0, (s, o) => s + o.paidAmount);
        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text('${orders.length} đơn đã chốt',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (showMoney)
                    Text('Đã thu ${money(collected)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.success)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _OrderCard(order: orders[i], showMoney: showMoney),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------- Thẻ đơn dùng chung -------------------------
class _CardAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  const _CardAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.secondaryLabel,
    this.onSecondary,
  });
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final _CardAction? action;

  /// Ẩn hết tiền khi người xem không phải Chủ (tab "Chờ xuất phát" có Kiểm
  /// hàng vào). Hai tab còn lại chỉ Chủ dùng nên luôn true.
  final bool showMoney;
  const _OrderCard({
    required this.order,
    required this.showMoney,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Card(
      child: InkWell(
        onTap: () => context.push('/orders/${o.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (o.priority) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text('GẤP',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(o.code,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  // Giờ dự kiến xuất phát — chính là thứ quyết định vị trí của
                  // đơn trong danh sách này, nên phải nhìn thấy được.
                  if (o.plannedDepartAt != null) ...[
                    const Icon(Icons.schedule,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text(fmtDepartAt(o.plannedDepartAt),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                    const SizedBox(width: 8),
                  ],
                  StatusChip(deliveryStatusUi(o.deliveryStatus), dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(o.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(o.deliveryAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
              // Gửi qua nhà xe: người đi giao cần biết giao cho nhà xe nào.
              if (o.hasCarrier)
                Text(
                    'Nhà xe: ${o.deliveryCarrierName}'
                    '${o.deliveryCarrierPhone.isEmpty ? '' : ' · ${o.deliveryCarrierPhone}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Bọc Flexible + ellipsis: đơn vài chục triệu là hai cụm số
                  // này đủ dài để tràn ngang trên máy màn nhỏ.
                  if (showMoney) ...[
                    Flexible(
                      child: Text(money(o.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: o.remaining > 0
                          ? Text('Cần thu ${money(o.remaining)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600))
                          : const Text('Đã thanh toán đủ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ] else
                    Text('${o.items.length} mặt hàng',
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  const Spacer(),
                  InkWell(
                    onTap: () => openMap(context,
                        mapUrl: o.deliveryMapUrl, address: o.deliveryAddress),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.navigation_outlined,
                          size: 20, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              if (action != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (action!.secondaryLabel != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: action!.onSecondary,
                          child: Text(action!.secondaryLabel!,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    if (action!.secondaryLabel != null)
                      const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: action!.onTap,
                        icon: Icon(action!.icon, size: 18),
                        label: Text(action!.label,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
