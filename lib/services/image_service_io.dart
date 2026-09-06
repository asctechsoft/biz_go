import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Images are stored LOCALLY (spec requirement), compressed to keep them light.
/// Only the file path is persisted to Firestore.
class ImageService {
  final _picker = ImagePicker();
  bool _busy = false; // chặn gọi picker chồng nhau → tránh already_active

  Future<String?> pickAndCompress({bool fromCamera = false}) async {
    if (_busy) return null; // đang chọn ảnh, bỏ qua lần gọi trùng
    _busy = true;
    try {
      final XFile? picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 90, // first pass; second pass below compresses harder
      );
      if (picked == null) return null;
      return await _compressTo(picked.path);
    } on Exception {
      // already_active hoặc bị hủy giữa chừng → coi như không chọn.
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<String> _compressTo(String srcPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final imgDir = Directory(p.join(dir.path, 'images'));
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);
    final outPath = p.join(imgDir.path, '${const Uuid().v4()}.jpg');

    final result = await FlutterImageCompress.compressAndGetFile(
      srcPath,
      outPath,
      quality: 65,
      minWidth: 1024,
      minHeight: 1024,
      format: CompressFormat.jpeg,
    );
    // Fallback to the original if the native compressor is unavailable.
    if (result == null) {
      final copied = await File(srcPath).copy(outPath);
      return copied.path;
    }
    return result.path;
  }

  static bool exists(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync();

  Future<void> delete(String? path) async {
    if (exists(path)) {
      try {
        await File(path!).delete();
      } catch (_) {}
    }
  }

  /// Widget hiển thị ảnh local. Tách ra đây để `common.dart` không phải import
  /// `dart:io` trực tiếp (bản web dùng stub thay thế).
  static Widget imageWidget(String path, {BoxFit fit = BoxFit.cover}) =>
      Image.file(File(path), fit: fit);

  static ImageProvider imageProvider(String path) => FileImage(File(path));
}
