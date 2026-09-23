import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import 'order_tile.dart';

/// Tìm đơn theo mã đơn / tên khách / SĐT khách — thay cho màn Lọc nhanh đã bỏ
/// (đơn ngày càng nhiều, lọc theo tiêu chí không còn đủ, cần gõ thẳng ra).
///
/// Cùng bộ tab trạng thái với màn Đơn hàng (Tất cả/Chờ xử lý/Đang giao/Đã
/// giao) để gõ xong vẫn biết đơn thuộc nhóm nào — xem [isOrderPending] /
/// [isOrderDelivering] / [isOrderDone].
class OrderSearchScreen extends StatefulWidget {
  const OrderSearchScreen({super.key});
  @override
  State<OrderSearchScreen> createState() => _OrderSearchScreenState();
}

class _OrderSearchScreenState extends State<OrderSearchScreen> {
  final _queryCtrl = TextEditingController();
  List<String> _tokens = const [];

  /// Rộng hơn cửa sổ mặc định của màn Đơn hàng — tìm kiếm thường nhắm tới
  /// đơn cũ hơn là đơn hôm nay. Bấm "Tìm xa hơn" cộng dồn khi chưa đủ.
  int _days = 90;

  bool get _showMoney {
    final role = context.read<AuthProvider>().user?.role;
    return role != null && Perm.viewMoney(role);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  // Tách token để gõ thiếu thứ tự vẫn ra, kiểu "sam lan" khớp "K Sam Sung Lan".
  void _onChanged(String v) => setState(
    () => _tokens = searchKey(
      v,
    ).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList(),
  );

  bool _matches(Order o) {
    final key = searchKey('${o.code} ${o.customerName} ${o.customerPhone}');
    return _tokens.every(key.contains);
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _queryCtrl,
                autofocus: true,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: AppColors.primary,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 10,
                  ),

                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 12, right: 6),
                    child: Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  hintText: 'Nhập mã đơn hoặc tên khách...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary),
                  suffixIcon: _tokens.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            _queryCtrl.clear();
                            setState(() => _tokens = const []);
                          },
                        ),
                ),
                onChanged: _onChanged,
              ),
            ),
          ),
          bottom: const TabBar(
            isScrollable: false,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xCCFFFFFF),
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
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
          stream: db.orders(days: _days),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Chưa gõ gì thì `_matches` khớp hết (every trên list rỗng) — hiện
            // sẵn toàn bộ đơn, gõ vào mới lọc dần.
            final all = snap.data!.where(_matches).toList();
            return TabBarView(
              children: [
                _list(all),
                _list(all.where(isOrderPending).toList()),
                _list(all.where(isOrderDelivering).toList()),
                _list(all.where(isOrderDone).toList()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(List<Order> orders) {
    final showMoney = _showMoney;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        if (orders.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(text: 'Không tìm thấy đơn nào khớp'),
          )
        else
          for (final o in orders)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OrderTile(o: o, showMoney: showMoney),
            ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _days += 180),
            icon: const Icon(Icons.history),
            label: Text('Tìm xa hơn (đang xem $_days ngày gần nhất)'),
          ),
        ),
      ],
    );
  }
}
