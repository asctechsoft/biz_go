/// Thông tin cửa hàng in trên phiếu giao hàng (§8). Lưu ở `meta/shop`.
///
/// Chỉ 2 trường vì màn Cài đặt phiếu chỉ cho sửa đúng 2 thứ này.
class ShopInfo {
  /// Tiêu đề phiếu — tên cửa hàng, ví dụ "Cùi Bưởi Minh Thư".
  final String title;

  /// SĐT in trên phiếu. Bỏ trống → lấy SĐT của tài khoản Chủ (xem
  /// [Db.shopInfo]), để cài xong là phiếu có số đúng ngay, không phải nhập.
  final String phone;

  const ShopInfo({required this.title, required this.phone});

  static const defaultTitle = 'Cùi Bưởi Minh Thư';

  factory ShopInfo.fromMap(Map<String, dynamic>? m) => ShopInfo(
        title: (m?['title'] as String?)?.trim().isNotEmpty == true
            ? (m!['title'] as String).trim()
            : defaultTitle,
        phone: (m?['phone'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toMap() => {'title': title, 'phone': phone};

  ShopInfo copyWith({String? title, String? phone}) =>
      ShopInfo(title: title ?? this.title, phone: phone ?? this.phone);
}
