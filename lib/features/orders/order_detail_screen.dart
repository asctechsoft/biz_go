import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';
import '../delivery/delivery_actions.dart';
import 'create/create_order_screen.dart';
import 'invoice_screen.dart';
import 'payment_sheet.dart';

class OrderDetailScreen extends StatelessWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<Order?>(
      stream: db.order(orderId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Đơn bị xoá trong lúc màn này đang mở, hoặc mở từ thông báo cũ.
        final order = snap.data;
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Đơn hàng')),
            body: const EmptyState(
              icon: Icons.delete_outline,
              text: 'Đơn này không còn tồn tại (đã bị xoá)',
            ),
          );
        }
        final o = order;
        // Kho chỉ được thấy mặt hàng + số lượng; mọi con số tiền ẩn hết.
        final role = context.watch<AuthProvider>().user?.role;
        final showMoney = role != null && Perm.viewMoney(role);
        return Scaffold(
          appBar: AppBar(
            title: Text(o.code),
            actions: [
              Builder(
                builder: (context) {
                  final role = context.read<AuthProvider>().user?.role;
                  final items = <PopupMenuEntry<String>>[
                    if (role != null && Perm.createOrder(role))
                      // GẤP là thao tác "đổi mức ưu tiên" nên cho nổi hẳn:
                      // nền đỏ nhạt + icon lửa, lướt mắt là thấy.
                      _menuItem(
                        value: 'priority',
                        icon: o.priority
                            ? Icons.local_fire_department_outlined
                            : Icons.local_fire_department,
                        label: o.priority ? 'Bỏ đánh dấu GẤP' : 'Đánh dấu GẤP',
                        color: AppColors.danger,
                        highlight: !o.priority,
                      ),
                    // Đổi giờ chỉ có nghĩa khi đơn chưa đi — đã lên đường thì
                    // `Db.setPlannedDepart` cũng từ chối.
                    if (role != null &&
                        Perm.startDelivery(role) &&
                        _canPlanDepart(o))
                      _menuItem(
                        value: 'depart-time',
                        icon: Icons.schedule,
                        label: o.plannedDepartAt == null
                            ? 'Đặt giờ xuất phát'
                            : 'Đổi giờ xuất phát',
                      ),
                    if (role != null && Perm.printInvoice(role)) ...[
                      _menuItem(
                        value: 'print',
                        icon: Icons.print_outlined,
                        label: 'In phiếu',
                      ),
                      _menuItem(
                        value: 'pdf',
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Tải PDF',
                      ),
                    ],
                    if (role != null &&
                        Perm.editOrder(role) &&
                        _canEditOrder(o))
                      _menuItem(
                        value: 'edit',
                        icon: Icons.edit_outlined,
                        label: 'Sửa đơn',
                      ),
                    // Hủy / Xoá tách hẳn xuống dưới gạch ngang — thao tác
                    // không hoàn tác được, đừng để nằm sát nút bấm hằng ngày.
                    if (role != null && Perm.cancelOrder(role)) ...[
                      const PopupMenuDivider(height: 8),
                      _menuItem(
                        value: 'cancel',
                        icon: Icons.cancel_outlined,
                        label: 'Hủy đơn',
                        color: AppColors.danger,
                      ),
                    ],
                    // Chỉ hiện khi đơn còn nguyên si (chưa ai đụng, chưa thu
                    // tiền) — xem `Db.canDelete`. Đơn đã vào quy trình thì
                    // phải "Hủy đơn" để còn giữ dấu vết.
                    if (role != null &&
                        Perm.deleteOrder(role) &&
                        Db.canDelete(o))
                      _menuItem(
                        value: 'delete',
                        icon: Icons.delete_outline,
                        label: 'Xoá đơn (tạo nhầm)',
                        color: AppColors.danger,
                      ),
                  ];
                  if (items.isEmpty) return const SizedBox.shrink();
                  return PopupMenuButton<String>(
                    // Mặc định menu bung đè lên chính nút bấm, che mất header.
                    // `under` đẩy nó xuống dưới AppBar.
                    position: PopupMenuPosition.under,
                    tooltip: 'Thao tác khác',
                    color: Colors.white,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (v) => _onMenu(context, db, o, v),
                    itemBuilder: (_) => items,
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Stepper(order: o),
              const SizedBox(height: 16),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (o.priority &&
                            o.orderStatus != OrderStatus.CANCELLED) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'GẤP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        StatusChip(orderStatusUi(o.orderStatus), dense: true),
                        if (showMoney) ...[
                          const SizedBox(width: 6),
                          StatusChip(
                            paymentStatusUi(o.paymentStatus),
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 20),
                    KVRow('Khách hàng', o.customerName),
                    KVRow('SĐT', o.customerPhone),
                    KVRow('Địa chỉ giao', o.deliveryAddress),
                    if (o.hasCarrier) ...[
                      KVRow('Nhà xe', o.deliveryCarrierName, bold: true),
                      if (o.deliveryCarrierPhone.isNotEmpty)
                        KVRow('SĐT nhà xe', o.deliveryCarrierPhone),
                    ],
                    if (o.plannedDepartAt != null)
                      KVRow(
                        'Giờ xuất phát dự kiến',
                        fmtDateTime(o.plannedDepartAt),
                      ),
                    // Dặn dò gắn với địa chỉ, snapshot lúc tạo đơn.
                    if (o.deliveryAddressNote.isNotEmpty)
                      KVRow('Lưu ý địa chỉ', o.deliveryAddressNote),
                    if (o.deliveryNote.isNotEmpty)
                      KVRow('Ghi chú giao', o.deliveryNote),
                    // Ghi chú nội bộ trước giờ gõ xong không hiện ở đâu cả.
                    // Chỉ Chủ đọc — có thể ghi chuyện giá cả, mặc cả.
                    if (showMoney && o.note.isNotEmpty)
                      KVRow('Ghi chú nội bộ', o.note),
                    if (o.packageCode != null)
                      KVRow('Mã kiện', o.packageCode!)
                    else if (o.packageCount != null)
                      KVRow('Số kiện', '${o.packageCount}'), // đơn đóng cũ
                    if (o.weightKg != null)
                      KVRow('Khối lượng', fmtWeight(o.weightKg, o.weightUnit)),
                    if (o.deliveryMapUrl.isNotEmpty ||
                        o.deliveryAddress.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openMap(
                            context,
                            mapUrl: o.deliveryMapUrl,
                            address: o.deliveryAddress,
                          ),
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('Mở chỉ đường'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sản phẩm',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final it in o.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // **Phân loại** làm tiêu đề (đậm) — đó là
                                  // thứ phân biệt các dòng. Bỏ dòng "sản phẩm
                                  // + quy cách" cũ vì mọi dòng đều giống nhau
                                  // ("Cùi Bưởi 1kg"), đọc không ra dòng nào là
                                  // dòng nào. Quy cách dồn xuống dòng dưới.
                                  Text(
                                    it.variantLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    showMoney
                                        ? '${it.packagingName} · ${money(it.unitPrice)} × ${it.quantity}'
                                        : '${it.packagingName} · Số lượng: ${it.quantity}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (showMoney) ...[
                              const SizedBox(width: 12),
                              Text(
                                money(it.lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (showMoney) ...[
                      const Divider(),
                      KVRow('Tổng cộng', money(o.total), bold: true),
                    ],
                  ],
                ),
              ),
              if (showMoney) ...[
                const SizedBox(height: 12),
                _PaymentCard(order: o),
              ],
              const SizedBox(height: 12),
              _TimelineCard(order: o),
              const SizedBox(height: 80),
            ],
          ),
          bottomNavigationBar: _ActionBar(order: o),
        );
      },
    );
  }

  Future<void> _onMenu(BuildContext context, Db db, Order o, String v) async {
    final user = context.read<AuthProvider>().user!;
    final canSeeMoney = Perm.viewMoney(user.role);
    if (v == 'print') {
      // Màn phiếu tự đọc `ShopInfo.hidePrices` để quyết mặc định in giá hay
      // không, và có nút lật cho riêng lần in — ở đây chỉ truyền quyền xem.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceScreen(order: o, canSeeMoney: canSeeMoney),
        ),
      );
    } else if (v == 'priority') {
      final on = !o.priority;
      await db.setOrderPriority(o, on, actorId: user.id, actorName: user.name);
      if (context.mounted) {
        toast(context, on ? 'Đã đánh dấu đơn GẤP' : 'Đã bỏ đánh dấu GẤP');
      }
    } else if (v == 'pdf') {
      // Lấy tiêu đề + SĐT hiện hành để phiếu PDF khớp với bản xem trước.
      final shop = await db.shopInfo().first;
      if (context.mounted) {
        // Tải thẳng từ menu thì theo đúng mặc định trong Cài đặt phiếu.
        await downloadInvoicePdf(
          context,
          o,
          shop,
          showMoney: canSeeMoney && !shop.hidePrices,
        );
      }
    } else if (v == 'delete') {
      await _deleteOrder(context, db, o, user);
    } else if (v == 'edit') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreateOrderScreen(editing: o)),
      );
    } else if (v == 'depart-time') {
      await _pickDepartTime(context, db, o, user);
    } else if (v == 'cancel') {
      final reason = await askReason(context, 'Lý do hủy đơn');
      if (reason != null) {
        await db.cancelOrder(o, reason, user.name, actorId: user.id);
        if (context.mounted) toast(context, 'Đã hủy đơn');
      }
    }
  }
}

