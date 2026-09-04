import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/demo_accounts.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../widgets/common.dart';

/// Thiết lập tài khoản lần đầu (bắt buộc).
///
/// Hiện ngay sau khi Chủ đăng nhập bằng tài khoản bootstrap
/// (`0900000000` / `123456`): phải đổi SĐT đăng nhập + mật khẩu trước khi vào
/// app. Router chặn mọi route khác khi [AuthProvider.mustSetupAccount] còn bật.
class SetupAccountScreen extends StatefulWidget {
  const SetupAccountScreen({super.key});
  @override
  State<SetupAccountScreen> createState() => _SetupAccountScreenState();
}

class _SetupAccountScreenState extends State<SetupAccountScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _current = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _bio = BiometricService();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().user;
    _name.text = u?.name ?? '';
    // SĐT bootstrap để trống — buộc nhập số thật, không sửa số demo.
    _current.text = DemoAccounts.password;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _current.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Trả về thông báo lỗi đầu tiên, null nếu hợp lệ.
  String? _validate() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) return 'Nhập tên chủ tài khoản.';
    if (phone.length < 9) return 'Số điện thoại phải có tối thiểu 9 chữ số.';
    if (DemoAccounts.find(phone) != null) {
      return 'Không dùng lại số mặc định của hệ thống. Nhập số điện thoại thật.';
    }
    if (_current.text.isEmpty) return 'Nhập mật khẩu hiện tại.';
    if (_pass.text.length < 6) return 'Mật khẩu mới tối thiểu 6 ký tự.';
    if (_pass.text == DemoAccounts.password) {
      return 'Không dùng lại mật khẩu mặc định.';
    }
    if (_pass.text == _current.text) {
      return 'Mật khẩu mới phải khác mật khẩu hiện tại.';
    }
    if (_confirm.text != _pass.text) return 'Nhập lại mật khẩu không khớp.';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final auth = context.read<AuthProvider>();
    final phone = _phone.text.trim();
    final pass = _pass.text;
    final ok = await auth.changeCredentials(
      currentPassword: _current.text,
      newPhone: phone,
      newPassword: pass,
      name: _name.text.trim(),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = auth.error ?? 'Thiết lập thất bại';
      });
      return;
    }
    // Cập nhật thông tin đăng nhập vân tay theo tài khoản mới.
    await _bio.save(phone, pass);
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, 'Đã thiết lập tài khoản. Ghi nhớ SĐT + mật khẩu mới!');
    // Router tự chuyển về màn chính khi cờ mustChangeCredentials đã tắt.
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Đăng xuất',
      message: 'Chưa thiết lập xong. Lần sau đăng nhập lại vẫn phải thiết lập. '
          'Đăng xuất?',
      confirm: 'Đăng xuất',
    );
    if (!ok || !mounted) return;
    await context.read<AuthProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // bắt buộc hoàn tất, không cho back ra
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Thiết lập tài khoản'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Đăng xuất',
              icon: const Icon(Icons.logout),
              onPressed: _busy ? null : _signOut,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary, width: .5),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.primaryDark),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Đây là lần đăng nhập đầu tiên. Hãy đổi số điện thoại '
                          'đăng nhập và mật khẩu để khoá tài khoản mặc định lại.',
                          style: TextStyle(color: AppColors.primaryDark),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SectionCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header('Tài khoản đăng nhập mới'),
                      _label('Tên chủ tài khoản'),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(hintText: 'VD: Nguyễn Văn A'),
                      ),
                      const SizedBox(height: 14),
                      _label('Số điện thoại đăng nhập mới'),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: phoneInputFormatters,
                        decoration: const InputDecoration(
                            hintText: 'Số điện thoại dùng để đăng nhập'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header('Mật khẩu'),
                      _label('Mật khẩu hiện tại'),
                      TextField(
                        controller: _current,
                        obscureText: _obscure,
                        decoration: const InputDecoration(
                            hintText: 'Mật khẩu đang dùng'),
                      ),
                      const SizedBox(height: 14),
                      _label('Mật khẩu mới'),
                      TextField(
                        controller: _pass,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          hintText: 'Tối thiểu 6 ký tự',
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _label('Nhập lại mật khẩu mới'),
                      TextField(
                        controller: _confirm,
                        obscureText: _obscure,
                        decoration:
                            const InputDecoration(hintText: 'Nhập lại'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger, width: .5),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Lưu & vào app'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sau khi lưu, số điện thoại và mật khẩu mặc định sẽ không '
                  'đăng nhập được nữa.',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
