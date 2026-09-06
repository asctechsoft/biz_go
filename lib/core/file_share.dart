/// Lưu/chia sẻ file (PDF, Excel) + in trực tiếp — tách theo nền tảng.
///
/// - **Android/iO S** (`file_share_io.dart`): ghi file tạm rồi mở hộp chia sẻ
///   `share_plus` như trước (Zalo/Drive/lưu máy). Hành vi CŨ, không đổi.
/// - **Web** (`file_share_web.dart`): tải file về qua trình duyệt; PDF in
///   thẳng ra máy in nối với máy tính (`printing`).
///
/// `dart.library.io` chỉ có trên nền tảng máy (không có trên web) nên bản web
/// được chọn mặc định. Tách kiểu này để `dart:io` KHÔNG lọt vào bản web (web
/// không compile được `dart:io`).
library;

export 'file_share_web.dart' if (dart.library.io) 'file_share_io.dart';