/// Xoá hẳn đơn tạo nhầm, sau khi hỏi lại thật rõ là không hoàn tác được.
Future<void> _deleteOrder(
    BuildContext context, Db db, Order o, AppUser user) async {
  final ok = await confirmDialog(
    context,
    title: 'Xoá đơn ${o.code}?',
    message: 'Đơn sẽ bị xoá HẲN khỏi hệ thống, KHÔNG thể hoàn tác. '
        'Chỉ dùng khi tạo nhầm. Nếu đơn có thật mà không giao nữa thì chọn '
        '"Hủy đơn" để giữ lại dấu vết.',
    confirm: 'Xoá hẳn',
  );
  if (!ok || !context.mounted) return;

  // Giữ sẵn navigator + messenger TRƯỚC khi await. Xoá xong là stream đơn bắn
  // `null`, màn chi tiết dựng lại thành màn "đơn không còn" → element cũ bị gỡ,
  // `context.mounted` thành false và MỌI lệnh sau await bị bỏ qua. Đó chính là
  // lý do trước đây kẹt lại ở màn rỗng, không toast, không quay về.
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String msg) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Đang xoá đơn...'),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    await db.deleteOrder(o, actorId: user.id, actorName: user.name);
    nav.pop(); // đóng hộp loading
    nav.pop(); // rời màn chi tiết → về đúng danh sách đơn vừa đứng
    say('Đã xoá đơn ${o.code}');
  } catch (e) {
    debugPrint('DELETE-ORDER ERROR: $e');
    nav.pop(); // đóng hộp loading, giữ nguyên màn chi tiết
    say(friendlyError(e, fallback: 'Không xoá được đơn. Thử lại giúp tôi.'));
  }
}

