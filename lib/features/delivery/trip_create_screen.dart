import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../models/fleet.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class TripCreateScreen extends StatefulWidget {
  const TripCreateScreen({super.key});
  @override
  State<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends State<TripCreateScreen> {
  DateTime _runDate = DateTime.now();
  TimeOfDay _departure = const TimeOfDay(hour: 7, minute: 30);
  Vehicle? _vehicle;
  AppUser? _driver; // tài khoản Giao hàng
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_vehicle == null || _driver == null) {
      toast(context, 'Chọn xe và tài xế');
      return;
    }
    setState(() => _busy = true);
    final db = context.read<Db>();
    final planned = DateTime(
      _runDate.year,
      _runDate.month,
      _runDate.day,
      _departure.hour,
      _departure.minute,
    );
    try {
      final trip = await db.createTrip(
        runDate: _runDate,
        vehicle: _vehicle!,
        driver: Driver(
          id: _driver!.id, // uid tài khoản → app tài xế lọc chuyến theo id này
          name: _driver!.name,
          phone: _driver!.phone,
        ),
        plannedDeparture: planned,
        note: _note.text.trim(),
      );
      if (mounted) {
        toast(context, 'Đã tạo chuyến ${trip.code}');
        context.pushReplacement('/trips/${trip.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Lỗi tạo chuyến: $e');
      }
    }
  }

  Widget _emptyNotice(String message, String route) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () => context.push(route),
            child: const Text('Tạo ngay'),
          ),
        ],
      ),
    );
  }

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

  Future<Vehicle?> _pickVehicle(List<Vehicle> vehicles) {
    return showModalBottomSheet<Vehicle>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Chọn xe',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final v in vehicles)
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined,
                    color: AppColors.primary),
                title: Text(v.plate,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${v.type} · ${v.capacityKg}kg · ${v.status}'),
                trailing: _vehicle?.id == v.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<AppUser?> _pickDriver(List<AppUser> drivers) {
    return showModalBottomSheet<AppUser>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Chọn tài xế',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final d in drivers)
              ListTile(
                leading: Avatar(d.name, size: 38),
                title: Text(d.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(d.phone),
                trailing: _driver?.id == d.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo chuyến xe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ngày chạy'),
            trailing: Text(fmtDate(_runDate)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _runDate,
                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (d != null) setState(() => _runDate = d);
            },
          ),
          StreamBuilder<List<Vehicle>>(
            stream: db.vehicles(),
            builder: (context, snap) {
              final vehicles = snap.data ?? [];
              if (snap.hasData && vehicles.isEmpty) {
                return _emptyNotice('Chưa có xe nào trong hệ thống.', '/fleet');
              }
              return _selectField(
                label: 'Chọn xe',
                value: _vehicle == null
                    ? ''
                    : '${_vehicle!.plate} · ${_vehicle!.type}',
                onTap: () async {
                  final v = await _pickVehicle(vehicles);
                  if (v != null) setState(() => _vehicle = v);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<AppUser>>(
            stream: db.usersByRole(UserRole.shipper),
            builder: (context, snap) {
              final drivers = snap.data ?? [];
              if (snap.hasData && drivers.isEmpty) {
                return _emptyNotice(
                    'Chưa có tài khoản Giao hàng. Tạo ở Quản lý người dùng.',
                    '/users');
              }
              return _selectField(
                label: 'Chọn tài xế',
                value: _driver == null
                    ? ''
                    : '${_driver!.name} · ${_driver!.phone}',
                onTap: () async {
                  final d = await _pickDriver(drivers);
                  if (d != null) setState(() => _driver = d);
                },
              );
            },
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Giờ dự kiến xuất phát'),
            trailing: Text(_departure.format(context)),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _departure,
              );
              if (t != null) setState(() => _departure = t);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Ghi chú'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Lưu chuyến'),
          ),
        ],
      ),
    );
  }
}
