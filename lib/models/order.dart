import '../core/enums.dart';

/// Snapshot of one line in the cart (spec §7.3).
class OrderItem {
  final String productId;
  final String variantId;
  final String packagingId;
  final String productName;
  final String variantName;
  final String packagingName;
  final int quantity;
  final int unitPrice; // snapshot at order time
  final String? imagePath;

  OrderItem({
    required this.productId,
    required this.variantId,
    required this.packagingId,
    required this.productName,
    required this.variantName,
    required this.packagingName,
    required this.quantity,
    required this.unitPrice,
    this.imagePath,
  });

  int get lineTotal => quantity * unitPrice;

  String get displayName => '$productName $packagingName';

  /// Tên để phân biệt các dòng hàng cùng sản phẩm: chính là **phân loại**
  /// ("Cùi bưởi tươi", "Cùi đẹp"...). Cùng một sản phẩm + quy cách có thể có
  /// nhiều phân loại giá khác nhau, thiếu nó là mấy dòng trông y hệt nhau.
  String get variantLabel => variantName.trim().isEmpty ? productName : variantName;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
    productId: m['productId'] ?? '',
    variantId: m['variantId'] ?? '',
    packagingId: m['packagingId'] ?? '',
    productName: m['productName'] ?? '',
    variantName: m['variantName'] ?? '',
    packagingName: m['packagingName'] ?? '',
    quantity: (m['quantity'] ?? 0) as int,
    unitPrice: (m['unitPrice'] ?? 0) as int,
    imagePath: m['imagePath'],
  );

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'variantId': variantId,
    'packagingId': packagingId,
    'productName': productName,
    'variantName': variantName,
    'packagingName': packagingName,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'lineTotal': lineTotal,
    'imagePath': imagePath,
  };

  OrderItem copyWith({int? quantity, int? unitPrice}) => OrderItem(
    productId: productId,
    variantId: variantId,
    packagingId: packagingId,
    productName: productName,
    variantName: variantName,
    packagingName: packagingName,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    imagePath: imagePath,
  );
}

/// One entry in the order timeline (spec §14). Append-only.
class TimelineEvent {
  final DateTime at;
  final String title;
  final String note;
  final String actorId;
  final String actorName;

  TimelineEvent({
    required this.at,
    required this.title,
    this.note = '',
    this.actorId = '',
    this.actorName = '',
  });

  factory TimelineEvent.fromMap(Map<String, dynamic> m) => TimelineEvent(
    at: DateTime.fromMillisecondsSinceEpoch((m['at'] ?? 0) as int),
    title: m['title'] ?? '',
    note: m['note'] ?? '',
    actorId: m['actorId'] ?? '',
    actorName: m['actorName'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'note': note,
    'actorId': actorId,
    'actorName': actorName,
  };
}

class Order {
  final String id;
  final String code; // DH260903-001
  final DateTime createdAt;

  final String customerId;
  final String customerName;
  final String customerPhone;

  // Snapshot of delivery address (spec §6.2).
  final String deliveryAddress;
  final String deliveryReceiver;
  final String deliveryPhone;
  final String deliveryMapUrl; // link Google Maps (snapshot lúc tạo đơn)

  /// Nhà xe chở đơn này — **snapshot** lúc tạo đơn như địa chỉ. Khách đổi nhà
  /// xe sau đó thì đơn cũ vẫn in đúng nhà xe đã gửi.
  final String deliveryCarrierName;
  final String deliveryCarrierPhone;

  final List<OrderItem> items;

  final int shippingFee;
  final int discount;
  final int prepaid; // khách trả trước tại thời điểm tạo

  final OrderStatus orderStatus;
  final WarehouseStatus warehouseStatus;
  final DeliveryStatus deliveryStatus;
  final PaymentStatus paymentStatus;

  final int paidAmount; // tổng đã thu (từ payments)

  /// Giờ **dự kiến xuất phát** do người tạo đơn đặt — dùng để xếp thứ tự đơn
  /// nào đi trước. `null` = không đặt, khi đó xếp theo giờ tạo đơn (xem
  /// [departAt]). KHÔNG phải giờ xuất phát thật: giờ thật nằm ở timeline.
  final DateTime? plannedDepartAt;

  final String note; // ghi chú nội bộ
  final String deliveryNote; // ghi chú giao hàng
  final String? cancelReason;

  // packing info
  /// Mã kiện `KIyyMMdd-NNN`, sinh tự động khi đóng hàng xong.
  final String? packageCode;

  /// Số kiện — LEGACY: trước đây nhập tay, giờ thay bằng [packageCode].
  /// Giữ lại để đơn đã đóng trước khi đổi vẫn hiển thị đúng.
  final int? packageCount;

  /// Khối lượng, LUÔN quy về **kg**. [weightUnit] chỉ để hiển thị lại đúng
  /// đơn vị đã nhập (`kg` / `tạ` / `tấn`) — xem `fmtWeight()`.
  final double? weightKg;
  final String weightUnit;

  /// Đơn gấp — Chủ tự đánh dấu, ghim lên đầu danh sách trong ngày.
  final bool priority;

  final List<TimelineEvent> timeline;

