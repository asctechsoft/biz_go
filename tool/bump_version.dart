// Tăng số phiên bản trong `pubspec.yaml`. CHẠY TRƯỚC MỖI LẦN BUILD BẢN PRODUCT.
//
//   dart run tool/bump_version.dart          → 1.0.0+1  ->  1.0.0+2   (chỉ build)
//   dart run tool/bump_version.dart patch    → 1.0.0+1  ->  1.0.1+2
//   dart run tool/bump_version.dart minor    → 1.0.3+7  ->  1.1.0+8
//   dart run tool/bump_version.dart major    → 1.4.2+9  ->  2.0.0+10
//
// `version: X.Y.Z+N` trong pubspec là NGUỒN DUY NHẤT: Flutter đổ X.Y.Z thành
// versionName và N thành versionCode của APK, còn app đọc lại đúng số đó qua
// `package_info_plus` để hiện ở Cài đặt › Phiên bản. Không gõ số ở chỗ nào khác.
//
// **Số build (N) LUÔN tăng**, kể cả khi không đổi X.Y.Z — Google Play từ chối
// bản có versionCode không lớn hơn bản đã nộp, và số này là cách duy nhất phân
// biệt 2 bản cùng tên phiên bản khi khách báo lỗi.
import 'dart:io';

const _usage = 'Cách dùng: dart run tool/bump_version.dart [patch|minor|major]';

void main(List<String> args) {
  final part = args.isEmpty ? 'build' : args.first.toLowerCase();
  if (!const ['build', 'patch', 'minor', 'major'].contains(part)) {
    stderr.writeln('Không hiểu "$part".\n$_usage');
    exit(64);
  }

  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('Không thấy pubspec.yaml — chạy lệnh từ thư mục gốc của repo.');
    exit(66);
  }

  final lines = file.readAsLinesSync();
  final idx = lines.indexWhere((l) => l.startsWith('version:'));
  if (idx < 0) {
    stderr.writeln('pubspec.yaml không có dòng "version:".');
    exit(65);
  }

  // Dạng bắt buộc: version: X.Y.Z+N
  final m = RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
      .firstMatch(lines[idx]);
  if (m == null) {
    stderr.writeln('Dòng version không đúng dạng X.Y.Z+N: "${lines[idx]}"');
    exit(65);
  }

  var major = int.parse(m.group(1)!);
  var minor = int.parse(m.group(2)!);
  var patch = int.parse(m.group(3)!);
  final build = int.parse(m.group(4)!) + 1; // luôn +1

  switch (part) {
    case 'major':
      major++;
      minor = 0;
      patch = 0;
    case 'minor':
      minor++;
      patch = 0;
    case 'patch':
      patch++;
  }

  final before = '$major.$minor.$patch';
  final next = 'version: $major.$minor.$patch+$build';
  lines[idx] = next;
  file.writeAsStringSync('${lines.join('\n')}\n');

  stdout.writeln('${m.group(0)!.trim()}  ->  $next');
  stdout.writeln('Phiên bản hiện lên app: $before (build $build)');
}
