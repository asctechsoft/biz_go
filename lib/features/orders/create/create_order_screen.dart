import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/enums.dart';
import '../../../core/error_text.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/customer.dart';
import '../../../models/order.dart';
import '../../../models/product.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/db.dart';
import '../../../services/sound_service.dart';
import '../../../widgets/common.dart';
import '../../customers/customer_edit_screen.dart';
import '../invoice_screen.dart';

/// Tạo đơn (5 bước) **hoặc sửa đơn** đã tạo.
///
/// Truyền [editing] để vào chế độ sửa: bỏ 2 bước chọn khách/địa chỉ (đơn đã
/// snapshot sẵn), vào thẳng bước Sản phẩm với giỏ hàng đổ từ đơn cũ.
///
/// Chế độ sửa KHÔNG cho đổi khách, địa chỉ, tiền trả trước và trạng thái
/// thanh toán — tiền đã thu là bất biến, đổi những thứ đó là lệch với
/// `payments` và công nợ đã ghi. Xem [Db.editOrder].
class CreateOrderScreen extends StatefulWidget {
  final Order? editing;
  const CreateOrderScreen({super.key, this.editing});
  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  int _step = 0;
  Customer? _customer;
  CustomerAddress? _address;
  final Map<String, OrderItem> _cart = {}; // key = packagingId

  /// Giá bảng theo packagingId, nhớ lại lúc thêm vào giỏ. Cần để giỏ hàng còn
  /// biết "giá gốc" là bao nhiêu sau khi người dùng sửa giá tay.
  final Map<String, int> _listPrice = {};
  String _custQuery = '';

  final _shipping = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _prepaid = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _deliveryNote = TextEditingController();
  PaymentStatus _payStatus = PaymentStatus.UNPAID;

  /// Giờ dự kiến cho đơn này xuất phát. `null` = chưa đặt → hàng đợi xếp theo
  /// giờ tạo đơn. Không tự điền sẵn một giờ đoán mò: giờ bịa mà lọt vào hàng
  /// đợi thì còn khó lần hơn là để trống.
  DateTime? _plannedDepart;
  bool _busy = false;
  bool _prefilled = false;

  static const _titles = [
    'Tạo đơn - Chọn khách',
    'Chọn địa chỉ giao',
    'Chọn sản phẩm',
    'Giỏ hàng',
    'Xác nhận đơn hàng',
  ];

  /// Bước 0-1 không dùng khi sửa đơn nên để trống.
  static const _editTitles = [
    '',
    '',
    'Sửa đơn - Sản phẩm',
    'Sửa đơn - Giỏ hàng',
    'Xác nhận sửa đơn',
  ];

  Order? get _editing => widget.editing;
  bool get _isEdit => _editing != null;

  /// Bước đầu tiên hợp lệ: sửa đơn thì bắt đầu ngay ở bước chọn sản phẩm.
  int get _firstStep => _isEdit ? 2 : 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;

    final editing = widget.editing;
    if (editing != null) {
      // Đổ lại đúng đơn cũ. `prepaid`/`paymentStatus` đọc lên để phần tổng kết
      // hiển thị đúng, nhưng KHÔNG cho sửa và không gửi lên `editOrder`.
      for (final it in editing.items) {
        _cart[it.packagingId] = it;
      }
      _shipping.text = moneyPlain(editing.shippingFee);
      _discount.text = moneyPlain(editing.discount);
      _prepaid.text = moneyPlain(editing.prepaid);
      _note.text = editing.note;
      _deliveryNote.text = editing.deliveryNote;
      _payStatus = editing.paymentStatus;
      _plannedDepart = editing.plannedDepartAt;
      _step = _firstStep;
      return;
    }

