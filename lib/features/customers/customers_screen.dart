import 'dart:async';

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

  /// Stream giữ trong State, KHÔNG gọi `db.customers()` thẳng trong `build`.
  ///
  /// `db.customers()` tạo listener MỚI mỗi lần gọi. Đặt trong `build` thì mỗi
  /// lần gõ ô tìm kiếm (hay bất cứ rebuild nào) là StreamBuilder huỷ listener
  /// đang chờ rồi nghe lại từ đầu → về `hasData == false` → nhảy lại spinner.
  /// Máy mới cài chưa có cache Firestore, lần nghe đầu phải tải cả collection;
  /// cứ bị restart giữa đường là **quay mãi không xong**.
  Stream<List<Customer>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= context.read<Db>().customers();
  }

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
              stream: _stream,
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
                  // Không để spinner quay vô tận: chờ quá lâu thì nói thật là
                  // đang không tải được + cho nghe lại. Firestore listener bị
                  // kẹt (mạng chặn, đồng hồ máy sai, sóng yếu lúc tải lần đầu)
                  // KHÔNG bao giờ ném lỗi, nên `hasError` ở trên không bắt.
                  return _SlowLoading(
                    onRetry: () => setState(
                      () => _stream = context.read<Db>().customers(),
                    ),
                  );
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
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
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

/// Spinner "biết nói": quay bình thường lúc đầu, chờ quá [_patience] thì báo
/// là đang không tải được kèm nút Thử lại.
///
/// Cần thiết vì Firestore listener kẹt (mạng bị chặn, đồng hồ máy sai làm TLS
/// fail, sóng yếu lúc tải lần đầu khi máy mới cài chưa có cache) sẽ **im lặng
/// chờ mãi** — không có snapshot, cũng không có lỗi để `hasError` bắt.
class _SlowLoading extends StatefulWidget {
  final VoidCallback onRetry;
  const _SlowLoading({required this.onRetry});

  @override
  State<_SlowLoading> createState() => _SlowLoadingState();
}

class _SlowLoadingState extends State<_SlowLoading> {
  static const _patience = Duration(seconds: 10);
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_patience, () {
      debugPrint('CUSTOMERS: chưa có snapshot sau ${_patience.inSeconds}s '
          '— listener Firestore đang kẹt (mạng/đồng hồ máy/cache trống).');
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_slow) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text(
              'Chưa tải được danh sách khách hàng.\n'
              'Kiểm tra mạng của máy rồi thử lại.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _slow = false);
                widget.onRetry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
