import '../core/enums.dart';

class Vehicle {
  final String id;
  final String plate; // biển số 29C-12345
  final String type; // Tải 1.25T / Van
  final int capacityKg;
  final String defaultDriverId;
  final String status; // Rảnh / Đang chạy / Bảo dưỡng

  Vehicle({
    required this.id,
    required this.plate,
    this.type = '',
    this.capacityKg = 0,
    this.defaultDriverId = '',
    this.status = 'Rảnh',
  });

  factory Vehicle.fromMap(String id, Map<String, dynamic> m) => Vehicle(
        id: id,
        plate: m['plate'] ?? '',
        type: m['type'] ?? '',
        capacityKg: (m['capacityKg'] ?? 0) as int,
        defaultDriverId: m['defaultDriverId'] ?? '',
        status: m['status'] ?? 'Rảnh',
      );

  Map<String, dynamic> toMap() => {
        'plate': plate,
        'type': type,
        'capacityKg': capacityKg,
        'defaultDriverId': defaultDriverId,
        'status': status,
      };

  // So khớp theo id để Dropdown không lỗi khi stream tạo instance mới.
  @override
  bool operator ==(Object other) => other is Vehicle && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Driver {
  final String id;
  final String name;
  final String phone;
  final String defaultVehicleId;
  final String status; // rảnh / đang chạy
  final String? userId; // linked app account

  Driver({
    required this.id,
    required this.name,
    required this.phone,
    this.defaultVehicleId = '',
    this.status = 'Rảnh',
    this.userId,
  });

  factory Driver.fromMap(String id, Map<String, dynamic> m) => Driver(
        id: id,
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
        defaultVehicleId: m['defaultVehicleId'] ?? '',
        status: m['status'] ?? 'Rảnh',
        userId: m['userId'],
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'defaultVehicleId': defaultVehicleId,
        'status': status,
        'userId': userId,
      };

  // So khớp theo id để Dropdown không lỗi khi stream tạo instance mới.
  @override
  bool operator ==(Object other) => other is Driver && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Trip {
  final String id;
  final String code; // CX260903-01
  final DateTime runDate;
  final String vehicleId;
  final String vehiclePlate;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final TripStatus status;
  final DateTime? plannedDeparture;
  final DateTime? actualDeparture;
  final String note;
  final int orderCount;
  final int deliveredCount;

  Trip({
    required this.id,
    required this.code,
    required this.runDate,
    required this.vehicleId,
    required this.vehiclePlate,
    required this.driverId,
    required this.driverName,
    this.driverPhone = '',
    this.status = TripStatus.DRAFT,
    this.plannedDeparture,
    this.actualDeparture,
    this.note = '',
    this.orderCount = 0,
    this.deliveredCount = 0,
  });

  int get remainingCount => orderCount - deliveredCount;

  factory Trip.fromMap(String id, Map<String, dynamic> m) => Trip(
        id: id,
        code: m['code'] ?? '',
        runDate: DateTime.fromMillisecondsSinceEpoch((m['runDate'] ?? 0) as int),
        vehicleId: m['vehicleId'] ?? '',
        vehiclePlate: m['vehiclePlate'] ?? '',
        driverId: m['driverId'] ?? '',
        driverName: m['driverName'] ?? '',
        driverPhone: m['driverPhone'] ?? '',
        status: enumFromName(TripStatus.values, m['status'], TripStatus.DRAFT),
        plannedDeparture: m['plannedDeparture'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['plannedDeparture'] as int),
        actualDeparture: m['actualDeparture'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['actualDeparture'] as int),
        note: m['note'] ?? '',
        orderCount: (m['orderCount'] ?? 0) as int,
        deliveredCount: (m['deliveredCount'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'runDate': runDate.millisecondsSinceEpoch,
        'vehicleId': vehicleId,
        'vehiclePlate': vehiclePlate,
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'status': status.name,
        'plannedDeparture': plannedDeparture?.millisecondsSinceEpoch,
        'actualDeparture': actualDeparture?.millisecondsSinceEpoch,
        'note': note,
        'orderCount': orderCount,
        'deliveredCount': deliveredCount,
      };
}
