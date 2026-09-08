import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../core/firebase_env.dart';
import '../models/app_user.dart';
import '../core/demo_accounts.dart';
import '../core/enums.dart';

/// Login is phone + password (spec / mockup 1.1). Firebase Auth uses
/// email/password, so we map a phone to a synthetic email domain.
class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  static String _emailOf(String phone) => '${normalizePhone(phone)}@bizgo.local';

  static String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  User? get currentUser => _auth.currentUser;
  Stream<User?> authState() => _auth.authStateChanges();

  Future<AppUser?> loadProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.id, doc.data()!);
  }

  /// Đã có tài khoản Chủ nào KHÁC [selfUid] chưa? Dùng để chặn cửa hậu: sau
  /// khi Chủ đổi sang SĐT riêng, số demo 0900000000/123456 không được cấp lại
  /// quyền Chủ nữa.
  Future<bool> _otherOwnerExists(String selfUid) async {
    final snap = await _db
        .collection('users')
        .where('role', isEqualTo: UserRole.owner.name)
        .get();
    return snap.docs.any((d) => d.id != selfUid);
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
        final needsFix =
            profile == null || profile.role != demo.$3 || profile.name != demo.$2;
        if (needsFix) {
          try {
            await _guardOwnerBootstrap(demo.$3, cred.user!.uid);
          } catch (_) {
            await _auth.signOut();
            rethrow;
          }
          final fresh = profile == null; // hồ sơ mới → buộc thiết lập lại
          profile = AppUser(
            id: cred.user!.uid,
            name: demo.$2,
            phone: phone,
            role: demo.$3,
            mustChangeCredentials: fresh,
          );
          await _db.collection('users').doc(profile.id).set({
            ...profile.toMap(),
            if (fresh) 'mustChangeCredentials': true,
          }, SetOptions(merge: true));
        }
        return profile;
      }

      // Không có hồ sơ → tài khoản đã bị Chủ xoá (hoặc tạo ngoài app). KHÔNG
      // tự tạo hồ sơ mặc định: làm vậy thì nút Xoá ở Quản lý người dùng vô
      // nghĩa — người bị xoá đăng nhập lại là hồ sơ mọc lại ngay.
      if (profile == null) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'account-removed',
          message: 'Tài khoản không còn hiệu lực.',
        );
      }
      // Chủ tắt công tắc ở Quản lý người dùng → chặn đăng nhập luôn.
      if (!profile.active) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'account-disabled',
          message: 'Tài khoản đang bị tạm ngưng.',
        );
      }
      return profile;
    } on FirebaseAuthException catch (e) {
      // Lần đầu đăng nhập tài khoản demo mà chưa tồn tại → tự tạo rồi vào.
      final missing = e.code == 'invalid-credential' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-login-credentials';
      if (demo != null && password == DemoAccounts.password && missing) {
        final u = await register(
            phone: phone,
            password: password,
            name: demo.$2,
            role: demo.$3,
            mustChangeCredentials: true);
        try {
          await _guardOwnerBootstrap(demo.$3, u.id);
        } catch (_) {
          // Bootstrap không hợp lệ → dọn hồ sơ + tài khoản Auth vừa tạo.
          await _db.collection('users').doc(u.id).delete();
          try {
            await _auth.currentUser?.delete();
          } catch (e) {
            debugPrint('signIn: xoá account bootstrap lỗi: $e');
            await _auth.signOut();
          }
          rethrow;
        }
        return u;
      }
      rethrow;
    }
  }

  /// Chỉ cho phép "mọc" tài khoản Chủ từ số demo khi hệ thống chưa có Chủ nào.
  /// Hệ thống VẪN cho nhiều Chủ — nhưng Chủ thứ hai phải do Chủ hiện tại tạo
  /// qua Quản lý người dùng, không phải ai biết số demo cũng tự dựng được.
  /// KHÔNG tự `signOut` — caller dọn dẹp (xoá account vừa tạo) rồi mới thoát,
  /// vì `currentUser` phải còn để xoá được.
  Future<void> _guardOwnerBootstrap(UserRole role, String uid) async {
    if (role != UserRole.owner) return;
    if (!await _otherOwnerExists(uid)) return;
    throw FirebaseAuthException(
      code: 'owner-already-exists',
      message: 'Hệ thống đã có tài khoản Chủ.',
    );
  }

  /// Create an account (used for seeding / user management).
  Future<AppUser> register({
    required String phone,
    required String password,
    required String name,
    required UserRole role,
    bool mustChangeCredentials = false,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: _emailOf(phone),
      password: password,
    );
    final u = AppUser(
        id: cred.user!.uid,
        name: name,
        phone: phone,
        role: role,
        mustChangeCredentials: mustChangeCredentials);
    await _db.collection('users').doc(u.id).set({
      ...u.toMap(),
      if (mustChangeCredentials) 'mustChangeCredentials': true,
    });
    return u;
  }

  /// Tạo tài khoản nếu chưa có; nếu đã có thì đăng nhập và ghi lại đúng role/tên
  /// (sửa các user seed cũ lưu role không còn hợp lệ). Trả về true nếu OK.
  Future<bool> ensureAccount({
    required String phone,
    required String password,
    required String name,
    required UserRole role,
    bool mustChangeCredentials = false,
  }) async {
    try {
      await register(
          phone: phone,
          password: password,
          name: name,
          role: role,
          mustChangeCredentials: mustChangeCredentials);
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

  /// Đổi SĐT đăng nhập + mật khẩu của tài khoản đang đăng nhập (màn thiết lập
  /// lần đầu). Xoá cờ [AppUser.mustChangeCredentials] khi xong.
  ///
  /// Email đăng nhập là `<sđt>@bizgo.local` — domain giả, không nhận được mail
  /// xác thực nên `verifyBeforeUpdateEmail` vô dụng. Vì vậy khi ĐỔI SĐT ta tạo
  /// tài khoản Auth mới, chuyển hồ sơ sang uid mới rồi xoá tài khoản cũ. Chỉ
  /// đổi mật khẩu thì giữ nguyên uid.
  Future<AppUser> changeCredentials({
    required String currentPassword,
    required String newPhone,
    required String newPassword,
    required String name,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
          code: 'no-current-user', message: 'Chưa đăng nhập.');
    }
    final oldUid = user.uid;
    final oldEmail = user.email!;
    final phone = normalizePhone(newPhone);

    // Bắt buộc xác thực lại trước khi đổi mật khẩu / xoá tài khoản.
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: oldEmail, password: currentPassword),
    );

    final old = await loadProfile(oldUid);
    final role = old?.role ?? UserRole.owner;
    final active = old?.active ?? true;

    // Giữ nguyên SĐT → chỉ đổi mật khẩu, uid không đổi.
    if (_emailOf(phone) == oldEmail) {
      await user.updatePassword(newPassword);
      final u = AppUser(
          id: oldUid, name: name, phone: phone, role: role, active: active);
      await _db.collection('users').doc(oldUid).set({
        ...u.toMap(),
        'mustChangeCredentials': false,
      }, SetOptions(merge: true));
      return u;
    }

    // Đổi SĐT → tạo tài khoản mới trên FirebaseApp phụ (không làm đăng xuất
    // app chính) TRƯỚC, để nếu SĐT mới đã bị dùng thì chưa phá gì cả.
    FirebaseApp secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'admin_ops',
        options: firebaseOptions,
      );
    } catch (_) {
      secondary = Firebase.app('admin_ops');
    }
    final String newUid;
    try {
      final auth2 = FirebaseAuth.instanceFor(app: secondary);
      final cred = await auth2.createUserWithEmailAndPassword(
        email: _emailOf(phone),
        password: newPassword,
      );
      newUid = cred.user!.uid;
      await auth2.signOut();
    } finally {
      await secondary.delete();
    }

    final u = AppUser(
        id: newUid, name: name, phone: phone, role: role, active: active);
    await _db.collection('users').doc(newUid).set({
      ...u.toMap(),
      'mustChangeCredentials': false,
    });
    // Từ đây tài khoản mới đã dùng được. Lỗi dọn dẹp chỉ log, KHÔNG throw —
    // nếu throw thì SĐT mới đã bị chiếm mà app vẫn kẹt ở màn thiết lập, thử
    // lại sẽ báo email-already-in-use.
    try {
      await _db.collection('users').doc(oldUid).delete();
    } catch (e) {
      debugPrint('changeCredentials: xoá hồ sơ cũ lỗi: $e');
    }
    try {
      // Xoá tài khoản Auth cũ — còn thì SĐT cũ vẫn đăng nhập được.
      await _auth.currentUser?.delete();
    } catch (e) {
      debugPrint('changeCredentials: xoá tài khoản Auth cũ lỗi: $e');
      await _auth.signOut();
    }
    // Đăng nhập lại bằng tài khoản mới trên app chính.
    await _auth.signInWithEmailAndPassword(
        email: _emailOf(phone), password: newPassword);
    return u;
  }

  /// Chủ đổi **SĐT đăng nhập** của một tài khoản khác.
  ///
  /// SĐT chính là danh tính đăng nhập (`<sđt>@bizgo.local`) nên không "sửa"
  /// tại chỗ được: phải tạo tài khoản Auth MỚI rồi chuyển hồ sơ sang uid mới.
  /// Chủ không biết mật khẩu của nhân viên nên buộc phải đặt mật khẩu mới.
  ///
  /// Tạo tài khoản mới TRƯỚC, xoá hồ sơ cũ SAU: SĐT mới trùng thì ném lỗi lúc
  /// chưa phá gì cả, người dùng vẫn đăng nhập được bằng số cũ.
  ///
  /// Hệ quả không tránh được: tài khoản Auth cũ chỉ xoá được bằng Admin SDK
  /// nên **SĐT cũ bị chiếm vĩnh viễn**, không tạo lại được. Người đó cũng
  /// không đăng nhập bằng số cũ được nữa vì hồ sơ đã xoá (`signIn` từ chối
  /// account không có hồ sơ).
  Future<AppUser> changePhoneAsAdmin({
    required AppUser target,
    required String newPhone,
    required String newPassword,
    required String name,
    required UserRole role,
  }) async {
    final phone = normalizePhone(newPhone);
    if (phone == normalizePhone(target.phone)) {
      throw FirebaseAuthException(
        code: 'same-phone',
        message: 'Số điện thoại không thay đổi.',
      );
    }

    FirebaseApp secondary;
    try {
      secondary = await Firebase.initializeApp(
        name: 'admin_ops',
        options: firebaseOptions,
      );
    } catch (_) {
      secondary = Firebase.app('admin_ops');
    }
    final String newUid;
    try {
      final auth2 = FirebaseAuth.instanceFor(app: secondary);
      final cred = await auth2.createUserWithEmailAndPassword(
        email: _emailOf(phone),
        password: newPassword,
      );
      newUid = cred.user!.uid;
      await auth2.signOut();
    } finally {
      await secondary.delete();
    }

    final u = AppUser(
      id: newUid,
      name: name,
      phone: phone,
      role: role,
      active: target.active,
    );
    await _db.collection('users').doc(newUid).set(u.toMap());
    // Hồ sơ mới đã dùng được rồi — lỗi dọn dẹp chỉ log, KHÔNG throw, kẻo báo
    // thất bại trong khi tài khoản mới đã tạo xong và SĐT mới đã bị chiếm.
    try {
      await _db.collection('users').doc(target.id).delete();
    } catch (e) {
      debugPrint('changePhoneAsAdmin: xoá hồ sơ cũ lỗi: $e');
    }
    return u;
  }

  /// Chủ tạo tài khoản cho nhân viên (Kiểm hàng/Kiểm kho) mà KHÔNG bị đăng xuất.
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
        options: firebaseOptions,
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
