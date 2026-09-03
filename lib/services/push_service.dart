import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Quản lý FCM token: xin quyền, lưu token vào `users/{uid}.fcmTokens` để
/// noti-server (Node) gửi push theo vai trò. Xoá token khi đăng xuất.
class PushService {
  final _fm = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  /// Gọi sau khi đăng nhập thành công.
  Future<void> registerFor(String uid) async {
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await _fm.getToken();
      if (token != null) await _saveToken(uid, token);
      // Token có thể đổi — lưu lại mỗi lần refresh.
      _fm.onTokenRefresh.listen((t) => _saveToken(uid, t));
    } catch (e) {
      debugPrint('PushService.registerFor error: $e');
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Gọi trước khi đăng xuất.
  Future<void> unregister(String uid) async {
    try {
      final token = await _fm.getToken();
      if (token != null) {
        await _db.collection('users').doc(uid).set({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('PushService.unregister error: $e');
    }
  }
}
