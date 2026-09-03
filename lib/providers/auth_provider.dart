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

  Future<void> signOut() async {
    if (user != null) await _push.unregister(user!.id);
    await _auth.signOut();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  String _friendly(Object e) {
    final s = e.toString();
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
