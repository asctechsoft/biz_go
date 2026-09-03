import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Presentational quick-filter (mockup 1.4). Applies by navigating to Orders;
/// the Orders screen has its own working search/tab filter.
class QuickFilterScreen extends StatefulWidget {
  const QuickFilterScreen({super.key});
  @override
  State<QuickFilterScreen> createState() => _QuickFilterScreenState();
}

class _QuickFilterScreenState extends State<QuickFilterScreen> {
  int _range = 2;
  String _orderStatus = 'Tất cả';
  String _deliveryStatus = 'Tất cả';
  String _paymentStatus = 'Tất cả';
  String _staff = 'Tất cả';

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
            children: [
              for (final (i, t) in ['Hôm nay', '7 ngày', '30 ngày', 'Tùy chọn']
                  .indexed)
                ChoiceChip(
                  label: Text(t),
                  selected: _range == i,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                      color: _range == i ? Colors.white : AppColors.textPrimary),
                  onSelected: (_) => setState(() => _range = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _dropdown('Trạng thái đơn', _orderStatus,
              ['Tất cả', 'Đơn mới', 'Đang xử lý', 'Hoàn thành', 'Đã hủy'],
              (v) => setState(() => _orderStatus = v)),
          _dropdown('Trạng thái giao', _deliveryStatus,
              ['Tất cả', 'Chờ xếp chuyến', 'Đang giao', 'Giao thành công', 'Giao thất bại'],
              (v) => setState(() => _deliveryStatus = v)),
          _dropdown('Trạng thái thanh toán', _paymentStatus,
              ['Tất cả', 'Chưa thanh toán', 'Thanh toán 1 phần', 'Đã thanh toán', 'Công nợ'],
              (v) => setState(() => _paymentStatus = v)),
          _dropdown('Nhân viên', _staff, ['Tất cả', 'Kế toán', 'Điều phối'],
              (v) => setState(() => _staff = v)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/orders'),
            child: const Text('Áp dụng'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _range = 2;
              _orderStatus = _deliveryStatus = _paymentStatus = _staff = 'Tất cả';
            }),
            child: const Text('Xóa bộ lọc'),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          DropdownButtonFormField<String>(
            initialValue: value,
            items: [
              for (final o in options)
                DropdownMenuItem(value: o, child: Text(o))
            ],
            onChanged: (v) => onChanged(v!),
          ),
        ],
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