  Order({
    required this.id,
    required this.code,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.deliveryReceiver,
    required this.deliveryPhone,
    this.deliveryMapUrl = '',
    this.deliveryCarrierName = '',
    this.deliveryCarrierPhone = '',
    required this.items,
    this.shippingFee = 0,
    this.discount = 0,
    this.prepaid = 0,
    this.orderStatus = OrderStatus.NEW,
    this.warehouseStatus = WarehouseStatus.WAITING,
    this.deliveryStatus = DeliveryStatus.WAITING_ASSIGNMENT,
    this.paymentStatus = PaymentStatus.UNPAID,
    this.paidAmount = 0,
    this.plannedDepartAt,
    this.note = '',
    this.deliveryNote = '',
    this.cancelReason,
    this.packageCode,
    this.packageCount,
    this.weightKg,
    this.weightUnit = 'kg',
    this.priority = false,
    this.timeline = const [],
  });

  /// Có nhà xe chở hay giao thẳng — quyết định hiện dòng nhà xe trên phiếu.
  bool get hasCarrier => deliveryCarrierName.trim().isNotEmpty;

  /// Mốc dùng để xếp hàng đợi xuất phát: giờ đã đặt, không có thì giờ tạo đơn
  /// (đặt trước đi trước). Có nó thì mọi chỗ sắp xếp dùng chung một quy tắc.
  DateTime get departAt => plannedDepartAt ?? createdAt;

  /// So sánh thứ tự đi: đơn **GẤP** luôn lên đầu, còn lại theo [departAt] tăng
  /// dần. Dùng cho mọi danh sách hàng đợi (kho, giao hàng).
  static int byDepartOrder(Order a, Order b) {
    if (a.priority != b.priority) return a.priority ? -1 : 1;
    return a.departAt.compareTo(b.departAt);
  }

  // §7.2 money formulas
  int get subtotal => items.fold(0, (s, i) => s + i.lineTotal);
  int get total => subtotal + shippingFee - discount;
  int get remaining => total - paidAmount; // còn phải thu

  factory Order.fromMap(String id, Map<String, dynamic> m) => Order(
    id: id,
    code: m['code'] ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] ?? 0) as int,
    ),
    customerId: m['customerId'] ?? '',
    customerName: m['customerName'] ?? '',
    customerPhone: m['customerPhone'] ?? '',
    deliveryAddress: m['deliveryAddress'] ?? '',
    deliveryMapUrl: m['deliveryMapUrl'] ?? '',
    deliveryCarrierName: m['deliveryCarrierName'] ?? '',
    deliveryCarrierPhone: m['deliveryCarrierPhone'] ?? '',
    deliveryReceiver: m['deliveryReceiver'] ?? '',
    deliveryPhone: m['deliveryPhone'] ?? '',
    items: ((m['items'] as List?) ?? [])
        .map((e) => OrderItem.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
    shippingFee: (m['shippingFee'] ?? 0) as int,
    discount: (m['discount'] ?? 0) as int,
    prepaid: (m['prepaid'] ?? 0) as int,
    orderStatus: enumFromName(
      OrderStatus.values,
      m['orderStatus'],
      OrderStatus.NEW,
    ),
    warehouseStatus: enumFromName(
      WarehouseStatus.values,
      m['warehouseStatus'],
      WarehouseStatus.WAITING,
    ),
    deliveryStatus: enumFromName(
      DeliveryStatus.values,
      m['deliveryStatus'],
      DeliveryStatus.WAITING_ASSIGNMENT,
    ),
    paymentStatus: enumFromName(
      PaymentStatus.values,
      m['paymentStatus'],
      PaymentStatus.UNPAID,
    ),
    paidAmount: (m['paidAmount'] ?? 0) as int,
    plannedDepartAt: m['plannedDepartAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['plannedDepartAt'] as int),
    note: m['note'] ?? '',
    deliveryNote: m['deliveryNote'] ?? '',
    cancelReason: m['cancelReason'],
    packageCode: m['packageCode'],
    packageCount: m['packageCount'],
    weightKg: (m['weightKg'] as num?)?.toDouble(),
    weightUnit: m['weightUnit'] ?? 'kg',
    priority: m['priority'] == true,
    timeline: ((m['timeline'] as List?) ?? [])
        .map((e) => TimelineEvent.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
  );

  Map<String, dynamic> toMap() => {
    'code': code,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'deliveryAddress': deliveryAddress,
    'deliveryMapUrl': deliveryMapUrl,
    'deliveryCarrierName': deliveryCarrierName,
    'deliveryCarrierPhone': deliveryCarrierPhone,
    'deliveryReceiver': deliveryReceiver,
    'deliveryPhone': deliveryPhone,
    'items': items.map((e) => e.toMap()).toList(),
    'shippingFee': shippingFee,
    'discount': discount,
    'prepaid': prepaid,
    'subtotal': subtotal,
    'total': total,
    'orderStatus': orderStatus.name,
    'warehouseStatus': warehouseStatus.name,
    'deliveryStatus': deliveryStatus.name,
    'paymentStatus': paymentStatus.name,
    'paidAmount': paidAmount,
    'remaining': remaining,
    'plannedDepartAt': plannedDepartAt?.millisecondsSinceEpoch,
    'note': note,
    'deliveryNote': deliveryNote,
    'cancelReason': cancelReason,
    'packageCode': packageCode,
    'packageCount': packageCount,
    'weightKg': weightKg,
    'weightUnit': weightUnit,
    'priority': priority,
    'timeline': timeline.map((e) => e.toMap()).toList(),
  };
}
