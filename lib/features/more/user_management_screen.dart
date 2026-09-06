import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../core/enums.dart';
import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// §3 — Chủ tạo & quản lý tài khoản nhân viên, kể cả **Chủ thứ hai**.
///
/// Nhiều Chủ = nhiều người cùng quản **một** cửa hàng, dùng chung toàn bộ dữ
/// liệu (đơn, khách, công nợ, báo cáo). KHÔNG phải để tách 2 cơ sở — một
/// Firestore là một cửa hàng.
///
/// Ràng buộc duy nhất: luôn phải còn **ít nhất 1 Chủ** đang hoạt động, không
/// thì chẳng ai vào được màn này để dựng lại. `Db` chặn thật, UI chỉ ẩn nút
/// cho đỡ bấm nhầm.
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  static const _creatableRoles = [
    UserRole.owner,
    UserRole.checker,
    UserRole.warehouse,
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
          final ownerCount =
              users.where((u) => u.role == UserRole.owner).length;
          return SlidableAutoCloseBehavior(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = users[i];
                final isOwner = u.role == UserRole.owner;
                // Chủ cuối cùng thì khoá mọi thao tác hạ quyền; có Chủ khác
                // gánh thì xoá/khoá được. Không bao giờ tự xoá chính mình.
                final lastOwner = isOwner && ownerCount <= 1;
                final canDelete = !lastOwner && u.id != meId;
                final lockSwitch = isOwner && (lastOwner || u.id == meId);
                final tile = ListTile(
                  onTap: () => _editUser(context, u, ownerCount: ownerCount),
                  leading: Avatar(u.name, size: 42),
                  title: Text(u.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${u.role.label} · ${u.phone}'),
                  trailing: lockSwitch
                      ? const Chip(
                          label: Text('Chủ',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.primary)),
                          backgroundColor: AppColors.primaryLight,
                          side: BorderSide.none,
                        )
                      : Switch(
                          value: u.active,
                          onChanged: (v) => _setActive(context, db, u, v),
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
  ///
  /// [slideCtx] là context của `SlidableAction`, nằm TRONG action pane — pane
  /// đóng lại là widget đó bị gỡ khỏi cây, `slideCtx.mounted` thành false và
  /// mọi lệnh sau `await` bị bỏ qua. Màn này là `StatelessWidget` nên không có
  /// context của State để thay: giữ sẵn `ScaffoldMessenger` trước khi await.
  Future<void> _deleteUser(BuildContext slideCtx, Db db, AppUser u) async {
    final context = slideCtx;
    final messenger = ScaffoldMessenger.of(context);
    Slidable.of(context)?.close();
    final me = context.read<AuthProvider>().user;
    final ok = await confirmDialog(
      context,
      title: 'Xóa tài khoản',
      message: 'Xóa "${u.name}" (${u.phone})? Người này sẽ không đăng nhập '
          'được nữa. Không thể hoàn tác, và SĐT này KHÔNG tạo lại được.',
      confirm: 'Xóa',
    );
    if (!ok) return;

    void say(String msg) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));

    // Xoá thẳng, danh sách chạy bằng stream nên hàng tự biến mất. Không treo
    // lệnh xoá vào `Slidable.dismiss(ResizeRequest(...))`: callback đó chỉ chạy
    // khi animation ở đúng trạng thái `completed` (dismissal.dart:61).
    try {
      await db.deleteUser(
        u.id,
        actorId: me?.id ?? '',
        actorName: me?.name ?? '',
      );
      say('Đã xóa tài khoản ${u.name}');
    } catch (e) {
      debugPrint('DELETE-USER ERROR: $e');
      say(friendlyError(e,
          fallback: 'Xoá tài khoản không thành công. Thử lại giúp tôi.'));
    }
  }

  /// SĐT trong ô nhập có khác SĐT đang lưu không (bỏ qua ký tự không phải số).
  static bool _phoneChanged(AppUser u, String input) {
    String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');
    final v = digits(input);
    return v.isNotEmpty && v != digits(u.phone);
  }

  /// Bật/tắt tài khoản. `Db` từ chối khi khoá Chủ đang hoạt động cuối cùng.
  Future<void> _setActive(
      BuildContext context, Db db, AppUser u, bool active) async {
    try {
      await db.setUserActive(u.id, active);
    } catch (e) {
      debugPrint('SET-USER-ACTIVE ERROR: $e');
      if (context.mounted) {
        toast(context,
            friendlyError(e, fallback: 'Không đổi được trạng thái tài khoản.'));
      }
    }
  }

  /// Sửa hồ sơ user: tên (mọi vai trò) + vai trò. SĐT giữ nguyên.
  /// Chủ **cuối cùng** không cho đổi vai trò — hạ cấp là mất quyền quản trị.
  Future<void> _editUser(BuildContext context, AppUser u,
      {required int ownerCount}) async {
    final db = context.read<Db>();
    final auth = context.read<AuthProvider>();
    final nameC = TextEditingController(text: u.name);
    final phoneC = TextEditingController(text: u.phone);
    final passC = TextEditingController();
    UserRole role = u.role;
    final lockRole = u.role == UserRole.owner && ownerCount <= 1;
    // Đổi SĐT của CHÍNH MÌNH ở đây là tự khoá mình ra ngoài: hồ sơ chuyển sang
    // uid mới, phiên đang chạy trỏ vào uid cũ đã bị xoá.
    final isSelf = u.id == auth.user?.id;
    String? error;
    bool busy = false;

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
                  controller: phoneC,
                  enabled: !isSelf,
                  keyboardType: TextInputType.phone,
                  inputFormatters: phoneInputFormatters,
                  onChanged: (_) => setSheet(() => error = null),
                  decoration: InputDecoration(
                    labelText: isSelf
                        ? 'Số điện thoại (không tự đổi số của mình)'
                        : 'Số điện thoại (dùng để đăng nhập)',
                  ),
                ),
                // Đổi SĐT = tạo tài khoản đăng nhập mới, nên bắt buộc đặt mật
                // khẩu mới — Chủ không biết mật khẩu cũ của nhân viên.
                if (!isSelf && _phoneChanged(u, phoneC.text)) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: passC,
                    onChanged: (_) => setSheet(() => error = null),
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới (tối thiểu 6 ký tự)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Đổi số là tạo lại tài khoản đăng nhập: người này phải '
                      'đăng nhập bằng SĐT mới + mật khẩu vừa đặt. Số cũ '
                      '${u.phone} sẽ KHÔNG dùng lại được nữa.',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ],
                if (lockRole) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Đây là tài khoản Chủ duy nhất nên không đổi được vai trò. '
                    'Tạo thêm một Chủ nữa rồi hãy đổi.',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ] else ...[
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
                  onPressed: busy
                      ? null
                      : () async {
                          final name = nameC.text.trim();
                          if (name.isEmpty) {
                            setSheet(() => error = 'Vui lòng nhập họ tên');
                            return;
                          }
                          final changedPhone =
                              !isSelf && _phoneChanged(u, phoneC.text);
                          if (changedPhone) {
                            if (phoneC.text.trim().length < 8) {
                              setSheet(() =>
                                  error = 'Số điện thoại không hợp lệ');
                              return;
                            }
                            if (passC.text.length < 6) {
                              setSheet(() =>
                                  error = 'Mật khẩu tối thiểu 6 ký tự');
                              return;
                            }
                            final ok = await confirmDialog(
                              ctx,
                              title: 'Đổi số điện thoại?',
                              message:
                                  '${u.phone} → ${phoneC.text.trim()}\n\n'
                                  'Tài khoản đăng nhập sẽ được tạo lại. Người '
                                  'này phải dùng SĐT mới + mật khẩu vừa đặt. '
                                  'Số cũ KHÔNG dùng lại được.',
                              confirm: 'Đổi số',
                            );
                            if (!ok) return;
                          }

                          setSheet(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            if (changedPhone) {
                              await AuthService().changePhoneAsAdmin(
                                target: u,
                                newPhone: phoneC.text.trim(),
                                newPassword: passC.text,
                                name: name,
                                role: lockRole ? u.role : role,
                              );
                            } else {
                              await db.updateUser(
                                u.id,
                                name: name,
                                role: lockRole ? null : role,
                              );
                            }
                          } catch (e) {
                            debugPrint('UPDATE-USER ERROR: $e');
                            setSheet(() {
                              busy = false;
                              error = friendlyError(e,
                                  fallback:
                                      'Không cập nhật được người dùng.');
                            });
                            return;
                          }
                          if (u.id == auth.user?.id) {
                            await auth.refreshProfile();
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            toast(
                                context,
                                changedPhone
                                    ? 'Đã đổi số đăng nhập thành '
                                        '${phoneC.text.trim()}'
                                    : 'Đã cập nhật người dùng');
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Lưu'),
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
    UserRole role = UserRole.checker;
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
                // Chủ là quyền cao nhất — nói rõ trước khi bấm, vì SĐT đã tạo
                // thì KHÔNG xoá lại được (Firebase Auth cần Admin SDK).
                if (role == UserRole.owner) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Chủ có TOÀN QUYỀN: xem doanh thu, công nợ, thu tiền, '
                      'sửa giá và quản lý cả tài khoản khác. Chỉ tạo cho '
                      'người đồng sở hữu cửa hàng này.',
                      style: TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ],
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
                            debugPrint('CREATE-USER ERROR: $e');
                            final msg = friendlyError(e,
                                fallback:
                                    'Tạo tài khoản không thành công. Thử lại giúp tôi.',
                                overrides: const {
                                  'email-already-in-use':
                                      'Số điện thoại này đã có tài khoản',
                                });
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
