import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';
import '../models/app_user.dart';
import '../core/demo_accounts.dart';
import '../core/enums.dart';

/// Login is phone + password (spec / mockup 1.1). Firebase Auth uses
/// email/password, so we map a phone to a synthetic email domain.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  static String _emailOf(String phone) =>
      '${phone.replaceAll(RegExp(r'[^0-9]'), '')}@bizgo.local';

  User? get currentUser => _auth.currentUser;
  Stream<User?> authState() => _auth.authStateChanges();

  Future<AppUser?> loadProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  Future<AppUser> signIn(String phone, String password) async {
    final demo = DemoAccounts.find(phone);
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: _emailOf(phone),
        password: password,
      );
      var profile = await loadProfile(cred.user!.uid);

      // Tài khoản demo: luôn ép đúng role/tên (sửa doc seed cũ lưu role lỗi).
      if (demo != null) {
        if (profile == null || profile.role != demo.$3 || profile.name != demo.$2) {
          profile = AppUser(
              id: cred.user!.uid, name: demo.$2, phone: phone, role: demo.$3);
          await _db
              .collection('users')
              .doc(profile.id)
              .set(profile.toMap(), SetOptions(merge: true));
        }
        return profile;
      }

      if (profile != null) return profile;
      // Không có hồ sơ → tạo mặc định quyền thấp nhất.
      final u = AppUser(
          id: cred.user!.uid,
          name: phone,
          phone: phone,
          role: UserRole.shipper);
      await _db.collection('users').doc(u.id).set(u.toMap());
      return u;
    } on FirebaseAuthException catch (e) {
      // Lần đầu đăng nhập tài khoản demo mà chưa tồn tại → tự tạo rồi vào.
      final missing = e.code == 'invalid-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-login-credentials';
      if (demo != null && password == DemoAccounts.password && missing) {
        return register(
            phone: phone, password: password, name: demo.$2, role: demo.$3);
      }
      rethrow;
    }
  }

  /// Create an account (used for seeding / user management).
  Future<AppUser> register({
    required String phone,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: _emailOf(phone),
      password: password,
    );
    final u = AppUser(id: cred.user!.uid, name: name, phone: phone, role: role);
    await _db.collection('users').doc(u.id).set(u.toMap());
    return u;
  }

  /// Tạo tài khoản nếu chưa có; nếu đã có thì đăng nhập và ghi lại đúng role/tên
  /// (sửa các user seed cũ lưu role không còn hợp lệ). Trả về true nếu OK.
  Future<bool> ensureAccount({
    required String phone,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    try {
      await register(phone: phone, password: password, name: name, role: role);
      return true;
    } catch (_) {
      // Đã tồn tại (hoặc lỗi khác) — thử đăng nhập & sửa hồ sơ.
      try {
        final cred = await _auth.signInWithEmailAndPassword(
          email: _emailOf(phone),
          password: password,
        );
        await _db.collection('users').doc(cred.user!.uid).set(
              AppUser(
                      id: cred.user!.uid,
                      name: name,
                      phone: phone,
                      role: role)
                  .toMap(),
              SetOptions(merge: true),
            );
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Chủ tạo tài khoản cho nhân viên/tài xế mà KHÔNG bị đăng xuất.
  /// Dùng một FirebaseApp phụ để tạo user, xong huỷ app phụ.
  Future<AppUser> createUserAsAdmin({
    required String phone,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    FirebaseApp secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'admin_ops',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (_) {
      secondary = Firebase.app('admin_ops');
    }
    try {
      final auth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await auth.createUserWithEmailAndPassword(
        email: _emailOf(phone),
        password: password,
      );
      final u = AppUser(id: cred.user!.uid, name: name, phone: phone, role: role);
      await _db.collection('users').doc(u.id).set(u.toMap());
      await auth.signOut();
      return u;
    } finally {
      await secondary.delete();
    }
  }
}
