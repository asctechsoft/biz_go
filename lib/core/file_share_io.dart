import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Bản Android/iOS: ghi file tạm rồi mở hộp chia sẻ (giữ nguyên luồng cũ).
Future<void> saveAndShareBytes(
  Uint8List bytes, {
  required String filename,
  required String mime,
  required String text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: mime)], text: text);
}

/// In trực tiếp chỉ dùng cho bản web. Trên máy, nút In vẫn theo luồng cũ và
/// KHÔNG gọi hàm này — để phòng gọi nhầm thì báo lỗi rõ.
Future<void> printPdfBytes(Uint8List bytes, {required String docName}) async {
  throw UnsupportedError('In trực tiếp chỉ hỗ trợ trên bản web');
}
