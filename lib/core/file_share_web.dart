import 'dart:html' as html;
import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Bản web: tải file về qua trình duyệt (không có `dart:io`/hộp chia sẻ).
Future<void> saveAndShareBytes(
  Uint8List bytes, {
  required String filename,
  required String mime,
  required String text,
}) async {
  final blob = html.Blob(<Object>[bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Bản web: mở hộp thoại in của trình duyệt với đúng nội dung PDF → máy tính
/// nối máy in in thẳng.
Future<void> printPdfBytes(Uint8List bytes, {required String docName}) async {
  await Printing.layoutPdf(onLayout: (_) async => bytes, name: docName);
}
