import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Bản web: KHÔNG lưu ảnh local (không có filesystem như máy). Upload ảnh bị
/// tắt ở `pickImage` (báo cho người dùng), nên mọi ảnh coi như không tồn tại →
/// chỗ nào cũng rơi về placeholder. Các hàm render chỉ để COMPILE, không chạy.
class ImageService {
  Future<String?> pickAndCompress({bool fromCamera = false}) async => null;

  static bool exists(String? path) => false;

  Future<void> delete(String? path) async {}

  static Widget imageWidget(String path, {BoxFit fit = BoxFit.cover}) =>
      const SizedBox.shrink();

  static ImageProvider imageProvider(String path) => MemoryImage(Uint8List(0));
}
