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

  /// Chuyến của đúng ngày chạy đang chọn — nguồn để biết xe/tài xế nào rảnh.
  /// Tạo lại mỗi khi đổi ngày (không tạo trong build, tránh re-subscribe).
  late Stream<List<Trip>> _dayTrips;

  @override
  void initState() {
    super.initState();
    _dayTrips = context.read<Db>().tripsOnDate(_runDate);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setRunDate(DateTime d) {
    setState(() {
      _runDate = d;
      _dayTrips = context.read<Db>().tripsOnDate(d);
    });
  }

  /// Xe/tài xế đang bị chuyến chưa xong của ngày đó chiếm → id -> chuyến đó.
  static Map<String, Trip> _busyBy(
      List<Trip> trips, String Function(Trip) key) {
    final out = <String, Trip>{};
    for (final t in trips.where(Db.tripHoldsResources)) {
      final k = key(t);
      if (k.isNotEmpty) out.putIfAbsent(k, () => t);
    }
    return out;
  }

  /// Giá trị đã chọn ở `trailing` của ListTile (ngày chạy, giờ xuất phát).
  /// Phải set tay: mặc định M3 cho trailing cỡ `labelSmall` (~11px) nên bé tí.
  static const _pickedValueStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  /// "CX260904-01 · 07:30" — giữ nguyên chữ hoa của mã chuyến.
  static String _tripLabel(Trip t) {
    final at = t.plannedDeparture ?? t.actualDeparture;
    return '${t.code}${at == null ? '' : ' · ${fmtTime(at)}'}';
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
        // Bỏ tiền tố "Exception: " cho thông báo chặn trùng xe/tài xế.
        toast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Widget _notice(String message, Color color,
      {String? route, String actionLabel = 'Tạo ngay'}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
          if (route != null)
            TextButton(
              onPressed: () => context.push(route),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }

  Widget _emptyNotice(String message, String route) =>
      _notice(message, AppColors.warning, route: route);

  Widget _selectField({
    required String label,
    required String value,
    required VoidCallback onTap,
    String? error,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, errorText: error),
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

  /// Khung chung cho 2 bottom sheet chọn: tiêu đề + cảnh báo + danh sách cuộn.
  Widget _pickerSheet({
    required String title,
    required int busyCount,
    required List<Widget> rows,
  }) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              busyCount == 0
                  ? 'Ngày ${fmtDate(_runDate)} — tất cả đang rảnh'
                  : 'Ngày ${fmtDate(_runDate)} — $busyCount đang chạy chuyến '
                      'chưa xong, không chọn được',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          // Cuộn được: danh sách xe/tài xế dài không làm tràn sheet.
          Flexible(child: SingleChildScrollView(child: Column(children: rows))),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<Vehicle?> _pickVehicle(List<Vehicle> vehicles, Map<String, Trip> busy) {
    // Xe rảnh lên trước cho dễ chọn.
    final sorted = [...vehicles]..sort((a, b) {
        final ba = busy.containsKey(a.id) ? 1 : 0;
        final bb = busy.containsKey(b.id) ? 1 : 0;
        return ba != bb ? ba - bb : a.plate.compareTo(b.plate);
      });
    return showModalBottomSheet<Vehicle>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _pickerSheet(
        title: 'Chọn xe',
        busyCount: vehicles.where((v) => busy.containsKey(v.id)).length,
        rows: [
          for (final v in sorted)
            _resourceRow(
              ctx: ctx,
              leading: Icon(Icons.local_shipping_outlined,
                  color: busy.containsKey(v.id)
                      ? AppColors.textSecondary
                      : AppColors.primary),
              title: v.plate,
              freeSubtitle: '${v.type} · ${v.capacityKg}kg · ${v.status}',
              clash: busy[v.id],
              selected: _vehicle?.id == v.id,
              value: v,
            ),
        ],
      ),
    );
  }

  Future<AppUser?> _pickDriver(List<AppUser> drivers, Map<String, Trip> busy) {
    final sorted = [...drivers]..sort((a, b) {
        final ba = busy.containsKey(a.id) ? 1 : 0;
        final bb = busy.containsKey(b.id) ? 1 : 0;
        return ba != bb ? ba - bb : a.name.compareTo(b.name);
      });
    return showModalBottomSheet<AppUser>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _pickerSheet(
        title: 'Chọn tài xế',
        busyCount: drivers.where((d) => busy.containsKey(d.id)).length,
        rows: [
          for (final d in sorted)
            _resourceRow(
              ctx: ctx,
              leading: Avatar(d.name, size: 38),
              title: d.name,
              freeSubtitle: d.phone,
              clash: busy[d.id],
              selected: _driver?.id == d.id,
              value: d,
            ),
        ],
      ),
    );
  }

  /// Một dòng xe/tài xế. [clash] != null → mờ đi, không bấm được.
  Widget _resourceRow<T>({
    required BuildContext ctx,
    required Widget leading,
    required String title,
    required String freeSubtitle,
    required Trip? clash,
    required bool selected,
    required T value,
  }) {
    final free = clash == null;
    return ListTile(
      enabled: free,
      leading: leading,
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: free ? AppColors.textPrimary : AppColors.textSecondary)),
      subtitle: Text(free ? freeSubtitle : 'Đang chạy ${_tripLabel(clash)}',
          style: TextStyle(color: free ? null : AppColors.danger)),
      trailing: free
          ? (selected ? const Icon(Icons.check, color: AppColors.primary) : null)
          : const Icon(Icons.block, color: AppColors.danger, size: 18),
      onTap: free ? () => Navigator.pop(ctx, value) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo chuyến xe')),
      body: StreamBuilder<List<Trip>>(
        stream: _dayTrips,
        builder: (context, tripSnap) {
          final dayTrips = tripSnap.data ?? const <Trip>[];
          final busyVehicles = _busyBy(dayTrips, (t) => t.vehicleId);
          final busyDrivers = _busyBy(dayTrips, (t) => t.driverId);
          // Đã chọn rồi mới đổi ngày → lựa chọn cũ có thể thành trùng.
          final vClash =
              _vehicle == null ? null : busyVehicles[_vehicle!.id];
          final dClash = _driver == null ? null : busyDrivers[_driver!.id];
          final blocked = vClash != null || dClash != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngày chạy'),
                trailing: Text(fmtDate(_runDate), style: _pickedValueStyle),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _runDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 60)),
                  );
                  if (d != null) _setRunDate(d);
                },
              ),
              StreamBuilder<List<Vehicle>>(
                stream: db.vehicles(),
                builder: (context, snap) {
                  final vehicles = snap.data ?? [];
                  if (snap.hasData && vehicles.isEmpty) {
                    return _emptyNotice(
                        'Chưa có xe nào trong hệ thống.', '/fleet');
                  }
                  final freeCount = vehicles
                      .where((v) => !busyVehicles.containsKey(v.id))
                      .length;
                  if (snap.hasData && freeCount == 0) {
                    return _notice(
                        'Tất cả ${vehicles.length} xe đều đang chạy chuyến chưa '
                        'xong ngày ${fmtDate(_runDate)}. Chọn ngày khác hoặc '
                        'kết thúc chuyến cũ.',
                        AppColors.danger);
                  }
                  return _selectField(
                    label: 'Chọn xe',
                    value: _vehicle == null
                        ? ''
                        : '${_vehicle!.plate} · ${_vehicle!.type}',
                    error: vClash == null
                        ? null
                        : 'Đang chạy ${_tripLabel(vClash)}',
                    onTap: () async {
                      final v = await _pickVehicle(vehicles, busyVehicles);
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
                  final freeCount = drivers
                      .where((d) => !busyDrivers.containsKey(d.id))
                      .length;
                  if (snap.hasData && freeCount == 0) {
                    return _notice(
                        'Tất cả ${drivers.length} tài xế đều đang chạy chuyến '
                        'chưa xong ngày ${fmtDate(_runDate)}.',
                        AppColors.danger);
                  }
                  return _selectField(
                    label: 'Chọn tài xế',
                    value: _driver == null
                        ? ''
                        : '${_driver!.name} · ${_driver!.phone}',
                    error: dClash == null
                        ? null
                        : 'Đang chạy ${_tripLabel(dClash)}',
                    onTap: () async {
                      final d = await _pickDriver(drivers, busyDrivers);
                      if (d != null) setState(() => _driver = d);
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Giờ dự kiến xuất phát'),
                trailing:
                    Text(_departure.format(context), style: _pickedValueStyle),
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
                onPressed: (_busy || blocked) ? null : _save,
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
          );
        },
      ),
    );
  }
}
