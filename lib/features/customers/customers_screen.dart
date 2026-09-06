import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Khách hàng')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm khách hàng...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: db.customers(),
              builder: (context, snap) {
                if (snap.hasError) {
                  debugPrint('CUSTOMERS STREAM ERROR: ${snap.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        friendlyError(snap.error!,
                            fallback: 'Không tải được danh sách khách hàng.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!
                    .where((c) =>
                        c.name.toLowerCase().contains(_q) || c.phone.contains(_q))
                    .toList();
                if (items.isEmpty) {
                  return const EmptyState(text: 'Chưa có khách hàng');
                }
                return SlidableAutoCloseBehavior(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final tile = ListTile(
                        onTap: () => context.push('/customers/${c.id}'),
                        leading: Avatar(c.name, imagePath: c.imagePath),
                        title: Text(c.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone),
                        trailing: Text(
                          c.debt > 0 ? 'Nợ: ${money(c.debt)}' : 'Nợ: 0đ',
                          style: TextStyle(
                            color: c.debt > 0
                                ? AppColors.danger
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                      // Vuốt sang trái để xoá — đồng bộ với màn Quản lý
                      // người dùng.
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Slidable(
                          key: ValueKey(c.id),
                          groupTag: 'customers',
                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            extentRatio: 0.28, // hé lộ ~1/4, không dismiss hết
                            children: [
                              SlidableAction(
                                onPressed: (ctx) => _delete(ctx, db, c),
                                backgroundColor: AppColors.danger,
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Xóa',
                              ),
                            ],
                          ),
                          child: Material(
                            color: AppColors.card,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(12),
                                ),
                              ),
                              child: tile,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/customers/new'),
                icon: const Icon(Icons.add),
                label: const Text('Thêm khách hàng'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Xoá khách (vuốt sang trái). Còn nợ thì từ chối và nói rõ lý do — chặn ở
  /// đây cho phản hồi nhanh, `Db.deleteCustomer` vẫn chặn lần nữa ở tầng dưới.
  ///
  /// [slideCtx] là context của `SlidableAction` — widget đó nằm TRONG action
  /// pane, pane đóng lại là nó bị gỡ khỏi cây và `slideCtx.mounted` thành
  /// false. Nên chỉ dùng nó để đóng pane; mọi thứ sau `await` phải dùng
  /// `context` của State (ổn định suốt vòng đời màn hình).
  Future<void> _delete(BuildContext slideCtx, Db db, Customer c) async {
    Slidable.of(slideCtx)?.close();
    if (c.debt > 0) {
      toast(context,
          'Khách còn nợ ${money(c.debt)}. Thu hết nợ rồi mới xoá được.');
      return;
    }
    final me = context.read<AuthProvider>().user;
    final ok = await confirmDialog(
      context,
      title: 'Xóa khách hàng',
      message: 'Xóa "${c.name}" (${c.phone})?\n'
          '${c.orderCount > 0 ? '${c.orderCount} đơn cũ vẫn được giữ nguyên. ' : ''}'
          'Không thể hoàn tác.',
      confirm: 'Xóa',
    );
    if (!ok || !mounted) return;

    // Xoá thẳng. Danh sách chạy bằng stream nên doc mất là hàng tự biến mất —
    // không treo lệnh xoá vào animation của Slidable (`ResizeRequest`), vì
    // callback đó chỉ chạy khi animation ở đúng trạng thái `completed`
    // (dismissal.dart:61), lệch một nhịp là nó im lặng bỏ qua.
    //
    // Báo kết quả THẬT: `Db.deleteCustomer` còn chặn nợ lần nữa, nên không
    // được toast "Đã xoá" trước rồi mới biết là hỏng.
    try {
      await db.deleteCustomer(
        c.id,
        actorId: me?.id ?? '',
        actorName: me?.name ?? '',
      );
      if (mounted) toast(context, 'Đã xóa khách hàng ${c.name}');
    } catch (e) {
      debugPrint('DELETE-CUSTOMER ERROR: $e');
      if (mounted) {
        toast(
          context,
          friendlyError(e,
              fallback: 'Xoá khách hàng không thành công. Thử lại giúp tôi.'),
        );
      }
    }
  }
}
