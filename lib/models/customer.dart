import 'package:uuid/uuid.dart';

class CustomerAddress {
  final String id;
  final String label; // Tên địa chỉ: Nhà riêng, Cửa hàng 1...
  final String receiver; // Người nhận
  final String phone;
  final String address;
  final String note;
  final String mapUrl; // link Google Maps (tùy chọn) để mở chỉ đường
  final bool isDefault;

  CustomerAddress({
    String? id,
    required this.label,
    required this.receiver,
    required this.phone,
    required this.address,
    this.note = '',
    this.mapUrl = '',
    this.isDefault = false,
  }) : id = id ?? const Uuid().v4();

  factory CustomerAddress.fromMap(Map<String, dynamic> m) => CustomerAddress(
        id: m['id'],
        label: m['label'] ?? '',
        receiver: m['receiver'] ?? '',
        phone: m['phone'] ?? '',
        address: m['address'] ?? '',
        note: m['note'] ?? '',
        mapUrl: m['mapUrl'] ?? '',
        isDefault: m['isDefault'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'receiver': receiver,
        'phone': phone,
        'address': address,
        'note': note,
        'mapUrl': mapUrl,
        'isDefault': isDefault,
      };

  CustomerAddress copyWith({bool? isDefault}) => CustomerAddress(
        id: id,
        label: label,
        receiver: receiver,
        phone: phone,
        address: address,
        note: note,
        mapUrl: mapUrl,
        isDefault: isDefault ?? this.isDefault,
      );
}

class Customer {
  final String id;
  final String name;
  final String phone;
  final String note;
  final String source; // nguồn khách
  final String? imagePath; // ảnh đại diện (đường dẫn local)
  final List<CustomerAddress> addresses;

  // Aggregates (kept denormalized for the customer detail screen).
  final int totalPurchased; // tổng mua hàng
  final int totalPaid; // tổng đã thanh toán
  final int debt; // công nợ hiện tại
  final int orderCount;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.note = '',
    this.source = '',
    this.imagePath,
    this.addresses = const [],
    this.totalPurchased = 0,
    this.totalPaid = 0,
    this.debt = 0,
    this.orderCount = 0,
  });

  CustomerAddress? get defaultAddress {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
  }

  factory Customer.fromMap(String id, Map<String, dynamic> m) => Customer(
        id: id,
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
        note: m['note'] ?? '',
        source: m['source'] ?? '',
        imagePath: m['imagePath'],
        addresses: ((m['addresses'] as List?) ?? [])
            .map((e) => CustomerAddress.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        totalPurchased: (m['totalPurchased'] ?? 0) as int,
        totalPaid: (m['totalPaid'] ?? 0) as int,
        debt: (m['debt'] ?? 0) as int,
        orderCount: (m['orderCount'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'note': note,
        'source': source,
        'imagePath': imagePath,
        'addresses': addresses.map((e) => e.toMap()).toList(),
        'totalPurchased': totalPurchased,
        'totalPaid': totalPaid,
        'debt': debt,
        'orderCount': orderCount,
        'nameLower': name.toLowerCase(),
      };
}