    final extra = GoRouterState.of(context).extra;
    if (extra is Customer) {
      _customer = extra;
      _address = extra.defaultAddress;
      _step = 2;
    }
  }

  @override
  void dispose() {
    _shipping.dispose();
    _discount.dispose();
    _prepaid.dispose();
    _note.dispose();
    _deliveryNote.dispose();
    super.dispose();
  }

  int _int(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get _subtotal => _cart.values.fold(0, (s, i) => s + i.lineTotal);
  int get _total => _subtotal + _int(_shipping) - _int(_discount);
  int get _codRemaining => _total - _int(_prepaid);

  void _back() {
    // Sửa đơn thì bước 2 là bước đầu — lùi thêm nữa là thoát màn.
    if (_step <= _firstStep) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  bool get _canContinue => switch (_step) {
        0 => _customer != null,
        1 => _address != null,
        2 => _cart.isNotEmpty,
        3 => _cart.isNotEmpty,
        _ => true,
      };

  Future<void> _submit({bool print = false}) async {
    setState(() => _busy = true);
    final db = context.read<Db>();
    final user = context.read<AuthProvider>().user!;
    // Giữ messenger TRƯỚC await: `pushReplacement` gỡ màn này khỏi cây, gọi
    // `toast(context)` sau đó là dựa vào context đã hỏng nên toast không hiện.
    final messenger = ScaffoldMessenger.of(context);
    final draft = Order(
      id: '',
      code: '',
      createdAt: DateTime.now(),
      customerId: _customer!.id,
      customerName: _customer!.name,
      customerPhone: _customer!.phone,
      deliveryAddress: _address!.address,
      deliveryReceiver: _address!.receiver,
      deliveryPhone: _address!.phone,
      deliveryMapUrl: _address!.mapUrl,
      deliveryCarrierName: _address!.carrierName,
      deliveryCarrierPhone: _address!.carrierPhone,
      deliveryAddressNote: _address!.note,
      items: _cart.values.toList(),
      shippingFee: _int(_shipping),
      discount: _int(_discount),
      prepaid: _int(_prepaid),
      paymentStatus: _payStatus,
      plannedDepartAt: _plannedDepart,
      note: _note.text.trim(),
      deliveryNote: _deliveryNote.text.trim(),
    );
    try {
      final order =
          await db.createOrder(draft, actorId: user.id, actorName: user.name);
      SoundService.cash();
      if (!mounted) return;
      context.pushReplacement('/orders/${order.id}');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Đã tạo đơn ${order.code}')),
        );
      if (print) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => InvoiceScreen(order: order)));
      }
    } catch (e) {
      debugPrint('CREATE-ORDER ERROR: $e');
      if (mounted) {
        setState(() => _busy = false);
        toast(
            context,
            friendlyError(e,
                fallback: 'Tạo đơn không thành công. Thử lại giúp tôi.'));
      }
    }
  }

  /// Lưu thay đổi cho đơn đang sửa. Không đụng khách/địa chỉ/tiền đã thu —
  /// xem [Db.editOrder].
  Future<void> _saveEdit() async {
    final o = _editing!;
    setState(() => _busy = true);
    final db = context.read<Db>();
    final user = context.read<AuthProvider>().user!;
    try {
      await db.editOrder(
        order: o,
        items: _cart.values.toList(),
        shippingFee: _int(_shipping),
        discount: _int(_discount),
        note: _note.text.trim(),
        deliveryNote: _deliveryNote.text.trim(),
        plannedDepartAt: _plannedDepart,
        actorId: user.id,
        actorName: user.name,
      );
      if (!mounted) return;
      // Toast TRƯỚC khi pop: `ScaffoldMessenger` nằm ở tầng app nên snackbar
      // vẫn sống sau khi màn này bị gỡ, còn gọi sau pop thì context đã hỏng.
      toast(context, 'Đã lưu thay đổi đơn ${o.code}');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('EDIT-ORDER ERROR: $e');
      if (mounted) {
        setState(() => _busy = false);
        toast(
            context,
            friendlyError(e,
                fallback: 'Không lưu được thay đổi. Thử lại giúp tôi.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(_isEdit ? _editTitles[_step] : _titles[_step]),
      ),
      body: switch (_step) {
        0 => _customerStep(),
        1 => _addressStep(),
        2 => _productStep(),
        3 => _cartStep(),
        _ => _confirmStep(),
      },
      bottomNavigationBar: _step == 4 ? null : _bottomBar(),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step == 3)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tổng tiền hàng',
                        style: TextStyle(color: AppColors.textSecondary)),
                    Text(money(_subtotal),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ElevatedButton(
              onPressed: _canContinue ? () => setState(() => _step++) : null,
              child: const Text('Tiếp tục'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Step 0: choose customer ----
  Widget _customerStep() {
    final db = context.read<Db>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'Tìm theo tên hoặc SĐT...',
                prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _custQuery = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Customer>>(
            stream: db.customers(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!
                  .where((c) =>
                      c.name.toLowerCase().contains(_custQuery) ||
                      c.phone.contains(_custQuery))
                  .toList();
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: _customer?.id == c.id ? AppColors.primaryLight : null,
                      child: ListTile(
                        leading: Avatar(c.name),
                        title: Text(c.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone),
                        trailing: _customer?.id == c.id
                            ? const Icon(Icons.check_circle,
                                color: AppColors.success)
                            : null,
                        onTap: () => setState(() {
                          _customer = c;
                          _address = c.defaultAddress;
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: () async {
              final id = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => const CustomerEditScreen()));
              if (id != null && context.mounted) {
                final c = await db.customer(id).first;
                if (mounted) {
                  setState(() {
                    _customer = c;
                    _address = c.defaultAddress;
                  });
                }
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Thêm khách hàng mới'),
          ),
        ),
      ],
    );
  }

  // ---- Step 1: choose address ----
  Widget _addressStep() {
    final addrs = _customer?.addresses ?? [];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final a in addrs)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<String>(
              value: a.id,
              groupValue: _address?.id,
              activeColor: AppColors.primary,
              onChanged: (_) => setState(() => _address = a),
              title: Text(a.address,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(a.hasCarrier
                  ? 'Nhà xe: ${a.carrierName}'
                  : '${a.receiver} · ${a.phone}'),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final c = _customer!;
            final updated = await Navigator.push<String>(context,
                MaterialPageRoute(builder: (_) => CustomerEditScreen(customer: c)));
            if (updated != null && context.mounted) {
              final fresh = await context.read<Db>().customer(c.id).first;
              if (mounted) setState(() => _customer = fresh);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Thêm địa chỉ mới'),
        ),
      ],
    );
  }

  // ---- Step 2: choose products ----
  Widget _productStep() {
    final db = context.read<Db>();
    return StreamBuilder<List<Product>>(
      stream: db.products(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snap.data!;
        // Nhớ giá bảng của MỌI quy cách đang bán. Khi sửa đơn cũ thì `_listPrice`
        // rỗng, không có bước này thì giỏ hàng không biết giá gốc để so và nút
        // "Dùng giá bảng" thành vô dụng. Chỉ ghi vào Map, không setState.
        for (final p in products) {
          for (final v in p.variants) {
            for (final pk in v.packagings) {
              _listPrice[pk.id] = pk.price;
            }
          }
        }
        // Mỗi tab là MỘT SẢN PHẨM, bên trong là các phân loại + quy cách của
        // nó. Trước đây tab là danh mục — mà danh mục đã bỏ, và gom theo sản
        // phẩm cũng đúng hơn: danh sách bên dưới vốn là phân loại của nó.
        if (products.isEmpty) {
          return const EmptyState(text: 'Chưa có sản phẩm');
        }
        return DefaultTabController(
          length: products.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                indicatorColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [for (final p in products) Tab(text: p.name)],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final p in products) _productList([p]),
                  ],
                ),
              ),
              if (_cart.isNotEmpty)
                Container(
                  color: AppColors.primaryLight,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text('${_cart.length} mặt hàng · ${money(_subtotal)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton(
                          onPressed: () => setState(() => _step = 3),
                          child: const Text('Xem giỏ')),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _productList(List<Product> products) {
    final rows = <(Product, ProductVariant, Packaging)>[];
    for (final p in products) {
      for (final v in p.variants) {
        for (final pk in v.packagings) {
          if (pk.active) rows.add((p, v, pk));
        }
      }
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final (p, v, pk) = rows[i];
        final inCart = _cart[pk.id];
        // Giá đang áp cho dòng này: giá đã sửa tay nếu có, không thì giá bảng.
        final price = inCart?.unitPrice ?? pk.price;
        final edited = inCart != null && inCart.unitPrice != pk.price;
        return Card(
          color: inCart != null ? AppColors.primaryLight : null,
          child: ListTile(
            // Chạm cả dòng để sửa số lượng + giá, khỏi bấm +/- chục lần.
            onTap: () => _editLine(p, v, pk),
            leading: LocalImage(path: p.imagePath, size: 48),
            // Phân loại lên làm tiêu đề: cùng "Cùi Bưởi 1kg" nhưng khác phân
            // loại và khác giá, để tên sản phẩm ở trên thì mọi dòng giống hệt.
            title: Text(v.name.trim().isEmpty ? p.name : v.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            // Giá sửa tay thì cho "Giá bảng ..." XUỐNG DÒNG RIÊNG, không nhét
            // chung một dòng — nhét chung là chật rồi cắt cụt thành "(đã s…",
            // đọc không ra. Mỗi dòng ngắn thì không bao giờ phải cắt.
            isThreeLine: edited,
            subtitle: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${pk.name} · '),
                      TextSpan(
                        text: money(price),
                        style: TextStyle(
                          fontWeight:
                              edited ? FontWeight.w700 : FontWeight.w400,
                          color: edited
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (edited)
                  Text(
                    'Giá bảng ${money(pk.price)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
            trailing: inCart == null
                ? IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addToCart(p, v, pk),
                  )
                // Nút gọn lại (bỏ padding mặc định 48px của IconButton) để
                // chừa chỗ cho tên hàng — số lượng 3 chữ số vẫn không đội chỗ.
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepBtn(
                        icon: Icons.remove_circle_outline,
                        onTap: () => _changeQty(pk.id, -1),
                      ),
                      // Chạm vào số để gõ thẳng số lượng.
                      InkWell(
                        onTap: () => _editLine(p, v, pk),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 34),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          child: Text('${inCart.quantity}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.primary)),
                        ),
                      ),
                      _StepBtn(
                        icon: Icons.add_circle,
                        color: AppColors.primary,
                        onTap: () => _changeQty(pk.id, 1),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// Sheet sửa **số lượng + đơn giá** của một dòng hàng.
  ///
  /// Giá mặc định lấy từ bảng giá (`pk.price`) nhưng cho sửa tay — khách mặc
  /// cả, hay lô hàng lệch giá. Giá chốt ở đây là giá **snapshot** vào đơn:
  /// sửa bảng giá sau này KHÔNG đổi đơn đã tạo.
  Future<void> _editLine(Product p, ProductVariant v, Packaging pk) =>
      _lineSheet(
        packagingId: pk.id,
        title: v.name.trim().isEmpty ? p.name : v.name,
        listPrice: pk.price,
        create: () => OrderItem(
          productId: p.id,
          variantId: v.id,
          packagingId: pk.id,
          productName: p.name,
          variantName: v.name,
          packagingName: pk.name,
          quantity: 1,
          unitPrice: pk.price,
          imagePath: p.imagePath,
        ),
      );

  /// Cùng sheet đó nhưng mở từ **giỏ hàng**, nơi chỉ còn `OrderItem`.
  /// Giá bảng lấy lại từ [_listPrice] — dòng nào vào được giỏ thì đã đi qua
  /// `_addToCart` hoặc `_lineSheet`, nên map luôn có sẵn.
  Future<void> _editCartLine(OrderItem it) => _lineSheet(
        packagingId: it.packagingId,
        title: it.variantLabel,
        listPrice: _listPrice[it.packagingId] ?? it.unitPrice,
        create: () => it,
      );

  Future<void> _lineSheet({
    required String packagingId,
    required String title,
    required int listPrice,
    required OrderItem Function() create,
  }) async {
    _listPrice[packagingId] = listPrice;
    final existing = _cart[packagingId];
    final qtyC = TextEditingController(text: '${existing?.quantity ?? 1}');
    final priceC = TextEditingController(
        text: moneyPlain(existing?.unitPrice ?? listPrice));
    String? error;

    int qty() => int.tryParse(qtyC.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    int price() => parseMoney(priceC.text);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                16,
            left: 16,
            right: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `SheetHeader` tự căn giữa chữ, NHƯNG Column cha dùng
                // `crossAxisAlignment.start` nên nó co lại đúng bề rộng chữ và
                // dính lề trái — phải ép giãn hết bề ngang mới căn giữa được.
                SizedBox(width: double.infinity, child: SheetHeader(title)),
                const SizedBox(height: 12),
                const Text('Số lượng',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.remove),
                      onPressed: () => setSheet(() {
                        final q = qty() - 1;
                        qtyC.text = '${q < 1 ? 1 : q}';
                        error = null;
                      }),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TextField(
                          controller: qtyC,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700),
                          onChanged: (_) => setSheet(() => error = null),
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add),
                      onPressed: () => setSheet(() {
                        qtyC.text = '${qty() + 1}';
                        error = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  onChanged: (_) => setSheet(() => error = null),
                  decoration: const InputDecoration(
                      labelText: 'Đơn giá', suffixText: 'đ'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Giá bảng: ${money(listPrice)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const Spacer(),
                    if (price() != listPrice)
                      TextButton(
                        onPressed: () => setSheet(() {
                          priceC.text = moneyPlain(listPrice);
                          error = null;
                        }),
                        child: const Text('Dùng giá bảng'),
                      ),
                  ],
                ),
                const Divider(height: 24),
                KVRow('Thành tiền', money(qty() * price()), bold: true),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (existing != null) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Xoá khỏi đơn'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Banner đỏ inline, KHÔNG toast — sheet che mất toast.
                          if (qty() < 1) {
                            setSheet(() => error = 'Số lượng phải từ 1 trở lên');
                            return;
                          }
                          if (price() <= 0) {
                            setSheet(() => error = 'Đơn giá phải lớn hơn 0');
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: Text(existing == null ? 'Thêm vào đơn' : 'Lưu'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == null) return; // đóng sheet mà không chọn gì
    setState(() {
      if (saved == false) {
        _cart.remove(packagingId);
        return;
      }
      _cart[packagingId] =
          (existing ?? create()).copyWith(quantity: qty(), unitPrice: price());
    });
  }

  void _addToCart(Product p, ProductVariant v, Packaging pk) {
    _listPrice[pk.id] = pk.price;
    setState(() {
      _cart[pk.id] = OrderItem(
        productId: p.id,
        variantId: v.id,
        packagingId: pk.id,
        productName: p.name,
        variantName: v.name,
        packagingName: pk.name,
        quantity: 1,
        unitPrice: pk.price,
        imagePath: p.imagePath,
      );
    });
  }

  void _changeQty(String key, int delta) {
    final item = _cart[key];
    if (item == null) return;
    final q = item.quantity + delta;
    setState(() {
      if (q <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = item.copyWith(quantity: q);
      }
    });
  }

  // ---- Step 3: cart ----
  Widget _cartStep() {
    if (_cart.isEmpty) return const EmptyState(text: 'Giỏ hàng trống');
    final items = _cart.values.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        final listPrice = _listPrice[it.packagingId];
        final edited = listPrice != null && listPrice != it.unitPrice;
        return Card(
          child: InkWell(
            // Chạm cả thẻ để sửa số lượng + giá.
            onTap: () => _editCartLine(it),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  LocalImage(path: it.imagePath, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.variantLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        // Bỏ tên sản phẩm: mọi dòng đều là "Cùi Bưởi" nên nó
                        // chỉ tốn chỗ, phân loại ở trên mới là thứ phân biệt.
                        // Giá bảng vẫn xuống dòng riêng — xem ghi chú ở màn
                        // chọn sản phẩm: nhét chung một dòng là bị cắt cụt.
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '${it.packagingName} · '),
                              TextSpan(
                                text: money(it.unitPrice),
                                style: TextStyle(
                                  fontWeight: edited
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: edited
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (edited)
                          Text(
                            'Giá bảng ${money(listPrice)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(money(it.lineTotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _changeQty(it.packagingId, -1)),
                      InkWell(
                        onTap: () => _editCartLine(it),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text('${it.quantity}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppColors.primary)),
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.add_circle,
                              color: AppColors.primary),
                          onPressed: () => _changeQty(it.packagingId, 1)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Step 4: confirm ----
  Widget _confirmStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                child: Column(
                  children: [
                    // Sửa đơn: khách + địa chỉ lấy từ SNAPSHOT của đơn, không
                    // đọc lại hồ sơ khách (khách đổi địa chỉ sau đó thì đơn cũ
                    // vẫn phải giữ nơi đã chốt).
                    KVRow('Khách hàng', _editing?.customerName ?? _customer!.name),
                    KVRow('SĐT', _editing?.customerPhone ?? _customer!.phone),
                    KVRow('Địa chỉ giao',
                        _editing?.deliveryAddress ?? _address!.address),
                    InkWell(
                      onTap: _showCartDetail,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('Sản phẩm',
                                  style: TextStyle(
                                      color: AppColors.textSecondary)),
                            ),
                            Text('Xem chi tiết (${_cart.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                            const Icon(Icons.chevron_right,
                                size: 18, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _numField('Phí giao hàng', _shipping),
              _numField('Giảm giá', _discount),
              // Sửa đơn KHÔNG cho đụng tiền đã thu: `prepaid` đã cộng vào
              // `paidAmount` và công nợ khách lúc tạo đơn, sửa số đó ở đây là
              // sai lệch sổ sách mà không có payment nào đối chứng.
              if (!_isEdit) ...[
                _numField('Khách trả trước', _prepaid),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickPayStatus,
                  child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Trạng thái thanh toán'),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(paymentStatusUi(_payStatus).label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                        const Icon(Icons.arrow_drop_down,
                            color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _departTimeField(),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Ghi chú nội bộ'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deliveryNote,
                decoration: const InputDecoration(labelText: 'Ghi chú giao hàng'),
              ),
              const SizedBox(height: 16),
              SectionCard(
                child: Column(
                  children: [
                    KVRow('Tổng tiền hàng', money(_subtotal)),
                    KVRow('Phí giao hàng', money(_int(_shipping))),
                    KVRow('Giảm giá', '- ${money(_int(_discount))}'),
                    const Divider(),
                    KVRow('Tổng cộng', money(_total), bold: true),
                    // Sửa đơn thì mốc so sánh là số ĐÃ THU thật (gồm cả tiền
                    // thu sau khi tạo), không phải riêng khoản trả trước.
                    if (_isEdit) ...[
                      KVRow('Đã thu', money(_editing!.paidAmount)),
                      KVRow(
                          'Còn phải thu',
                          money(_total - _editing!.paidAmount > 0
                              ? _total - _editing!.paidAmount
                              : 0),
                          valueColor: AppColors.danger,
                          bold: true),
                    ] else ...[
                      KVRow('Khách trả trước', money(_int(_prepaid))),
                      KVRow('Còn phải thu (COD)', money(_codRemaining),
                          valueColor: AppColors.danger, bold: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed:
                      _busy ? null : (_isEdit ? _saveEdit : () => _submit()),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Lưu thay đổi' : 'Tạo đơn'),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _submit(print: true),
                    child: const Text('Tạo đơn & In'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Ô chọn **giờ dự kiến xuất phát** — quyết định đơn nào đi trước ở màn Kho
  /// và Giao hàng. Để trống thì đơn xếp theo giờ tạo (tạo trước đi trước).
  Widget _departTimeField() {
    final set = _plannedDepart != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await pickDateTime(
              context,
              initial: _plannedDepart,
              helpText: 'Giờ xuất phát dự kiến',
            );
            if (picked != null) setState(() => _plannedDepart = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Giờ xuất phát dự kiến',
              prefixIcon: Icon(Icons.schedule),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    set ? fmtDateTime(_plannedDepart) : 'Chưa đặt',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          set ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (set)
                  InkWell(
                    onTap: () => setState(() => _plannedDepart = null),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 18, color: AppColors.textSecondary),
                    ),
                  )
                else
                  const Icon(Icons.arrow_drop_down,
                      color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 12, top: 4),
          child: Text(
            'Để trống thì đơn xếp theo giờ tạo. Đơn GẤP luôn lên đầu.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// Bottom sheet chọn trạng thái thanh toán.
  Future<void> _pickPayStatus() async {
    const options = [
      PaymentStatus.UNPAID,
      PaymentStatus.PARTIAL,
      PaymentStatus.PAID,
      PaymentStatus.COD,
      PaymentStatus.DEBT,
    ];
    final picked = await showModalBottomSheet<PaymentStatus>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader('Trạng thái thanh toán'),
            for (final s in options)
              ListTile(
                title: Text(paymentStatusUi(s).label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: _payStatus == s
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _payStatus = picked);
  }

  /// Sheet xem nhanh sản phẩm trong đơn (chỉ đọc).
  void _showCartDetail() {
    final items = _cart.values.toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeader('Sản phẩm (${items.length})'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final it in items)
                      ListTile(
                        leading: LocalImage(path: it.imagePath, size: 44),
                        title: Text(it.variantLabel,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${it.packagingName} · '
                            '${money(it.unitPrice)} × ${it.quantity}'),
                        trailing: Text(money(it.lineTotal),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [ThousandsInputFormatter()],
          decoration: InputDecoration(labelText: label, suffixText: 'đ'),
          onChanged: (_) => setState(() {}),
        ),
      );
}

/// Nút +/- gọn cho cụm chỉnh số lượng.
///
/// `IconButton` mặc định chiếm 48x48 — hai cái là 96px, cộng ô số nữa thì dòng
/// hàng chỉ còn hơn nửa bề ngang cho tên + giá, đủ để tràn. Cái này ~36px.
class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 24, color: color ?? AppColors.textSecondary),
      ),
    );
  }
}
