// Chọn Firebase project theo flavor đang build.
//
// `appFlavor` do chính Flutter tool ghi vào bản build từ cờ `--flavor`, nên nó
// KHÔNG THỂ lệch với google-services.json mà Gradle đã nhúng: cùng một nguồn
// sự thật cho tầng native và tầng Dart. Đừng thay bằng `--dart-define` tự đặt —
// quên truyền một lần là bản dev nói chuyện với DB khách hàng.
//
//   --flavor dev     → dev-asc     (Firestore/Auth để test, xoá thoải mái)
//   --flavor product → bizgo-877df (DỮ LIỆU THẬT CỦA KHÁCH HÀNG)
//
// Web không có flavor (`appFlavor == null`) → dùng cấu hình prod như trước.
//
// MỌI chỗ gọi `Firebase.initializeApp` phải dùng `firebaseOptions` ở đây, kể cả
// FirebaseApp phụ `admin_ops` trong `AuthService` — app phụ buộc phải truyền
// options tay, để sót một chỗ là bản dev tạo tài khoản thẳng vào project thật.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/services.dart' show appFlavor;

import '../firebase_options.dart';
import '../firebase_options_dev.dart';

/// Tên flavor môi trường test, khớp `productFlavors` trong build.gradle.kts.
const String kDevFlavor = 'dev';

/// Đang chạy bản dev (project dev-asc) hay không.
bool get isDevEnv => appFlavor == kDevFlavor;

/// Nhãn ngắn để hiện trên UI/log khi cần phân biệt môi trường.
String get envLabel => isDevEnv ? 'DEV' : 'PROD';

/// Cấu hình Firebase của môi trường đang build.
FirebaseOptions get firebaseOptions => isDevEnv
    ? DevFirebaseOptions.currentPlatform
    : DefaultFirebaseOptions.currentPlatform;
