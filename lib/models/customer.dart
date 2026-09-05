import 'package:uuid/uuid.dart';

class CustomerAddress {
  final String id;
  final String receiver; // Người nhận
  final String phone;
  final String address;

  /// Nhà xe chở hàng tới địa chỉ này (gửi hàng qua nhà xe là chuyện thường ở
  /// tuyến tỉnh). Để trống nếu giao thẳng.
  final String carrierName;
  final String carrierPhone;

  final String note;
  final String mapUrl; // link Google Maps (tùy chọn) để mở chỉ đường
  final bool isDefault;

  CustomerAddress({
    String? id,
    required this.receiver,
    required this.phone,
    required this.address,
    this.carrierName = '',
    this.carrierPhone = '',
    this.note = '',
    this.mapUrl = '',
    this.isDefault = false,
  }) : id = id ?? const Uuid().v4();

  /// Có khai nhà xe không — dùng để quyết định hiện dòng nhà xe trên phiếu.
  bool get hasCarrier => carrierName.trim().isNotEmpty;

  // `label` (Tên địa chỉ) đã bỏ — địa chỉ tự nó đủ nhận biết rồi. Doc cũ còn
  // field đó trong Firestore thì cứ để, không đọc tới nữa.
  factory CustomerAddress.fromMap(Map<String, dynamic> m) => CustomerAddress(
        id: m['id'],
        receiver: m['receiver'] ?? '',
        phone: m['phone'] ?? '',
        address: m['address'] ?? '',
        carrierName: m['carrierName'] ?? '',
        carrierPhone: m['carrierPhone'] ?? '',
        note: m['note'] ?? '',
        mapUrl: m['mapUrl'] ?? '',
        isDefault: m['isDefault'] ?? false,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'receiver': receiver,
        'phone': phone,
        'address': address,
        'carrierName': carrierName,
        'carrierPhone': carrierPhone,
        'note': note,
        'mapUrl': mapUrl,
        'isDefault': isDefault,
      };

  CustomerAddress copyWith({bool? isDefault}) => CustomerAddress(
        id: id,
        receiver: receiver,
        phone: phone,
        address: address,
        carrierName: carrierName,
        carrierPhone: carrierPhone,
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
