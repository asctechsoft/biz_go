import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'sound_service.dart';

/// Quản lý FCM token: xin quyền, lưu token vào `users/{uid}.fcmTokens` để
/// noti-server (Node) gửi push theo vai trò. Xoá token khi đăng xuất.
class PushService {
  final _fm = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  StreamSubscription<RemoteMessage>? _fgSub;

  /// Gọi sau khi đăng nhập thành công.
  Future<void> registerFor(String uid) async {
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await _fm.getToken();
      if (token != null) await _saveToken(uid, token);
      // Token có thể đổi — lưu lại mỗi lần refresh.
      _fm.onTokenRefresh.listen((t) => _saveToken(uid, t));
      _listenForeground();
    } catch (e) {
      debugPrint('PushService.registerFor error: $e');
    }
  }

  /// App đang MỞ thì FCM không tự kêu và không tự hiện banner (thiết kế của
  /// Firebase) — nghe `onMessage` để tự phát tiếng báo có đơn/thông báo mới.
  ///
  /// [registerFor] bị gọi lại nhiều lần (đăng nhập lại, đổi uid ở
  /// `AuthProvider`) nên phải chặn đăng ký trùng, kẻo 1 push kêu nhiều tiếng.
  void _listenForeground() {
    if (_fgSub != null) return;
    _fgSub = FirebaseMessaging.onMessage.listen(
      (_) => SoundService.cash(),
      onError: (e) => debugPrint('PushService.onMessage error: $e'),
    );
  }

  Future<void> _saveToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Gọi trước khi đăng xuất.
  Future<void> unregister(String uid) async {
    await _fgSub?.cancel();
    _fgSub = null;
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

  /// Chỉ bỏ token trên máy, KHÔNG ghi Firestore. Dùng khi vừa xoá sạch
  /// collection `users` — nếu gọi [unregister] thì `set(merge)` sẽ tạo lại
  /// doc user rác vừa xoá.
  Future<void> dropToken() async {
    try {
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('PushService.dropToken error: $e');
    }
  }
}
