import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/enums.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../models/customer.dart';
import '../../../models/order.dart';
import '../../../models/product.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/db.dart';
import '../../../widgets/common.dart';
import '../../customers/customer_edit_screen.dart';
import '../invoice_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});
  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  int _step = 0;
  Customer? _customer;
  CustomerAddress? _address;
  final Map<String, OrderItem> _cart = {}; // key = packagingId
  String _custQuery = '';

  final _shipping = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _prepaid = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _deliveryNote = TextEditingController();
  PaymentStatus _payStatus = PaymentStatus.UNPAID;
  bool _busy = false;
  bool _prefilled = false;

  static const _titles = [
    'Tạo đơn - Chọn khách',
    'Chọn địa chỉ giao',
    'Chọn sản phẩm',
    'Giỏ hàng',
    'Xác nhận đơn hàng',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefilled) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Customer) {
        _customer = extra;
        _address = extra.defaultAddress;
        _step = 2;
      }
      _prefilled = true;
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
    if (_step == 0) {
      context.pop();
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
    final draft = Order(
      id: '',
      code: '',
      createdAt: DateTime.now(),
      customerId: _customer!.id,
      customerName: _customer!.name,
      customerPhone: _customer!.phone,
      deliveryLabel: _address!.label,
      deliveryAddress: _address!.address,
      deliveryReceiver: _address!.receiver,
      deliveryPhone: _address!.phone,
      items: _cart.values.toList(),
      shippingFee: _int(_shipping),
      discount: _int(_discount),
      prepaid: _int(_prepaid),
      paymentStatus: _payStatus,
      note: _note.text.trim(),
      deliveryNote: _deliveryNote.text.trim(),
    );
    try {
      final order =
          await db.createOrder(draft, actorId: user.id, actorName: user.name);
      if (!mounted) return;
      context.pushReplacement('/orders/${order.id}');
      if (print) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => InvoiceScreen(order: order)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Lỗi tạo đơn: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(_titles[_step]),
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
              title: Text(a.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(a.address),
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
        final categories =
            products.map((p) => p.categoryName).toSet().toList()..sort();
        if (categories.isEmpty) {
          return const EmptyState(text: 'Chưa có sản phẩm');
        }
        return DefaultTabController(
          length: categories.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                labelColor: AppColors.primary,
                indicatorColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [for (final c in categories) Tab(text: c)],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final cat in categories)
                      _productList(products
                          .where((p) => p.categoryName == cat)
                          .toList()),
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
        return Card(
          color: inCart != null ? AppColors.primaryLight : null,
          child: ListTile(
            leading: LocalImage(path: p.imagePath, size: 48),
            title: Text('${p.name} ${pk.name}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${v.name} · ${money(pk.price)}'),
            trailing: inCart == null
                ? IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addToCart(p, v, pk),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _changeQty(pk.id, -1)),
                      Text('${inCart.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                          icon: const Icon(Icons.add_circle,
                              color: AppColors.primary),
                          onPressed: () => _changeQty(pk.id, 1)),
                    ],
                  ),
          ),
        );
      },
    );
  }

  void _addToCart(Product p, ProductVariant v, Packaging pk) {
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                LocalImage(path: it.imagePath, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(money(it.unitPrice),
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(money(it.lineTotal),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _changeQty(it.packagingId, -1)),
                    Text('${it.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                        icon: const Icon(Icons.add_circle,
                            color: AppColors.primary),
                        onPressed: () => _changeQty(it.packagingId, 1)),
                  ],
                ),
              ],
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
                    KVRow('Khách hàng', _customer!.name),
                    KVRow('SĐT', _customer!.phone),
                    KVRow('Địa chỉ giao', _address!.address),
                    KVRow('Sản phẩm', 'Xem chi tiết (${_cart.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _numField('Phí giao hàng', _shipping),
              _numField('Giảm giá', _discount),
              _numField('Khách trả trước', _prepaid),
              const SizedBox(height: 4),
              DropdownButtonFormField<PaymentStatus>(
                initialValue: _payStatus,
                decoration:
                    const InputDecoration(labelText: 'Trạng thái thanh toán'),
                items: [
                  for (final s in [
                    PaymentStatus.UNPAID,
                    PaymentStatus.PARTIAL,
                    PaymentStatus.PAID,
                    PaymentStatus.COD,
                    PaymentStatus.DEBT,
                  ])
                    DropdownMenuItem(value: s, child: Text(paymentStatusUi(s).label)),
                ],
                onChanged: (v) => setState(() => _payStatus = v!),
              ),
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
                    KVRow('Khách trả trước', money(_int(_prepaid))),
                    KVRow('Còn phải thu (COD)', money(_codRemaining),
                        valueColor: AppColors.danger, bold: true),
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
                  onPressed: _busy ? null : () => _submit(),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Tạo đơn'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _submit(print: true),
                  child: const Text('Tạo đơn & In'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, suffixText: 'đ'),
          onChanged: (_) => setState(() {}),
        ),
      );
}
