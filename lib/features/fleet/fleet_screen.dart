import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/fleet.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

const _vehicleTypes = [
  'Tải 1.25T',
  'Tải 2.5T',
  'Tải 5T',
  'Van',
  'Xe bán tải',
  'Xe máy',
];
const _vehicleStatuses = ['Rảnh', 'Đang chạy', 'Bảo dưỡng'];

/// Auto-format biển số khi gõ: viết HOA, chỉ chữ+số, chèn '-' sau 3 ký tự.
/// VD gõ "29c12345" → "29C-12345".
class _PlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var raw = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.length > 8) raw = raw.substring(0, 8);
    final out = raw.length > 3 ? '${raw.substring(0, 3)}-${raw.substring(3)}' : raw;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

/// Ô "chọn" trông như text field, bấm vào mở danh sách chọn (xổ từ dưới lên,
/// không đè lên field khác).
Widget _selectField({
  required String label,
  required String value,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Text(value.isEmpty ? 'Chọn...' : value,
                style: TextStyle(
                    color: value.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.textPrimary)),
          ),
          const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
        ],
      ),
    ),
  );
}

Widget _errorBanner(String? message) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message ?? '',
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Future<String?> _pickFromList(
    BuildContext context, String title, List<String> options, String current) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          for (final o in options)
            ListTile(
              title: Text(o),
              trailing: o == current
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, o),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// §10.1 — quản lý xe (thêm/sửa/xóa). Tài xế = tài khoản Giao hàng, quản ở
/// màn Quản lý người dùng.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý xe')),
      body: _VehicleTab(db: db),
    );
  }
}

class _VehicleTab extends StatelessWidget {
  final Db db;
  const _VehicleTab({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Vehicle>>(
        stream: db.vehicles(),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (snap.hasData && list.isEmpty) {
            return const EmptyState(text: 'Chưa có xe');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final v = list[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined,
                      color: AppColors.primary),
                  title: Text(v.plate,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${v.type} · ${v.capacityKg}kg · ${v.status}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(context, v),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Vehicle? existing) async {
    final plateC = TextEditingController(text: existing?.plate ?? '');
    final capC = TextEditingController(
        text: existing == null ? '' : '${existing.capacityKg}');
    String type = existing?.type ?? '';
    String status = existing?.status ?? 'Rảnh';
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Thêm xe' : 'Sửa xe',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                if (error != null) ...[
                  _errorBanner(error),
                  const SizedBox(height: 12),
                ],
                TextField(
                    controller: plateC,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_PlateFormatter()],
                    onChanged: (_) {
                      if (error != null) setSheet(() => error = null);
                    },
                    decoration: const InputDecoration(
                        labelText: 'Biển số', hintText: '29C-12345')),
                const SizedBox(height: 12),
                _selectField(
                  label: 'Loại xe',
                  value: type,
                  onTap: () async {
                    final v = await _pickFromList(
                        ctx, 'Chọn loại xe', _vehicleTypes, type);
                    if (v != null) {
                      setSheet(() {
                        type = v;
                        error = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: capC,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Tải trọng (kg)')),
                const SizedBox(height: 12),
                _selectField(
                  label: 'Trạng thái',
                  value: status,
                  onTap: () async {
                    final v = await _pickFromList(
                        ctx, 'Trạng thái xe', _vehicleStatuses, status);
                    if (v != null) setSheet(() => status = v);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (existing != null)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger)),
                          onPressed: () async {
                            await db.deleteVehicle(existing.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) toast(context, 'Đã xóa xe');
                          },
                          child: const Text('Xóa'),
                        ),
                      ),
                    if (existing != null) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (plateC.text.trim().isEmpty) {
                            setSheet(() => error = 'Vui lòng nhập biển số xe');
                            return;
                          }
                          if (type.isEmpty) {
                            setSheet(() => error = 'Vui lòng chọn loại xe');
                            return;
                          }
                          await db.upsertVehicle(Vehicle(
                            id: existing?.id ?? '',
                            plate: plateC.text.trim(),
                            type: type,
                            capacityKg: int.tryParse(capC.text
                                    .replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0,
                            defaultDriverId: existing?.defaultDriverId ?? '',
                            status: status,
                          ));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            toast(context,
                                existing == null ? 'Đã thêm xe' : 'Đã lưu xe');
                          }
                        },
                        child: const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
