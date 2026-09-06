import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/db.dart';
import '../../services/image_service.dart';
import '../../widgets/common.dart';

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      body: StreamBuilder<Product>(
        stream: db.product(productId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final p = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(p.name),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Sửa sản phẩm',
                    onPressed: () => _editProduct(context, db, p),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: SlidableAutoCloseBehavior(
                  child: Padding(
                    // Chừa chỗ cho thanh điều hướng Android. `Scaffold` chỉ tự
                    // trừ inset đáy khi có `bottomNavigationBar` — màn này
                    // không có, nên nút cuối trang bị thanh nav che và cuộn
                    // hết cỡ vẫn không bấm được.
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      16 + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: ImagePickerBox(
                            path: p.imagePath,
                            size: 160,
                            onTap: () async {
                              final path = await pickImage(
                                context,
                                context.read<ImageService>(),
                              );
                              if (path != null) {
                                await db.upsertProduct(
                                  _copyVariants(
                                    Product(
                                      id: p.id,
                                      name: p.name,
                                      description: p.description,
                                      imagePath: path,
                                    ),
                                    p.variants,
                                  ),
                                );
                                if (context.mounted) {
                                  toast(context, 'Đã cập nhật ảnh');
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (p.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            p.description,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const Divider(height: 28),
                        const Text(
                          'Phân loại',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final v in p.variants)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Slidable(
                                key: ValueKey(v.id),
                                groupTag: 'variants',
                                endActionPane: ActionPane(
                                  motion: const DrawerMotion(),
                                  extentRatio: 0.5,
                                  children: [
                                    SlidableAction(
                                      onPressed: (_) =>
                                          _editVariant(context, db, p, v),
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      icon: Icons.edit,
                                      label: 'Sửa',
                                    ),
                                    SlidableAction(
                                      onPressed: (_) =>
                                          _deleteVariant(context, db, p, v),
                                      backgroundColor: AppColors.danger,
                                      foregroundColor: Colors.white,
                                      icon: Icons.delete,
                                      label: 'Xóa',
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.white,
                                  child: ListTile(
                                    title: Text(
                                      v.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${v.packagings.length} quy cách',
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _PackagingScreen(
                                          product: p,
                                          variantId: v.id,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _addVariant(context, db, p),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm phân loại'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addVariant(BuildContext context, Db db, Product p) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Thêm phân loại'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên phân loại'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      final variants = [...p.variants, ProductVariant(name: c.text.trim())];
      await db.upsertProduct(_copyVariants(p, variants));
      if (context.mounted) toast(context, 'Đã thêm phân loại');
    }
  }

  /// Sửa tên phân loại (giữ nguyên các quy cách).
  Future<void> _editVariant(
    BuildContext context,
    Db db,
    Product p,
    ProductVariant v,
  ) async {
    final c = TextEditingController(text: v.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Sửa phân loại'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên phân loại'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty && c.text.trim() != v.name) {
      final newV = ProductVariant(
        id: v.id,
        name: c.text.trim(),
        packagings: v.packagings,
      );
      final variants = p.variants.map((e) => e.id == v.id ? newV : e).toList();
      await db.upsertProduct(_copyVariants(p, variants));
      if (context.mounted) toast(context, 'Đã cập nhật phân loại');
    }
  }

  /// Xóa phân loại (kèm toàn bộ quy cách của nó).
  Future<void> _deleteVariant(
    BuildContext context,
    Db db,
    Product p,
    ProductVariant v,
  ) async {
    final ok = await confirmDialog(
      context,
      title: 'Xóa phân loại',
      message: 'Xóa "${v.name}" và toàn bộ quy cách? Không thể hoàn tác.',
      confirm: 'Xóa',
    );
    if (!ok) return;
    final variants = p.variants.where((e) => e.id != v.id).toList();
    await db.upsertProduct(_copyVariants(p, variants));
    if (context.mounted) toast(context, 'Đã xóa phân loại');
  }

  /// Sửa tên / mô tả của sản phẩm (giữ ảnh + phân loại).
  Future<void> _editProduct(BuildContext context, Db db, Product p) async {
    final nameC = TextEditingController(text: p.name);
    final descC = TextEditingController(text: p.description);

    await showModalBottomSheet(
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
                const Text(
                  'Sửa sản phẩm',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descC,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    if (nameC.text.trim().isEmpty) {
                      if (ctx.mounted) toast(ctx, 'Nhập tên sản phẩm');
                      return;
                    }
                    await db.upsertProduct(
                      Product(
                        id: p.id,
                        name: nameC.text.trim(),
                        description: descC.text.trim(),
                        imagePath: p.imagePath,
                        variants: p.variants,
                      ),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) toast(context, 'Đã lưu sản phẩm');
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

}

Product _copyVariants(Product p, List<ProductVariant> variants) => Product(
  id: p.id,
  name: p.name,
  description: p.description,
  imagePath: p.imagePath,
  variants: variants,
);

/// Mockup 2.3 — Quy cách & Giá for a variant.
class _PackagingScreen extends StatelessWidget {
  final Product product;
  final String variantId;
  const _PackagingScreen({required this.product, required this.variantId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      body: StreamBuilder<Product>(
        stream: db.product(product.id),
        builder: (context, snap) {
          final p = snap.data ?? product;
          final v = p.variants.firstWhere(
            (e) => e.id == variantId,
            orElse: () => product.variants.firstWhere((e) => e.id == variantId),
          );
          return CustomScrollView(
            slivers: [
              SliverAppBar(pinned: true, title: Text(v.name)),
              SliverToBoxAdapter(
                child: Padding(
                  // Chừa chỗ cho thanh điều hướng Android — xem ghi chú ở màn
                  // chi tiết sản phẩm.
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _editPackaging(context, db, p, v, null),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm quy cách'),
                      ),
                      const SizedBox(height: 12),
                      for (final pk in v.packagings)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              pk.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: pk.active
                                ? null
                                : const Text(
                                    'Ngừng bán',
                                    style: TextStyle(color: AppColors.danger),
                                  ),
                            trailing: Text(
                              money(pk.price),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: AppColors.primary,
                              ),
                            ),
                            onTap: () => _editPackaging(context, db, p, v, pk),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editPackaging(
    BuildContext context,
    Db db,
    Product p,
    ProductVariant v,
    Packaging? existing,
  ) async {
    // Tách tên quy cách thành số lượng + đơn vị (VD "1kg" → "1" + "kg").
    String qtyInit = '1';
    String unitInit = 'kg';
    if (existing != null && existing.name.isNotEmpty) {
      final m = RegExp(r'^\s*([\d.,]+)\s*(.*)$').firstMatch(existing.name);
      if (m != null) {
        qtyInit = m.group(1)!.trim();
        final u = m.group(2)!.trim();
        if (u.isNotEmpty) unitInit = u;
      } else {
        unitInit = existing.name.trim();
      }
    }
    final qtyC = TextEditingController(text: qtyInit);
    String unit = unitInit;
    final priceC = TextEditingController(
      text: existing == null ? '' : moneyPlain(existing.price),
    );
    final costC = TextEditingController(
      text: existing == null ? '' : moneyPlain(existing.costPrice),
    );
    final noteC = TextEditingController(text: existing?.note ?? '');
    bool active = existing?.active ?? true;

    await showModalBottomSheet(
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
                  existing == null ? 'Thêm quy cách' : 'Sửa quy cách',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qtyC,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Số lượng',
                          hintText: '1',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final picked = await _pickUnit(ctx, db, unit);
                          if (picked != null) setSheet(() => unit = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị',
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(unit)),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Đơn vị tính giá bên dưới',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Giá bán',
                    suffixText: 'đ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Giá vốn (tham khảo)',
                    suffixText: 'đ',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Trạng thái'),
                  subtitle: Text(active ? 'Đang bán' : 'Ngừng bán'),
                  value: active,
                  onChanged: (v) => setSheet(() => active = v),
                ),
                TextField(
                  controller: noteC,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (existing != null)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                          ),
                          onPressed: () async {
                            final pks = v.packagings
                                .where((e) => e.id != existing.id)
                                .toList();
                            await _saveVariant(db, p, v, pks);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              toast(context, 'Đã xóa quy cách');
                            }
                          },
                          child: const Text('Xóa'),
                        ),
                      ),
                    if (existing != null) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final newPrice = parseMoney(priceC.text);
                          final pk = Packaging(
                            id: existing?.id,
                            name: '${qtyC.text.trim()}$unit',
                            price: newPrice,
                            costPrice: parseMoney(costC.text),
                            active: active,
                            note: noteC.text.trim(),
                          );
                          final pks = existing == null
                              ? [...v.packagings, pk]
                              : v.packagings
                                    .map((e) => e.id == pk.id ? pk : e)
                                    .toList();
                          await _saveVariant(db, p, v, pks);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            toast(
                              context,
                              existing == null
                                  ? 'Đã thêm quy cách'
                                  : 'Đã lưu quy cách',
                            );
                          }
                        },
                        child: const Text('Lưu'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveVariant(
    Db db,
    Product p,
    ProductVariant v,
    List<Packaging> pks,
  ) async {
    final newV = ProductVariant(id: v.id, name: v.name, packagings: pks);
    final variants = p.variants.map((e) => e.id == v.id ? newV : e).toList();
    await db.upsertProduct(_copyVariants(p, variants));
  }

  /// Bottom sheet chọn đơn vị (đọc list từ Db, thêm đơn vị khác → lưu lại).
  Future<String?> _pickUnit(BuildContext context, Db db, String current) {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: StreamBuilder<List<String>>(
          stream: db.units(),
          builder: (ctx, snap) {
            final units = snap.data ?? Db.defaultUnits;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHeader('Chọn đơn vị'),
                for (final u in units)
                  ListTile(
                    leading: const Icon(
                      Icons.straighten,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      u,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: current == u
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, u),
                  ),
                ListTile(
                  leading: const Icon(Icons.add, color: AppColors.primary),
                  title: const Text('Thêm đơn vị khác'),
                  onTap: () async {
                    final custom = await _addUnitDialog(ctx);
                    if (custom == null || custom.isEmpty) return;
                    await db.addUnit(custom); // lưu vĩnh viễn vào list
                    if (ctx.mounted) Navigator.pop(ctx, custom);
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<String?> _addUnitDialog(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Đơn vị mới'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên đơn vị',
              hintText: 'VD: gói, thùng, lon',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}
