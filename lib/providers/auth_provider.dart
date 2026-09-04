import 'package:flutter/foundation.dart';

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

  String _friendlyChange(Object e) {
    final s = e.toString();
    if (s.contains('email-already-in-use')) {
      return 'Số điện thoại này đã có tài khoản khác dùng. Chọn số khác.';
    }
    if (s.contains('weak-password')) {
      return 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
    }
    if (s.contains('invalid-credential') ||
        s.contains('wrong-password') ||
        s.contains('invalid-login-credentials')) {
      return 'Mật khẩu hiện tại không đúng.';
    }
    if (s.contains('requires-recent-login')) {
      return 'Phiên đăng nhập đã cũ. Đăng xuất rồi đăng nhập lại để đổi.';
    }
    if (s.contains('network')) return 'Lỗi kết nối mạng.';
    final code = RegExp(r'\[([^\]]+)\]').firstMatch(s)?.group(1);
    return 'Thiết lập thất bại${code == null ? '' : ': $code'}';
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('account-removed')) {
      return 'Tài khoản này đã bị xoá. Liên hệ Chủ để được cấp lại.';
    }
    if (s.contains('account-disabled')) {
      return 'Tài khoản đang bị tạm ngưng. Liên hệ Chủ để mở lại.';
    }
    if (s.contains('owner-already-exists')) {
      return 'Tài khoản demo đã bị vô hiệu hoá vì hệ thống đã có Chủ.\n'
          'Đăng nhập bằng số điện thoại Chủ đã thiết lập.';
    }
    if (s.contains('invalid-credential') ||
        s.contains('wrong-password') ||
        s.contains('user-not-found') ||
        s.contains('invalid-login-credentials')) {
      return 'Số điện thoại hoặc mật khẩu không đúng.\nLần đầu bấm "Tạo dữ liệu mẫu & đăng nhập demo".';
    }
    if (s.contains('operation-not-allowed')) {
      return 'Firebase chưa bật đăng nhập Email/Password. Vào Console → Authentication → Sign-in method để bật.';
    }
    if (s.contains('too-many-requests')) {
      return 'Thử quá nhiều lần. Đợi chút rồi thử lại.';
    }
    if (s.contains('network')) return 'Lỗi kết nối mạng.';
    // Surface the raw Firebase code so lỗi lạ vẫn chẩn đoán được.
    final code = RegExp(r'\[([^\]]+)\]').firstMatch(s)?.group(1) ??
        RegExp(r'\(([^)]+)\)').firstMatch(s)?.group(1);
    return 'Đăng nhập thất bại${code == null ? '' : ': $code'}';
  }
}
