/// `ImageService` tách theo nền tảng:
/// - **Android/iOS** (`image_service_io.dart`): chọn ảnh + nén + lưu local,
///   render bằng `dart:io` File. Hành vi CŨ, không đổi.
/// - **Web** (`image_service_web.dart`): tắt lưu ảnh local (web không có
///   filesystem kiểu này); mọi ảnh rơi về placeholder.
///
/// `dart.library.io` không có trên web nên web nhận bản stub → `dart:io` không
/// lọt vào bản web.
library;

export 'image_service_web.dart' if (dart.library.io) 'image_service_io.dart';
