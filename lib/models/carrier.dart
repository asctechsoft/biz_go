import 'package:uuid/uuid.dart';

/// Nhà xe trong **danh mục** (`carriers`) — sổ tay nhà xe hay dùng, khai một
/// lần ở Cài đặt rồi chọn lại ở form địa chỉ khách hàng.
///
/// Đây CHỈ là danh mục gợi ý: `CustomerAddress.carrierName`/`carrierPhone`
/// vẫn là **chuỗi tự do** đã chép sang (và đơn hàng lại snapshot lần nữa).
/// Nên sửa/xoá nhà xe ở đây KHÔNG đổi địa chỉ khách hay đơn cũ — đúng ý: số
/// đã in trên phiếu thì không được tự nhảy.
class Carrier {
  final String id;
  final String name;
  final String phone;

  Carrier({String? id, required this.name, this.phone = ''})
      : id = id ?? const Uuid().v4();

  factory Carrier.fromMap(String id, Map<String, dynamic> m) => Carrier(
        id: id,
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'nameLower': name.toLowerCase(),
      };

  // Stream tạo instance mới mỗi lần snapshot đổi → so sánh theo `id` để
  // ChoiceChip/Dropdown không mất trạng thái chọn.
  @override
  bool operator ==(Object other) => other is Carrier && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
