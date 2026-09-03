import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class CustomerEditScreen extends StatefulWidget {
  final Customer? customer;
  const CustomerEditScreen({super.key, this.customer});
  @override
  State<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends State<CustomerEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.customer?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.customer?.phone ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.customer?.note ?? '');
  late List<CustomerAddress> _addresses =
      List.of(widget.customer?.addresses ?? []);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      toast(context, 'Nhập tên và số điện thoại');
      return;
    }
    setState(() => _busy = true);
    final db = context.read<Db>();
    final c = Customer(
      id: widget.customer?.id ?? '',
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      note: _note.text.trim(),
      source: widget.customer?.source ?? '',
      addresses: _addresses,
    );
    final id = await db.upsertCustomer(c);
    if (mounted) Navigator.pop(context, id);
  }

  void _setDefault(int i) {
    setState(() {
      _addresses = [
        for (var j = 0; j < _addresses.length; j++)
          _addresses[j].copyWith(isDefault: j == i)
      ];
    });
  }

  Future<void> _editAddress([int? index]) async {
    final existing = index == null ? null : _addresses[index];
    final result = await Navigator.push<CustomerAddress>(
      context,
      MaterialPageRoute(
          builder: (_) => _AddressFormScreen(existing: existing)),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        if (result.isDefault || _addresses.isEmpty) {
          _addresses = _addresses.map((a) => a.copyWith(isDefault: false)).toList();
        }
        _addresses.add(result);
      } else {
        _addresses[index] = result;
      }
      if (result.isDefault) {
        _addresses = _addresses
            .map((a) => a.id == result.id
                ? a
                : a.copyWith(isDefault: false))
            .toList();
      }
      if (!_addresses.any((a) => a.isDefault) && _addresses.isNotEmpty) {
        _addresses[0] = _addresses[0].copyWith(isDefault: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.customer == null ? 'Thêm khách hàng' : 'Sửa khách hàng')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('Họ tên', _name),
          _field('Số điện thoại', _phone, keyboard: TextInputType.phone),
          _field('Ghi chú', _note, maxLines: 2),
          const SizedBox(height: 12),
          const Text('Địa chỉ giao hàng',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var i = 0; i < _addresses.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _editAddress(i),
                title: Text(_addresses[i].label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_addresses[i].address),
                trailing: IconButton(
                  icon: Icon(
                    _addresses[i].isDefault
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: _addresses[i].isDefault
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  onPressed: () => _setDefault(i),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _editAddress(),
            icon: const Icon(Icons.add),
            label: const Text('Thêm địa chỉ'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextField(controller: c, keyboardType: keyboard, maxLines: maxLines),
        ],
      ),
    );
  }
}

/// Mockup 3.4 — Thêm/Sửa địa chỉ.
class _AddressFormScreen extends StatefulWidget {
  final CustomerAddress? existing;
  const _AddressFormScreen({this.existing});
  @override
  State<_AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<_AddressFormScreen> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _receiver =
      TextEditingController(text: widget.existing?.receiver ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late bool _default = widget.existing?.isDefault ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'Thêm địa chỉ' : 'Sửa địa chỉ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _f('Tên địa chỉ', _label, hint: 'Cửa hàng 3'),
          _f('Người nhận', _receiver),
          _f('Số điện thoại', _phone, keyboard: TextInputType.phone),
          _f('Địa chỉ', _address, maxLines: 2),
          _f('Ghi chú', _note),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đặt làm mặc định'),
            value: _default,
            onChanged: (v) => setState(() => _default = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_label.text.trim().isEmpty || _address.text.trim().isEmpty) {
                toast(context, 'Nhập tên địa chỉ và địa chỉ');
                return;
              }
              Navigator.pop(
                context,
                CustomerAddress(
                  id: widget.existing?.id,
                  label: _label.text.trim(),
                  receiver: _receiver.text.trim(),
                  phone: _phone.text.trim(),
                  address: _address.text.trim(),
                  note: _note.text.trim(),
                  isDefault: _default,
                ),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Widget _f(String label, TextEditingController c,
      {String? hint, TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextField(
              controller: c,
              keyboardType: keyboard,
              maxLines: maxLines,
              decoration: InputDecoration(hintText: hint)),
        ],
      ),
    );
  }
}
