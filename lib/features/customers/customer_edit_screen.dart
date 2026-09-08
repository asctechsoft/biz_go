import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../services/db.dart';
import '../../services/image_service.dart';
import '../../widgets/common.dart';
import '../more/carriers_screen.dart';

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
  late String? _imagePath = widget.customer?.imagePath;
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _note]) {
      c.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Hỏi trước khi rời nếu có thay đổi chưa lưu.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return confirmDialog(
      context,
      title: 'Rời khỏi?',
      message: 'Thông tin chưa lưu sẽ bị mất. Bạn vẫn muốn thoát?',
      confirm: 'Thoát',
    );
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
      imagePath: _imagePath,
      addresses: _addresses,
    );
    final id = await db.upsertCustomer(c);
    _dirty = false;
    if (mounted) Navigator.pop(context, id);
  }

  void _setDefault(int i) {
    _dirty = true;
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
    // Trở về màn này: bỏ focus để không bung bàn phím.
    // Chạy sau khung hình để ghi đè việc Flutter tự khôi phục focus cũ.
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusManager.instance.primaryFocus?.unfocus();
      });
    }
    if (result == null) return;
    _dirty = true;
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
      appBar: AppBar(
          title: Text(
              widget.customer == null ? 'Thêm khách hàng' : 'Sửa khách hàng')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        children: [
          Center(
            child: ImagePickerBox(
              path: _imagePath,
              onTap: () async {
                final path =
                    await pickImage(context, context.read<ImageService>());
                if (path != null) {
                  setState(() {
                    _imagePath = path;
                    _dirty = true;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Chạm để chọn ảnh khách',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 16),
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
                title: Text(_addresses[i].address,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_addresses[i].hasCarrier
                    ? 'Nhà xe: ${_addresses[i].carrierName}'
                    : '${_addresses[i].receiver} · ${_addresses[i].phone}'),
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
          TextField(
              controller: c,
              keyboardType: keyboard,
              maxLines: maxLines,
              inputFormatters: keyboard == TextInputType.phone
                  ? phoneInputFormatters
                  : null),
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
  late final _receiver =
      TextEditingController(text: widget.existing?.receiver ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _carrier =
      TextEditingController(text: widget.existing?.carrierName ?? '');
  late final _carrierPhone =
      TextEditingController(text: widget.existing?.carrierPhone ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _map = TextEditingController(text: widget.existing?.mapUrl ?? '');
  late bool _default = widget.existing?.isDefault ?? false;
  bool _dirty = false;

  /// Vừa chọn nhà xe từ danh mục → hiện dòng nhắc là số này sửa được.
  bool _pickedFromDirectory = false;

  /// Chọn nhà xe từ danh mục, điền sẵn tên + SĐT vào 2 ô bên dưới.
  Future<void> _pickCarrier() async {
    final pick = await pickCarrier(context, selectedName: _carrier.text);
    if (pick == null || !mounted) return;
    setState(() {
      _carrier.text = pick.carrier?.name ?? '';
      _carrierPhone.text = pick.carrier?.phone ?? '';
      _pickedFromDirectory = pick.carrier != null;
      _dirty = true;
    });
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _receiver,
      _phone,
      _address,
      _carrier,
      _carrierPhone,
      _note,
      _map,
    ]) {
      c.addListener(() => _dirty = true);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return confirmDialog(
      context,
      title: 'Rời khỏi?',
      message: 'Địa chỉ chưa lưu sẽ bị mất. Bạn vẫn muốn thoát?',
      confirm: 'Thoát',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'Thêm địa chỉ' : 'Sửa địa chỉ')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        children: [
          _f('Người nhận', _receiver),
          _f('Số điện thoại', _phone, keyboard: TextInputType.phone),
          _f('Địa chỉ', _address, maxLines: 2),
          _f('Link Google Maps (tùy chọn)', _map,
              hint: 'Dán link vị trí từ app Google Maps'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: () =>
                  openMap(context, mapUrl: _map.text, address: _address.text),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Mở trên Google Maps'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 10),
            child: Text('Nhà xe (nếu gửi hàng qua nhà xe)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          // Chọn từ danh mục (Cài đặt › Nhà xe) → điền sẵn tên + SĐT. Hai ô
          // dưới vẫn sửa được: nhà xe đổi số cho riêng tuyến này là chuyện
          // thường, và danh mục chỉ là gợi ý — địa chỉ giữ bản chép riêng.
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: _pickCarrier,
              icon: const Icon(Icons.directions_bus_outlined),
              label: Text(_carrier.text.trim().isEmpty
                  ? 'Chọn nhà xe từ danh mục'
                  : 'Đổi nhà xe khác'),
            ),
          ),
          _f('Tên nhà xe', _carrier, hint: 'VD: Nhà xe Hoàng Long'),
          _f('SĐT nhà xe', _carrierPhone, keyboard: TextInputType.phone),
          if (_pickedFromDirectory)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Đã lấy từ danh mục nhà xe. Sửa ở đây chỉ đổi cho địa chỉ '
                'này, danh mục giữ nguyên.',
                style:
                    TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          _f('Ghi chú', _note),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đặt làm mặc định'),
            value: _default,
            onChanged: (v) => setState(() {
              _default = v;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_address.text.trim().isEmpty) {
                toast(context, 'Nhập địa chỉ giao hàng');
                return;
              }
              _dirty = false;
              Navigator.pop(
                context,
                CustomerAddress(
                  id: widget.existing?.id,
                  receiver: _receiver.text.trim(),
                  phone: _phone.text.trim(),
                  address: _address.text.trim(),
                  carrierName: _carrier.text.trim(),
                  carrierPhone: _carrierPhone.text.trim(),
                  note: _note.text.trim(),
                  mapUrl: _map.text.trim(),
                  isDefault: _default,
                ),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
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
              inputFormatters: keyboard == TextInputType.phone
                  ? phoneInputFormatters
                  : null,
              decoration: InputDecoration(hintText: hint)),
        ],
      ),
    );
  }
}
