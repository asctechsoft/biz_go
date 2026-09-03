import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/fleet.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

const _vehicleTypes = [
  'Táº£i 1.25T',
  'Táº£i 2.5T',
  'Táº£i 5T',
  'Van',
  'Xe bÃ¡n táº£i',
  'Xe mÃ¡y',
];
const _vehicleStatuses = ['Ráº£nh', 'Äang cháº¡y', 'Báº£o dÆ°á»¡ng'];

/// Auto-format biá»ƒn sá»‘ khi gÃµ: viáº¿t HOA, chá»‰ chá»¯+sá»‘, chÃ¨n '-' sau 3 kÃ½ tá»±.
/// VD gÃµ "29c12345" â†’ "29C-12345".
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

/// Ã” "chá»n" trÃ´ng nhÆ° text field, báº¥m vÃ o má»Ÿ danh sÃ¡ch chá»n (xá»• tá»« dÆ°á»›i lÃªn,
/// khÃ´ng Ä‘Ã¨ lÃªn field khÃ¡c).
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
            child: Text(value.isEmpty ? 'Chá»n...' : value,
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

/// Â§10.1 â€” quáº£n lÃ½ xe (thÃªm/sá»­a/xÃ³a). TÃ i xáº¿ = tÃ i khoáº£n Giao hÃ ng, quáº£n á»Ÿ
/// mÃ n Quáº£n lÃ½ ngÆ°á»i dÃ¹ng.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quáº£n lÃ½ xe')),
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
            return const EmptyState(text: 'ChÆ°a cÃ³ xe');
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
                  subtitle: Text('${v.type} Â· ${v.capacityKg}kg Â· ${v.status}'),
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
    String status = existing?.status ?? 'Ráº£nh';
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'ThÃªm xe' : 'Sá»­a xe',
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
                        labelText: 'Biá»ƒn sá»‘', hintText: '29C-12345')),
                const SizedBox(height: 12),
                _selectField(
                  label: 'Loáº¡i xe',
                  value: type,
                  onTap: () async {
                    final v = await _pickFromList(
                        ctx, 'Chá»n loáº¡i xe', _vehicleTypes, type);
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
                        const InputDecoration(labelText: 'Táº£i trá»ng (kg)')),
                const SizedBox(height: 12),
                _selectField(
                  label: 'Tráº¡ng thÃ¡i',
                  value: status,
                  onTap: () async {
                    final v = await _pickFromList(
                        ctx, 'Tráº¡ng thÃ¡i xe', _vehicleStatuses, status);
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
                          },
                          child: const Text('XÃ³a'),
                        ),
                      ),
                    if (existing != null) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (plateC.text.trim().isEmpty) {
                            setSheet(() => error = 'Vui lÃ²ng nháº­p biá»ƒn sá»‘ xe');
                            return;
                          }
                          if (type.isEmpty) {
                            setSheet(() => error = 'Vui lÃ²ng chá»n loáº¡i xe');
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
                        },
                        child: const Text('LÆ°u'),
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
