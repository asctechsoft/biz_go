import 'package:flutter/foundation.dart';

import '../core/error_text.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';

enum AuthStatus { unknown, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final PushService _push = PushService();

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  String? error;

  AuthProvider() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final current = _auth.currentUser;
    if (current == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    user = await _auth.loadProfile(current.uid);
    status = user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    if (user != null) _push.registerFor(user!.id);
    notifyListeners();
  }

  Future<bool> signIn(String phone, String password) async {
    status = AuthStatus.loading;
    error = null;
    notifyListeners();
    try {
      user = await _auth.signIn(phone, password);
      status = AuthStatus.authenticated;
      if (user != null) _push.registerFor(user!.id);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('SIGN-IN ERROR: $e'); // raw Firebase code for diagnosis
      error = _friendly(e);
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Nạp lại hồ sơ user hiện tại (sau khi sửa tên...).
  Future<void> refreshProfile() async {
    if (user == null) return;
    final fresh = await _auth.loadProfile(user!.id);
    if (fresh != null) {
      user = fresh;
      notifyListeners();
    }
  }

  /// Có phải đang bị bắt buộc thiết lập lại tài khoản (lần đầu đăng nhập)?
  bool get mustSetupAccount =>
      status == AuthStatus.authenticated &&
      (user?.mustChangeCredentials ?? false);

  /// Đổi SĐT đăng nhập + mật khẩu (màn thiết lập lần đầu). Trả về true nếu OK;
  /// lỗi nằm ở [error].
  Future<bool> changeCredentials({
    required String currentPassword,
    required String newPhone,
    required String newPassword,
    required String name,
  }) async {
    error = null;
    try {
      final oldUid = user?.id;
      final fresh = await _auth.changeCredentials(
        currentPassword: currentPassword,
        newPhone: newPhone,
        newPassword: newPassword,
        name: name,
      );
      user = fresh;
      // Đổi SĐT → uid mới, phải đăng ký lại FCM token cho uid đó.
      if (oldUid != fresh.id) _push.registerFor(fresh.id);
      status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CHANGE-CREDENTIALS ERROR: $e');
      error = _friendlyChange(e);
      notifyListeners();
      return false;
    }
  }

  /// [purgeToken] = false khi vừa xoá sạch collection `users` — tránh ghi
  /// Firestore tạo lại doc user rác.
  Future<void> signOut({bool purgeToken = true}) async {
    if (user != null && purgeToken) {
      await _push.unregister(user!.id);
    } else {
      await _push.dropToken();
    }
    await _auth.signOut();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Ở màn đổi thông tin đăng nhập, "sai thông tin" nghĩa là **mật khẩu hiện
  /// tại** sai — khác nghĩa với lúc đăng nhập.
  String _friendlyChange(Object e) => friendlyError(
        e,
        fallback: 'Thiết lập không thành công. Thử lại giúp tôi.',
        overrides: const {
          'invalid-credential': 'Mật khẩu hiện tại không đúng.',
          'invalid-login-credentials': 'Mật khẩu hiện tại không đúng.',
          'wrong-password': 'Mật khẩu hiện tại không đúng.',
          'email-already-in-use':
              'Số điện thoại này đã có tài khoản khác dùng. Chọn số khác.',
          'requires-recent-login':
              'Phiên đăng nhập đã cũ. Đăng xuất rồi đăng nhập lại để đổi.',
        },
      );

  String _friendly(Object e) => friendlyError(
        e,
        fallback: 'Đăng nhập không thành công. Thử lại giúp tôi.',
        overrides: const {
          'invalid-credential': 'Số điện thoại hoặc mật khẩu không đúng.',
          'invalid-login-credentials':
              'Số điện thoại hoặc mật khẩu không đúng.',
          'wrong-password': 'Số điện thoại hoặc mật khẩu không đúng.',
          'user-not-found': 'Số điện thoại hoặc mật khẩu không đúng.',
        },
      );
}
