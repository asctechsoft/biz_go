import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/order_filter.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Lọc nhanh đơn hàng. Bấm "Áp dụng" trả [OrderFilter] về màn Đơn hàng qua
/// `context.pop(filter)` — màn kia `await context.push()` để nhận.
///
/// Nhận bộ lọc hiện hành qua `extra` để mở lên là thấy đúng thứ đang lọc.
class QuickFilterScreen extends StatefulWidget {
  final OrderFilter initial;
  const QuickFilterScreen({super.key, this.initial = OrderFilter.empty});
  @override
  State<QuickFilterScreen> createState() => _QuickFilterScreenState();
}

class _QuickFilterScreenState extends State<QuickFilterScreen> {
  late OrderFilter _f = widget.initial;

  /// Danh sách nhân viên để lọc — lấy user thật, không hardcode vai trò.
  List<AppUser> _staff = const [];

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    final users = await context.read<Db>().users().first;
    if (mounted) setState(() => _staff = users);
  }

  static const _ranges = [1, 7, 30];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lọc nhanh')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Label('Khoảng thời gian'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _ranges)
                _chip(
                  d == 1 ? 'Hôm nay' : '$d ngày',
                  selected: _f.custom == null && (_f.days ?? 30) == d,
                  onTap: () => setState(
                      () => _f = _f.copyWith(days: d, clearCustom: true)),
                ),
              _chip(
                _f.custom == null
                    ? 'Tùy chọn'
                    : '${fmtDate(_f.custom!.start)} - ${fmtDate(_f.custom!.end)}',
                selected: _f.custom != null,
                onTap: _pickRange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _enumField<OrderStatus>(
            'Trạng thái đơn',
            OrderStatus.values,
            _f.orderStatus,
            (s) => orderStatusUi(s).label,
            (v) => setState(() => _f = v == null
                ? _f.copyWith(clearOrderStatus: true)
                : _f.copyWith(orderStatus: v)),
          ),
          _enumField<DeliveryStatus>(
            'Trạng thái giao',
            deliveryStatusFilterValues,
            _f.deliveryStatus,
            (s) => deliveryStatusUi(s).label,
            (v) => setState(() => _f = v == null
                ? _f.copyWith(clearDeliveryStatus: true)
                : _f.copyWith(deliveryStatus: v)),
          ),
          _enumField<PaymentStatus>(
            'Trạng thái thanh toán',
            PaymentStatus.values,
            _f.paymentStatus,
            (s) => paymentStatusUi(s).label,
            (v) => setState(() => _f = v == null
                ? _f.copyWith(clearPaymentStatus: true)
                : _f.copyWith(paymentStatus: v)),
          ),
          _staffField(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.pop(_f),
            child: const Text('Áp dụng'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.pop(OrderFilter.empty),
            child: const Text('Xóa bộ lọc'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _f.custom,
      helpText: 'Chọn khoảng ngày',
      saveText: 'Xong',
    );
    if (picked != null) {
      setState(() => _f = _f.copyWith(
            custom: DateTimeRange(
              start: DateTime(picked.start.year, picked.start.month,
                  picked.start.day),
              end: DateTime(
                  picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
            ),
          ));
    }
  }

  Widget _chip(String text,
          {required bool selected, required VoidCallback onTap}) =>
      ChoiceChip(
        label: Text(text),
        selected: selected,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary),
        onSelected: (_) => onTap(),
      );

  /// Ô chọn 1 giá trị enum, kèm lựa chọn "Tất cả" (= null).
  Widget _enumField<T>(
    String label,
    List<T> values,
    T? current,
    String Function(T) labelOf,
    ValueChanged<T?> onChanged,
  ) {
    return _field(
      label,
      current == null ? 'Tất cả' : labelOf(current),
      () async {
        final options = ['Tất cả', ...values.map(labelOf)];
        final i = await _pickIndex(
            label, options, current == null ? 0 : values.indexOf(current) + 1);
        if (i != null) onChanged(i == 0 ? null : values[i - 1]);
      },
    );
  }

  Widget _staffField() {
    return _field(
      'Nhân viên',
      _f.staffId == null ? 'Tất cả' : _f.staffName,
      () async {
        final options = [
          'Tất cả',
          ..._staff.map((u) => '${u.name} · ${u.role.label}'),
        ];
        final cur = _f.staffId == null
            ? 0
            : _staff.indexWhere((u) => u.id == _f.staffId) + 1;
        final i = await _pickIndex('Nhân viên', options, cur);
        if (i == null) return;
        setState(() => _f = i == 0
            ? _f.copyWith(clearStaff: true)
            : _f.copyWith(
                staffId: _staff[i - 1].id, staffName: _staff[i - 1].name));
      },
    );
  }

  Widget _field(String label, String value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Label(label),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: InputDecorator(
                decoration: const InputDecoration(),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(value,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.arrow_drop_down,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// Bottom sheet chọn 1 giá trị (thay DropdownButtonFormField hay bung/đè).
  Future<int?> _pickIndex(String title, List<String> options, int current) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * .7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHeader(title),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final (i, o) in options.indexed)
                      ListTile(
                        title: Text(o,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        trailing: current == i
                            ? const Icon(Icons.check, color: AppColors.primary)
                            : null,
                        onTap: () => Navigator.pop(ctx, i),
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
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
