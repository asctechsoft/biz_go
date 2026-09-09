import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/carrier.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Danh mục **nhà xe** (Cài đặt › Nhà xe) — thêm / sửa / xoá.
///
/// Chỉ là sổ tay tên + SĐT nhà xe hay dùng, để lúc thêm địa chỉ khách khỏi
/// phải gõ lại. Địa chỉ khách và đơn hàng vẫn giữ bản chép riêng, nên sửa/xoá
/// ở đây KHÔNG đổi địa chỉ đã lưu hay phiếu đã in — xem [Carrier].
class CarriersScreen extends StatelessWidget {
  const CarriersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nhà xe')),
      body: StreamBuilder<List<Carrier>>(
        stream: db.carriers(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.directions_bus_outlined,
              text: 'Chưa có nhà xe nào.\nBấm "Thêm" để khai nhà xe hay dùng.',
            );
          }
          return SlidableAutoCloseBehavior(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                88 + MediaQuery.of(context).padding.bottom,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = list[i];
                final tile = ListTile(
                  onTap: () => carrierFormSheet(context, existing: c),
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      Icons.directions_bus_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    c.phone.isEmpty ? 'Chưa có SĐT' : c.phone,
                    style: TextStyle(
                      color: c.phone.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                );
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Slidable(
                    key: ValueKey(c.id),
                    groupTag: 'carriers',
                    endActionPane: ActionPane(
                      motion: const DrawerMotion(),
                      extentRatio: 0.28,
                      children: [
                        SlidableAction(
                          onPressed: (ctx) => _delete(ctx, db, c),
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
        onPressed: () => carrierFormSheet(context),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Thêm', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Xoá nhà xe khỏi danh mục (swipe sang trái).
  ///
  /// [slideCtx] là context của `SlidableAction` — pane đóng lại là widget đó
  /// bị gỡ khỏi cây, nên giữ sẵn `ScaffoldMessenger` trước khi await (cùng lý
  /// do như màn Quản lý người dùng).
  Future<void> _delete(BuildContext slideCtx, Db db, Carrier c) async {
    final messenger = ScaffoldMessenger.of(slideCtx);
    Slidable.of(slideCtx)?.close();
    final ok = await confirmDialog(
      slideCtx,
      title: 'Xóa nhà xe?',
      message:
          'Xóa "${c.name}" khỏi danh mục. Địa chỉ khách và đơn hàng đã lưu '
          'nhà xe này KHÔNG bị ảnh hưởng, chỉ không còn chọn nhanh được nữa.',
      confirm: 'Xóa',
    );
    if (!ok) return;
    await db.deleteCarrier(c.id);
    messenger.showSnackBar(SnackBar(content: Text('Đã xóa nhà xe ${c.name}')));
  }
}

/// Sheet thêm/sửa nhà xe. Trả về [Carrier] đã lưu, `null` nếu bỏ qua.
///
/// Dùng chung cho màn Cài đặt › Nhà xe **và** nút "Thêm nhà xe mới" trong ô
/// chọn nhà xe ở form địa chỉ khách — đang thêm khách mà thiếu nhà xe thì khai
/// luôn tại đó, không phải thoát ra Cài đặt.
Future<Carrier?> carrierFormSheet(
  BuildContext context, {
  Carrier? existing,
  String initialName = '',
}) async {
  final db = context.read<Db>();
  final nameC = TextEditingController(text: existing?.name ?? initialName);
  final phoneC = TextEditingController(text: existing?.phone ?? '');
  String? error;
  bool busy = false;

  return showModalBottomSheet<Carrier>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                existing == null ? 'Thêm nhà xe' : 'Sửa nhà xe',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameC,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setSheet(() => error = null),
                decoration: const InputDecoration(
                  labelText: 'Tên nhà xe',
                  hintText: 'VD: Nhà xe Hoàng Long',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneC,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneInputFormatters,
                onChanged: (_) => setSheet(() => error = null),
                decoration: const InputDecoration(labelText: 'SĐT nhà xe'),
              ),
              // Toast bị sheet che → báo lỗi bằng banner inline.
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final name = nameC.text.trim();
                          if (name.isEmpty) {
                            setSheet(() => error = 'Nhập tên nhà xe');
                            return;
                          }
                          // Trùng tên là nhầm lẫn chứ không phải nhu cầu —
                          // hai dòng y hệt trong ô chọn thì chọn kiểu gì.
                          final all = await db.carriers().first;
                          final dup = all.any(
                            (c) =>
                                c.id != existing?.id &&
                                c.name.toLowerCase() == name.toLowerCase(),
                          );
                          if (dup) {
                            setSheet(() => error = 'Đã có nhà xe tên này');
                            return;
                          }
                          setSheet(() => busy = true);
                          final saved = Carrier(
                            id: existing?.id,
                            name: name,
                            phone: phoneC.text.trim(),
                          );
                          await db.upsertCarrier(saved);
                          if (ctx.mounted) Navigator.pop(ctx, saved);
                        },
                  child: const Text('Lưu'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Kết quả của [pickCarrier]. Phân biệt "bỏ qua" với "chọn không qua nhà xe":
/// `null` từ [pickCarrier] = đóng sheet, còn `CarrierPick(null)` = người dùng
/// chủ động chọn *Không qua nhà xe* → phải xoá 2 ô nhà xe.
class CarrierPick {
  final Carrier? carrier;
  const CarrierPick(this.carrier);
}

/// Ô chọn nhà xe từ danh mục (dùng ở form địa chỉ khách hàng).
Future<CarrierPick?> pickCarrier(BuildContext context, {String? selectedName}) {
  final db = context.read<Db>();
  final searchC = TextEditingController();
  return showModalBottomSheet<CarrierPick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          // Bàn phím mở phải kéo sheet lên theo (padding trên), còn chiều
          // cao tối đa vẫn phải chặn lại kẻo sheet dài hơn cả màn hình.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.9,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => StreamBuilder<List<Carrier>>(
              stream: db.carriers(),
              builder: (ctx, snap) {
                final list = snap.data;
                final query = searchC.text.trim().toLowerCase();
                final filtered = list == null
                    ? null
                    : query.isEmpty
                    ? list
                    : list
                          .where(
                            (c) =>
                                c.name.toLowerCase().contains(query) ||
                                c.phone.toLowerCase().contains(query),
                          )
                          .toList();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          'Chọn nhà xe',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (list != null && list.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: searchC,
                          autofocus: false,
                          onChanged: (_) => setSheet(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Tìm nhà xe theo tên hoặc SĐT',
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        setSheet(() => searchC.clear()),
                                  ),
                          ),
                        ),
                      ),
                    if (list == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            if (query.isEmpty)
                              ListTile(
                                leading: const Icon(Icons.block_outlined),
                                title: const Text(
                                  'Không qua nhà xe (giao thẳng)',
                                ),
                                onTap: () =>
                                    Navigator.pop(ctx, const CarrierPick(null)),
                              ),
                            if (list.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  'Danh mục nhà xe đang trống. Thêm ở đây hoặc vào '
                                  'Cài đặt › Nhà xe.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            else if (filtered!.isEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  'Không tìm thấy nhà xe phù hợp.',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            for (final c in filtered ?? const <Carrier>[])
                              ListTile(
                                leading: Icon(
                                  c.name.toLowerCase() ==
                                          (selectedName ?? '')
                                              .trim()
                                              .toLowerCase()
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: AppColors.primary,
                                ),
                                title: Text(c.name),
                                subtitle: Text(
                                  c.phone.isEmpty ? 'Chưa có SĐT' : c.phone,
                                ),
                                onTap: () => Navigator.pop(ctx, CarrierPick(c)),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.add,
                          color: AppColors.primary,
                        ),
                        title: const Text(
                          'Thêm nhà xe mới',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () async {
                          final created = await carrierFormSheet(
                            ctx,
                            initialName: searchC.text.trim(),
                          );
                          // Thêm xong thì chọn luôn — không ai khai nhà xe mới rồi
                          // lại phải bấm chọn nó lần nữa.
                          if (created != null && ctx.mounted) {
                            Navigator.pop(ctx, CarrierPick(created));
                          }
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
