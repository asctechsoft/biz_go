/// Thông tin + tuỳ chọn phiếu giao hàng (§8). Lưu ở `meta/shop`.
class ShopInfo {
  /// Tiêu đề phiếu — tên cửa hàng, ví dụ "Cùi Bưởi Minh Thư".
  final String title;

  /// SĐT in trên phiếu. Bỏ trống → lấy SĐT của tài khoản Chủ (xem
  /// [Db.shopInfo]), để cài xong là phiếu có số đúng ngay, không phải nhập.
  final String phone;

  /// Ẩn **đơn giá / thành tiền / tổng cộng / cần thu** trên phiếu in.
  ///
  /// Mặc định `true`: phiếu đi kèm hàng thường qua tay nhà xe, người nhận hộ,
  /// nên không in giá là an toàn hơn. Chủ tắt ở Cài đặt phiếu khi cần phiếu
  /// đầy đủ. Người KHÔNG được xem tiền (`Perm.viewMoney`) thì luôn bị ẩn, cài
  /// đặt này không mở lại được.
  final bool hidePrices;

  const ShopInfo({
    required this.title,
    required this.phone,
    this.hidePrices = true,
  });

  static const defaultTitle = 'Cùi Bưởi Minh Thư';

  factory ShopInfo.fromMap(Map<String, dynamic>? m) => ShopInfo(
        title: (m?['title'] as String?)?.trim().isNotEmpty == true
            ? (m!['title'] as String).trim()
            : defaultTitle,
        phone: (m?['phone'] as String?)?.trim() ?? '',
        // Doc cũ chưa có field → mặc định ẩn giá.
        hidePrices: m?['hidePrices'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() =>
      {'title': title, 'phone': phone, 'hidePrices': hidePrices};

  ShopInfo copyWith({String? title, String? phone, bool? hidePrices}) =>
      ShopInfo(
        title: title ?? this.title,
        phone: phone ?? this.phone,
        hidePrices: hidePrices ?? this.hidePrices,
      );
}
