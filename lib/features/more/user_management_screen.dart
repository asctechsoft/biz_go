import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// §3 — Chủ tạo & quản lý tài khoản nhân viên (Kiểm hàng) và tài xế (Giao hàng).
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  // Chủ chỉ tạo được 2 vai trò này; tài khoản Chủ giữ duy nhất.
  static const _creatableRoles = [
    UserRole.checker,
    UserRole.warehouse,
    UserRole.shipper,
  ];

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý người dùng')),
      body: StreamBuilder<List<AppUser>>(
        stream: db.users(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!;
          final meId = context.read<AuthProvider>().user?.id;
          return SlidableAutoCloseBehavior(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = users[i];
                // Không cho xoá Chủ (chỉ có 1, xoá là mất quyền quản trị) và
                // không cho tự xoá chính mình.
                final canDelete = u.role != UserRole.owner && u.id != meId;
                final tile = ListTile(
                  onTap: () => _editUser(context, u),
                  leading: Avatar(u.name, size: 42),
                  title: Text(u.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${u.role.label} · ${u.phone}'),
                  trailing: u.role == UserRole.owner
                      ? const Chip(
                          label: Text('Chủ',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.primary)),
                          backgroundColor: AppColors.primaryLight,
                          side: BorderSide.none,
                        )
                      : Switch(
                          value: u.active,
                          onChanged: (v) => db.setUserActive(u.id, v),
                        ),
                );
                if (!canDelete) return Card(child: tile);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Slidable(
                    key: ValueKey(u.id),
                    groupTag: 'users',
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.28, // hé lộ ~1/4, không dismiss hết
                      children: [
                        SlidableAction(
                          onPressed: (ctx) => _deleteUser(ctx, db, u),
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          icon: Icons.delete,
                          label: 'Xóa',
                        ),
                      ],
                    ),
                    child: Material(
                      color: AppColors.card,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(12),
                          ),
                        ),
                        child: tile,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _createUser(context),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Thêm', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Xoá tài khoản (swipe sang trái). Chỉ xoá hồ sơ Firestore — tài khoản
  /// Firebase Auth cần Admin SDK mới xoá được, nên SĐT đó không tạo lại được.
  Future<void> _deleteUser(BuildContext context, Db db, AppUser u) async {
    final me = context.read<AuthProvider>().user;
    final ok = await confirmDialog(
      context,
      title: 'Xóa tài khoản',
      message: 'Xóa "${u.name}" (${u.phone})? Người này sẽ không đăng nhập '
          'được nữa. Không thể hoàn tác, và SĐT này KHÔNG tạo lại được.',
      confirm: 'Xóa',
    );
    if (!ok) return;
    if (context.mounted) toast(context, 'Đã xóa tài khoản ${u.name}');
    // Co hàng lại (đẩy các dòng dưới lên) rồi mới xóa dữ liệu.
    final slidable = context.mounted ? Slidable.of(context) : null;
    void remove() => db.deleteUser(
          u.id,
          actorId: me?.id ?? '',
          actorName: me?.name ?? '',
        );
    if (slidable != null) {
      slidable.dismiss(
        ResizeRequest(const Duration(milliseconds: 300), remove),
      );
    } else {
      remove();
    }
  }

  /// Sửa hồ sơ user: tên (mọi vai trò) + vai trò (trừ Chủ). SĐT giữ nguyên.
  Future<void> _editUser(BuildContext context, AppUser u) async {
    final db = context.read<Db>();
    final auth = context.read<AuthProvider>();
    final nameC = TextEditingController(text: u.name);
    UserRole role = u.role;
    final isOwner = u.role == UserRole.owner;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sửa người dùng',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: false,
                  controller: TextEditingController(text: u.phone),
                  decoration: const InputDecoration(
                      labelText: 'Số điện thoại (không đổi được)'),
                ),
                if (!isOwner) ...[
                  const SizedBox(height: 12),
                  const Text('Vai trò',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in _creatableRoles)
                        ChoiceChip(
                          label: Text(r.label),
                          selected: role == r,
                          onSelected: (_) => setSheet(() => role = r),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (nameC.text.trim().isEmpty) {
                      toast(ctx, 'Vui lòng nhập họ tên');
                      return;
                    }
                    await db.updateUser(
                      u.id,
                      name: nameC.text.trim(),
                      role: isOwner ? null : role,
                    );
                    if (u.id == auth.user?.id) await auth.refreshProfile();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      toast(context, 'Đã cập nhật người dùng');
                    }
                  },
                  child: const Text('Lưu'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createUser(BuildContext context) async {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final passC = TextEditingController(text: '123456');
    UserRole role = UserRole.shipper;
    String? error;
    bool busy = false;
    final auth = AuthService();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Thêm người dùng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                if (error != null) ...[
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(error!,
                              style: const TextStyle(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w600))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameC,
                  onChanged: (_) {
                    if (error != null) setSheet(() => error = null);
                  },
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  inputFormatters: phoneInputFormatters,
                  onChanged: (_) {
                    if (error != null) setSheet(() => error = null);
                  },
                  decoration: const InputDecoration(
                      labelText: 'Số điện thoại (dùng để đăng nhập)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passC,
                  decoration: const InputDecoration(
                      labelText: 'Mật khẩu (tối thiểu 6 ký tự)'),
                ),
                const SizedBox(height: 12),
                const Text('Vai trò',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in _creatableRoles)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: role == r,
                        onSelected: (_) => setSheet(() => role = r),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final phone = phoneC.text.trim();
                          if (nameC.text.trim().isEmpty) {
                            setSheet(() => error = 'Vui lòng nhập họ tên');
                            return;
                          }
                          if (phone.length < 8) {
                            setSheet(() =>
                                error = 'Số điện thoại không hợp lệ');
                            return;
                          }
                          if (passC.text.length < 6) {
                            setSheet(() =>
                                error = 'Mật khẩu tối thiểu 6 ký tự');
                            return;
                          }
                          setSheet(() => busy = true);
                          try {
                            await auth.createUserAsAdmin(
                              phone: phone,
                              password: passC.text,
                              name: nameC.text.trim(),
                              role: role,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              toast(context,
                                  'Đã tạo tài khoản ${nameC.text.trim()}');
                            }
                          } catch (e) {
                            final msg = e.toString().contains('email-already-in-use')
                                ? 'Số điện thoại này đã có tài khoản'
                                : 'Lỗi tạo tài khoản: $e';
                            setSheet(() {
                              busy = false;
                              error = msg;
                            });
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Tạo tài khoản'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
