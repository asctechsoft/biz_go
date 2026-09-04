import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../services/seed_service.dart';
import '../../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: SeedService.demoPhone);
  final _pass = TextEditingController(text: SeedService.demoPassword);
  final _bio = BiometricService();
  bool _obscure = true;
  bool _busy = false;
  bool _bioReady = false; // máy hỗ trợ vân tay + đã lưu tài khoản

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final ok = await _bio.canUse() && await _bio.hasSaved();
    if (mounted) setState(() => _bioReady = ok);
  }

  @override
  void dispose() {
    _phone.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    final phone = _phone.text.trim();
    final pass = _pass.text;
    final ok = await auth.signIn(phone, pass);
    if (ok) {
      // Lưu để đăng nhập vân tay lần sau (đúng tài khoản này).
      await _bio.save(phone, pass);
    } else if (mounted) {
      toast(context, auth.error ?? 'Đăng nhập thất bại');
    }
  }

  Future<void> _bioLogin() async {
    final creds = await _bio.credentials();
    if (creds == null) {
      if (mounted) toast(context, 'Chưa có tài khoản lưu. Đăng nhập mật khẩu trước.');
      return;
    }
    final okBio = await _bio.authenticate();
    if (!okBio) return;
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(creds.$1, creds.$2);
    if (!ok && mounted) {
      toast(context, auth.error ?? 'Đăng nhập thất bại');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loading = auth.status == AuthStatus.loading || _busy;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/images/logo_app.png',
                      width: 96, height: 96, fit: BoxFit.cover),
                ),
                const SizedBox(height: 16),
                const Text('BizGo',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: 32),
                _label('Số điện thoại'),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: phoneInputFormatters,
                  decoration: const InputDecoration(hintText: 'Nhập số điện thoại'),
                ),
                const SizedBox(height: 16),
                _label('Mật khẩu'),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: 'Nhập mật khẩu',
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        toast(context, 'Liên hệ quản trị để đặt lại mật khẩu'),
                    child: const Text('Quên mật khẩu?'),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: loading ? null : _login,
                  child: loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Đăng nhập'),
                ),
                if (_bioReady) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: loading ? null : _bioLogin,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Đăng nhập bằng vân tay'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text('Phiên bản 1.0.0',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
      );
}
