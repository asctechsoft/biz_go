/// Đổi lỗi kỹ thuật thành câu tiếng Việt người dùng đọc hiểu.
///
/// Nguyên tắc: **KHÔNG BAO GIỜ đưa mã lỗi thô ra màn hình** (kiểu
/// `firebase_auth/invalid-email` hay `Exception: ...`) — user không hiểu và
/// cũng không làm gì được với nó. Mã thô chỉ đi vào console qua `debugPrint`
/// ở nơi bắt lỗi, để dev chẩn đoán.
library;

/// Mã lỗi → câu tiếng Việt. Gộp cả Firebase Auth, Firestore và mã tự đặt của
/// app (`account-removed`... ném từ `AuthService`).
const Map<String, String> _messages = {
  // --- Firebase Auth ---
  'invalid-email': 'Số điện thoại không hợp lệ. Nhập lại giúp tôi.',
  'invalid-credential': 'Số điện thoại hoặc mật khẩu không đúng.',
  'invalid-login-credentials': 'Số điện thoại hoặc mật khẩu không đúng.',
  'wrong-password': 'Số điện thoại hoặc mật khẩu không đúng.',
  'user-not-found': 'Số điện thoại hoặc mật khẩu không đúng.',
  'user-disabled': 'Tài khoản đang bị tạm ngưng. Liên hệ Chủ để mở lại.',
  'email-already-in-use': 'Số điện thoại này đã có tài khoản khác dùng.',
  'weak-password': 'Mật khẩu quá yếu — cần ít nhất 6 ký tự.',
  'too-many-requests': 'Bạn thử quá nhiều lần. Đợi vài phút rồi thử lại.',
  'requires-recent-login':
      'Phiên đăng nhập đã cũ. Đăng xuất rồi đăng nhập lại để thực hiện.',
  'network-request-failed':
      'Không có kết nối mạng. Kiểm tra Wi-Fi hoặc 4G rồi thử lại.',
  'channel-error': 'Vui lòng nhập đầy đủ thông tin.',
  // Firebase chưa bật Email/Password — user không tự sửa được, chỉ báo để họ
  // gọi đúng người. Mã thô vẫn nằm ở console cho dev.
  'operation-not-allowed':
      'Hệ thống chưa được cấu hình đăng nhập. Liên hệ quản trị viên.',

  // --- Mã tự đặt của app ---
  'account-removed': 'Tài khoản này đã bị xoá. Liên hệ Chủ để được cấp lại.',
  'account-disabled': 'Tài khoản đang bị tạm ngưng. Liên hệ Chủ để mở lại.',
  'owner-already-exists':
      'Tài khoản demo đã bị vô hiệu hoá vì hệ thống đã có Chủ.\n'
          'Đăng nhập bằng số điện thoại Chủ đã thiết lập.',

  // --- Firestore ---
  'permission-denied': 'Bạn không có quyền thực hiện thao tác này.',
  'unauthenticated': 'Phiên đăng nhập đã hết hạn. Đăng nhập lại giúp tôi.',
  'unavailable': 'Mất kết nối máy chủ. Kiểm tra mạng rồi thử lại.',
  'deadline-exceeded': 'Máy chủ phản hồi chậm. Thử lại giúp tôi.',
  'not-found': 'Không tìm thấy dữ liệu. Có thể đã bị xoá.',
  'already-exists': 'Dữ liệu này đã tồn tại.',
  'aborted': 'Thao tác bị gián đoạn. Thử lại giúp tôi.',
  'cancelled': 'Thao tác đã bị huỷ.',
  'resource-exhausted': 'Hệ thống đang quá tải. Thử lại sau ít phút.',
};

/// Mã trong ngoặc vuông kiểu `[firebase_auth/invalid-email]` hoặc
/// `[cloud_firestore/permission-denied]`.
final _bracketCode = RegExp(r'\[[\w_]+/([\w-]+)\]');

/// Dạng rút gọn `firebase_auth/invalid-email` khi không có ngoặc.
final _slashCode = RegExp(r'\b[\w_]+/([\w-]+)\b');

/// Tiền tố kỹ thuật cần cắt khỏi message nghiệp vụ.
final _prefix = RegExp(r'^(Exception|_Exception|StateError|ArgumentError):\s*');

/// Dấu tiếng Việt — dùng để nhận ra message nghiệp vụ do `Db` ném ra (đã là
/// câu tiếng Việt sẵn sàng hiển thị) so với lỗi Dart/Anh ngữ lọt ra.
final _vietnamese = RegExp(
    r'[ăâđêôơưàáạảãằắặẳẵầấậẩẫèéẹẻẽềếệểễìíịỉĩòóọỏõồốộổỗờớợởỡùúụủũừứựửữỳýỵỷỹ]',
    caseSensitive: false);

/// Câu thông báo cho [e].
///
/// - Có mã lỗi đã biết → trả câu tiếng Việt tương ứng.
/// - Là lỗi nghiệp vụ `Db` ném ra (message tiếng Việt) → trả nguyên message,
///   bỏ tiền tố `Exception:`.
/// - Còn lại → [fallback]. Không lộ mã thô.
///
/// [overrides] để đổi lời cho từng ngữ cảnh — ví dụ ở màn đổi mật khẩu thì
/// `invalid-credential` nghĩa là "mật khẩu hiện tại sai", không phải "sai
/// tài khoản".
String friendlyError(
  Object e, {
  String fallback = 'Có lỗi xảy ra. Thử lại giúp tôi.',
  Map<String, String>? overrides,
}) {
  final raw = e.toString();

  final code = _bracketCode.firstMatch(raw)?.group(1) ??
      _slashCode.firstMatch(raw)?.group(1);
  if (code != null) {
    return overrides?[code] ?? _messages[code] ?? fallback;
  }

  final msg = raw.replaceFirst(_prefix, '').trim();
  if (msg.isNotEmpty && _vietnamese.hasMatch(msg)) return msg;

  return fallback;
}
