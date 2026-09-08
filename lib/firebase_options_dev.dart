// Firebase config của MÔI TRƯỜNG DEV — project dev-asc.
// Số liệu chép từ android/app/google-services_dev.json (bản Gradle đọc nằm ở
// android/app/src/dev/google-services.json). Sửa file json thì sửa cả đây.
//
// Chỉ Android được khai báo: project dev-asc hiện chỉ đăng ký app Android
// (package `dev.asctechsoft`). Nền tảng khác cố tình NÉM lỗi thay vì rơi về
// cấu hình prod — thà build chết còn hơn bản test ghi vào DB khách hàng.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'Môi trường dev (project dev-asc) chỉ có cấu hình Android. '
      'Muốn chạy dev trên web/iOS thì đăng ký app tương ứng trong Firebase '
      'console của dev-asc rồi thêm FirebaseOptions vào firebase_options_dev.dart.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAT1nSNW2jrPER1GaYQatcgfW2QrckRNv4',
    appId: '1:573104976303:android:4ec3bfbc710a030716ff5a',
    messagingSenderId: '573104976303',
    projectId: 'dev-asc',
    storageBucket: 'dev-asc.firebasestorage.app',
  );
}
