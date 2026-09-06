// Firebase config generated from google-services.json (project bizgo-877df).
// Android is the primary target. Other platforms fall back to the Android config.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  // Cấu hình app web (Firebase console › Project settings › Web app).
  // Dùng CÙNG project bizgo-877df với Android → chung Firestore/Auth/dữ liệu.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB0JcrzqsnEEykxNHXCFeFvtMcHn068Dic',
    appId: '1:844322247816:web:b837e195392346a2a73b3d',
    messagingSenderId: '844322247816',
    projectId: 'bizgo-877df',
    authDomain: 'bizgo-877df.firebaseapp.com',
    storageBucket: 'bizgo-877df.firebasestorage.app',
    measurementId: 'G-4EYMJXVR6L',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDLRIRx756tGgu1yYGAqudw59wvrFLuw3I',
    appId: '1:844322247816:android:f1949c2dfede9ecba73b3d',
    messagingSenderId: '844322247816',
    projectId: 'bizgo-877df',
    storageBucket: 'bizgo-877df.firebasestorage.app',
  );

  // iOS not configured with a real GoogleService-Info.plist yet; reuses shared
  // project keys so firebase_core init does not crash during development.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDLRIRx756tGgu1yYGAqudw59wvrFLuw3I',
    appId: '1:844322247816:android:f1949c2dfede9ecba73b3d',
    messagingSenderId: '844322247816',
    projectId: 'bizgo-877df',
    storageBucket: 'bizgo-877df.firebasestorage.app',
    iosBundleId: 'com.asc.bizgo',
  );
}
