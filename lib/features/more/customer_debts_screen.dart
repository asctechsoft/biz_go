import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../models/order.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Cài đặt › Công nợ — tổng hợp khách còn nợ tiền, xếp theo số nợ giảm dần.
///
/// Chỉ tính **đơn đã giao thành công** (`DeliveryStatus.DELIVERED`) mà còn
/// `remaining > 0`: đơn chưa giao thì khách chưa cầm hàng, chưa tính là nợ ở
/// đây — khác với `Customer.debt` (cộng dồn ngay lúc TẠO đơn, dùng cho sổ
/// công nợ tổng + "Thu công nợ" ở màn chi tiết khách), nên số ở màn này có
/// thể thấp hơn `Customer.debt` của cùng một khách.
class CustomerDebtsScreen extends StatefulWidget {
  const CustomerDebtsScreen({super.key});

  @override
  State<CustomerDebtsScreen> createState() => _CustomerDebtsScreenState();
}

class _CustomerDebtsScreenState extends State<CustomerDebtsScreen> {
  String _q = '';

  // Giữ stream trong State, KHÔNG gọi db.allOrders()/db.customers() thẳng
  // trong build — mỗi lần gõ ô tìm kiếm là build lại, gọi trong build thì
  // StreamBuilder huỷ listener cũ nghe lại từ đầu (xem customers_screen.dart).
  Stream<List<Order>>? _ordersStream;
  Stream<List<Customer>>? _customersStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = context.read<Db>();
    _ordersStream ??= db.allOrders();
    _customersStream ??= db.customers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Công nợ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm khách nợ theo tên hoặc SĐT...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            // allOrders() (không giới hạn 30 ngày) — nợ có thể phát sinh từ
            // đơn cũ hơn nhiều so với cửa sổ mặc định của danh sách đơn hàng.
            child: StreamBuilder<List<Order>>(
              stream: _ordersStream,
              builder: (context, osnap) {
                if (!osnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final debtOrders = osnap.data!
                    .where(
                      (o) =>
                          o.deliveryStatus == DeliveryStatus.DELIVERED &&
                          o.orderStatus != OrderStatus.CANCELLED &&
                          o.remaining > 0,
                    )
                    .toList();

                return StreamBuilder<List<Customer>>(
                  stream: _customersStream,
                  builder: (context, csnap) {
                    // Lấy tên/SĐT/ảnh HIỆN TẠI của khách (đổi SĐT sau khi đặt
                    // đơn thì vẫn gọi đúng số mới) — rơi về bản snapshot trên
                    // đơn nếu vì lý do gì đó không tìm thấy hồ sơ khách.
                    final customers = {
                      for (final c in csnap.data ?? const <Customer>[])
                        c.id: c,
                    };

                    final byCustomer = <String, List<Order>>{};
                    for (final o in debtOrders) {
                      (byCustomer[o.customerId] ??= []).add(o);
                    }
                    final allRows = byCustomer.entries.map((e) {
                      final orders = e.value
                        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                      final c = customers[e.key];
                      return _Debtor(
                        customerId: e.key,
                        name: c?.name ?? orders.first.customerName,
                        phone: c?.phone ?? orders.first.customerPhone,
                        imagePath: c?.imagePath,
                        orders: orders,
                      );
                    }).toList()..sort((a, b) => b.debt.compareTo(a.debt));

                    if (allRows.isEmpty) {
                      return const EmptyState(
                        icon: Icons.check_circle_outline,
                        text: 'Không có khách nào đang nợ tiền đơn đã giao.',
                      );
                    }

                    final rows = _q.isEmpty
                        ? allRows
                        : allRows
                            .where(
                              (r) =>
                                  r.name.toLowerCase().contains(_q) ||
                                  r.phone.contains(_q),
                            )
                            .toList();

                    if (rows.isEmpty) {
                      return const EmptyState(
                        icon: Icons.search_off,
                        text: 'Không tìm thấy khách nợ phù hợp.',
                      );
                    }

                    final totalDebt = rows.fold<int>(0, (s, r) => s + r.debt);

                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        24 + MediaQuery.of(context).padding.bottom,
                      ),
                      children: [
                        SectionCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tổng công nợ',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      money(totalDebt),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${rows.length} khách đang nợ',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final r in rows)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () =>
                                  context.push('/customers/${r.customerId}'),
                              leading: Avatar(r.name, imagePath: r.imagePath),
                              title: Text(
                                r.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(r.subtitle),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    money(r.debt),
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (r.phone.isNotEmpty)
                                    InkWell(
                                      onTap: () => callPhone(context, r.phone),
                                      borderRadius: BorderRadius.circular(20),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(
                                          Icons.call,
                                          color: AppColors.success,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Debtor {
  final String customerId;
  final String name;
  final String phone;
  final String? imagePath;
  final List<Order> orders;

  _Debtor({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.imagePath,
    required this.orders,
  });

  int get debt => orders.fold<int>(0, (s, o) => s + o.remaining);

  /// "2 đơn chưa thanh toán · 1 đơn thanh toán 1 phần" — để admin biết ngay
  /// khách nào trắng tay, khách nào đã trả một phần mà không phải bấm vào
  /// từng đơn.
  String get subtitle {
    final unpaid = orders.where((o) => o.paidAmount == 0).length;
    final partial = orders.length - unpaid;
    final parts = <String>[
      if (unpaid > 0) '$unpaid đơn chưa thanh toán',
      if (partial > 0) '$partial đơn thanh toán 1 phần',
    ];
    return parts.join(' · ');
  }
}
