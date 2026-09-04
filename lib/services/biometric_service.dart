import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Đăng nhập vân tay: lưu thông tin đăng nhập (an toàn) của tài khoản vừa
/// đăng nhập thành công, lần sau xác thực sinh trắc học để đăng nhập lại
/// đúng tài khoản đó. Thông tin lưu riêng từng thiết bị.
class BiometricService {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kPhone = 'bio_phone';
  static const _kPass = 'bio_pass';
  final _auth = LocalAuthentication();

  /// Máy có hỗ trợ + đã đăng ký vân tay/khuôn mặt chưa.
  Future<bool> canUse() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(String phone, String password) async {
    await _store.write(key: _kPhone, value: phone);
    await _store.write(key: _kPass, value: password);
  }

  Future<bool> hasSaved() async =>
      (await _store.read(key: _kPhone)) != null &&
      (await _store.read(key: _kPass)) != null;

  Future<String?> savedPhone() => _store.read(key: _kPhone);

  Future<(String, String)?> credentials() async {
    final p = await _store.read(key: _kPhone);
    final w = await _store.read(key: _kPass);
    if (p == null || w == null) return null;
    return (p, w);
  }

  Future<void> clear() async {
    await _store.delete(key: _kPhone);
    await _store.delete(key: _kPass);
  }

  /// Hiện hộp xác thực vân tay. true nếu xác thực thành công.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Xác thực để đăng nhập BizGo',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