/// Một dòng trong menu ⋮ của đơn: icon + chữ, màu theo mức độ.
///
/// [highlight] tô nền nhạt cho dòng cần bật lên (Đánh dấu GẤP) — menu toàn
/// chữ đen như nhau thì thao tác quan trọng chìm nghỉm.
PopupMenuItem<String> _menuItem({
  required String value,
  required IconData icon,
  required String label,
  Color color = AppColors.textPrimary,
  bool highlight = false,
}) {
  return PopupMenuItem<String>(
    value: value,
    height: 46,
    padding: EdgeInsets.zero,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: highlight
          ? BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            )
          : null,
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Đơn còn sửa được: chưa hủy và **chưa xuất phát**. Đã lên đường rồi mà đổi
/// mặt hàng là lệch với hàng thật đang trên xe — `Db.editOrder` cũng từ chối.
bool _canEditOrder(Order o) => _canPlanDepart(o);

/// Đơn còn ở hàng đợi (chưa lên đường) thì mới đặt/đổi được giờ dự kiến.
bool _canPlanDepart(Order o) =>
    o.orderStatus != OrderStatus.CANCELLED &&
    (o.deliveryStatus == DeliveryStatus.WAITING_ASSIGNMENT ||
        o.deliveryStatus == DeliveryStatus.ASSIGNED ||
        o.deliveryStatus == DeliveryStatus.LOADING ||
        o.deliveryStatus == DeliveryStatus.RESCHEDULED);

/// Đặt / đổi giờ xuất phát dự kiến của đơn.
Future<void> _pickDepartTime(
  BuildContext context,
  Db db,
  Order o,
  AppUser user,
) async {
  final picked = await pickDateTime(
    context,
    initial: o.plannedDepartAt,
    helpText: 'Giờ xuất phát dự kiến',
  );
  if (picked == null || !context.mounted) return;
  try {
    await db.setPlannedDepart(
      o,
      picked,
      actorId: user.id,
      actorName: user.name,
    );
    if (context.mounted) {
      toast(context, 'Đã đặt giờ xuất phát ${fmtDateTime(picked)}');
    }
  } catch (e) {
    debugPrint('SET-PLANNED-DEPART ERROR: $e');
    if (context.mounted) {
      toast(
        context,
        friendlyError(e, fallback: 'Không đặt được giờ xuất phát.'),
      );
    }
  }
}

class _Stepper extends StatelessWidget {
  final Order order;
  const _Stepper({required this.order});

  int get _stage {
    final o = order;
    if (o.deliveryStatus == DeliveryStatus.DELIVERED) return 4;
    // Đã rời kho (kể cả trạng thái legacy của luồng chuyến xe cũ).
    if (o.deliveryStatus.index >= DeliveryStatus.ASSIGNED.index &&
        o.deliveryStatus != DeliveryStatus.WAITING_ASSIGNMENT)
      return 3;
    if (o.warehouseStatus == WarehouseStatus.PACKED) return 2;
    if (o.warehouseStatus == WarehouseStatus.PREPARING ||
        o.warehouseStatus == WarehouseStatus.PREPARED ||
        o.warehouseStatus == WarehouseStatus.PACKING)
      return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Mới tạo',
      'Chuẩn bị',
      'Đóng hàng',
      'Giao hàng',
      'Hoàn thành',
    ];
    final stage = _stage;
    return SectionCard(
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: i <= stage
                      ? AppColors.primary
                      : AppColors.border,
                  child: Icon(
                    i <= stage ? Icons.check : Icons.circle,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: i < stage ? AppColors.primary : AppColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final Order order;
  const _PaymentCard({required this.order});
  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          KVRow('Tổng tiền', money(order.total)),
          KVRow('Đã trả trước', money(order.prepaid)),
          KVRow(
            'Đã thu',
            money(order.paidAmount),
            valueColor: AppColors.success,
          ),
          KVRow(
            'Còn thiếu',
            money(order.remaining > 0 ? order.remaining : 0),
            valueColor: order.remaining > 0
                ? AppColors.danger
                : AppColors.textSecondary,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final Order order;
  const _TimelineCard({required this.order});
  @override
  Widget build(BuildContext context) {
    final events = [...order.timeline]..sort((a, b) => a.at.compareTo(b.at));
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lịch sử xử lý',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.radio_button_checked,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fmtTime(e.at)}  ${e.title}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (e.actorName.isNotEmpty)
                          Text(
                            e.actorName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (e.note.isNotEmpty)
                          Text(
                            e.note,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Role/status-aware action buttons.
class _ActionBar extends StatelessWidget {
  final Order order;
  const _ActionBar({required this.order});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    final user = context.read<AuthProvider>().user!;
    final o = order;
    final actions = <Widget>[];

    void add(String label, VoidCallback onTap, {bool primary = true}) {
      actions.add(
        primary
            ? ElevatedButton(onPressed: onTap, child: Text(label))
            : OutlinedButton(onPressed: onTap, child: Text(label)),
      );
    }

    if (o.orderStatus == OrderStatus.CANCELLED) {
      return const SizedBox.shrink();
    }
    final role = user.role;

    // Warehouse flow — Kiểm hàng / Chủ.
    if (Perm.warehouseOps(role)) {
      if (o.warehouseStatus == WarehouseStatus.WAITING) {
        add('Bắt đầu chuẩn bị', () => db.startPreparing(o, user.id, user.name));
      } else if (o.warehouseStatus == WarehouseStatus.PREPARING) {
        add('Đã chuẩn bị xong', () => db.markPrepared(o, user.id, user.name));
      } else if (o.warehouseStatus == WarehouseStatus.PREPARED) {
        add('Bắt đầu đóng hàng', () => db.startPacking(o, user.id, user.name));
      } else if (o.warehouseStatus == WarehouseStatus.PACKING) {
        add(
          'Đóng hàng xong',
          () => _packDialog(context, db, o, user.id, user.name),
        );
      }
    }

    // Đóng hàng xong → cho đi. Chủ + Kiểm hàng (KHÔNG còn bước xếp chuyến).
    const waitingDepart = {
      DeliveryStatus.WAITING_ASSIGNMENT,
      DeliveryStatus.ASSIGNED, // legacy
      DeliveryStatus.LOADING, // legacy
      DeliveryStatus.RESCHEDULED,
    };
    if (Perm.startDelivery(role) &&
        o.warehouseStatus == WarehouseStatus.PACKED &&
        waitingDepart.contains(o.deliveryStatus)) {
      add('Xuất phát', () => departOrder(context, o));
    }

    // Đối soát cuối ngày — CHỈ Chủ.
    if (Perm.confirmDelivery(role) &&
        (o.deliveryStatus == DeliveryStatus.ON_THE_WAY ||
            o.deliveryStatus == DeliveryStatus.ARRIVED)) {
      add(
        'Giao thành công',
        () => deliverOrder(context, o, onDone: () => Navigator.pop(context)),
      );
      add('Không giao được', () => failOrder(context, o), primary: false);
    }

    // Thu công nợ còn lại — chỉ Chủ.
    // KHÔNG thu khi đơn đã hủy hoặc giao không thành công (FAILED/RETURNED —
    // hàng hoàn, khách chưa nhận).
    const noCollect = {DeliveryStatus.FAILED, DeliveryStatus.RETURNED};
    if (Perm.collectPayment(role) &&
        o.remaining > 0 &&
        o.orderStatus != OrderStatus.CANCELLED &&
        !noCollect.contains(o.deliveryStatus)) {
      add(
        'Thu tiền',
        () => _collectFlow(context, db, o, user.id, user.name),
        primary: o.warehouseStatus == WarehouseStatus.WAITING ? false : true,
      );
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in actions) SizedBox(width: double.infinity, child: a),
          ],
        ),
      ),
    );
  }

  Future<void> _packDialog(
    BuildContext context,
    Db db,
    Order o,
    String uid,
    String uname,
  ) async {
    // Mã kiện cấp trước để hiện sẵn trong dialog. Lỗi mạng thì để null →
    // markPacked tự cấp lúc lưu.
    String? code;
    try {
      code = await db.nextPackageCode();
    } catch (_) {
      code = null;
    }
    if (!context.mounted) return;

    final weightC = TextEditingController();
    final noteC = TextEditingController();
    String unit = 'kg';
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Đóng hàng xong'),
          // Bàn phím số bật lên ăn hơn nửa màn hình → dialog bị bóp lại và tràn
          // đáy ("BOTTOM OVERFLOWED BY 25 PIXELS"), rõ nhất khi hiện thêm dòng
          // báo lỗi đỏ. Cho nội dung cuộn được thì cao bao nhiêu cũng chịu.
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mã kiện tự sinh — chỉ đọc, không cho sửa.
                  TextField(
                    enabled: false,
                    controller: TextEditingController(
                      text: code ?? 'Sẽ tạo khi lưu',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Mã kiện (tự động)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weightC,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      if (error != null) setDlg(() => error = null);
                    },
                    decoration: const InputDecoration(labelText: 'Khối lượng'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Đơn vị',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final u in weightUnits.keys)
                        ChoiceChip(
                          label: Text(u),
                          selected: unit == u,
                          onSelected: (_) => setDlg(() => unit = u),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteC,
                    decoration: const InputDecoration(labelText: 'Ghi chú'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: () {
                if (_parseWeight(weightC.text) == null) {
                  setDlg(() => error = 'Nhập khối lượng lớn hơn 0');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      // Quy về kg trước khi lưu (Firestore luôn giữ kg).
      final value = _parseWeight(weightC.text)!;
      await db.markPacked(
        o,
        uid,
        uname,
        code: code,
        weightKg: value * weightUnits[unit]!.toDouble(),
        weightUnit: unit,
        note: noteC.text.trim(),
      );
      if (context.mounted) toast(context, 'Đã đóng hàng, chờ xuất phát');
    }
  }

  /// Khối lượng người dùng nhập — nhận cả dấu phẩy kiểu VN ("1,5"), trả về
  /// null nếu không hợp lệ hoặc <= 0.
  static double? _parseWeight(String s) {
    final v = double.tryParse(s.trim().replaceAll(',', '.'));
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> _collectFlow(
    BuildContext context,
    Db db,
    Order o,
    String uid,
    String uname,
  ) async {
    final result = await showPaymentSheet(context, o);
    if (result == null || result.amount <= 0) return;
    await db.recordPayment(
      order: o,
      amount: result.amount,
      method: result.method,
      actorId: uid,
      actorName: uname,
      note: result.note,
    );
    if (context.mounted) toast(context, 'Đã ghi nhận thu tiền');
  }
}
