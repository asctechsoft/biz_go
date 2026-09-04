import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/product.dart';
import '../../services/db.dart';
import '../../services/image_service.dart';
import '../../widgets/common.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sản phẩm'),
        actions: [
          TextButton.icon(
            onPressed: () => _manageCategories(context, db),
            icon: const Icon(Icons.category, color: Colors.white, size: 20),
            label: const Text(
              'Danh mục',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm sản phẩm...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: db.products(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!
                    .where((p) => p.name.toLowerCase().contains(_q))
                    .toList();
                if (items.isEmpty) {
                  return const EmptyState(text: 'Chưa có sản phẩm');
                }
                return SlidableAutoCloseBehavior(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = items[i];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Slidable(
                          key: ValueKey(p.id),
                          groupTag: 'products',
                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            extentRatio: 0.28, // hé lộ ~1/4, không dismiss hết
                            children: [
                              SlidableAction(
                                onPressed: (ctx) => _deleteProduct(ctx, db, p),
                                backgroundColor: AppColors.danger,
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Xóa',
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.white,
                            child: InkWell(
                              onTap: () => context.push('/products/${p.id}'),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(14),
                                  ),
                                ),
                                child: ListTile(
                                  leading: LocalImage(
                                    path: p.imagePath,
                                    size: 52,
                                  ),
                                  title: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text('${p.variantCount} loại'),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: () => _addProduct(context, db),
                icon: const Icon(Icons.add),
                label: const Text('Thêm sản phẩm'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(BuildContext context, Db db) async {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    String? selectedId;
    String? imagePath;
    final imgSvc = context.read<ImageService>();

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
                  'Thêm sản phẩm',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ImagePickerBox(
                    path: imagePath,
                    onTap: () async {
                      final path = await pickImage(ctx, imgSvc);
                      if (path != null) setSheet(() => imagePath = path);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Chạm để chọn ảnh',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                ),
                const SizedBox(height: 12),
                // Danh mục — cập nhật trực tiếp khi thêm mới.
                StreamBuilder<List<ProductCategory>>(
                  stream: db.categories(),
                  builder: (context, snap) {
                    final cats = snap.data ?? [];
                    if (cats.isNotEmpty &&
                        !cats.any((c) => c.id == selectedId)) {
                      selectedId = cats.first.id;
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              final sel = cats.where((c) => c.id == selectedId);
                              final label = sel.isEmpty ? '' : sel.first.name;
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: cats.isEmpty
                                    ? null
                                    : () async {
                                        final picked = await _pickCategory(
                                          ctx,
                                          cats,
                                          selectedId,
                                        );
                                        if (picked != null) {
                                          setSheet(() => selectedId = picked);
                                        }
                                      },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: cats.isEmpty
                                        ? 'Chưa có danh mục — bấm +'
                                        : 'Danh mục',
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          label.isEmpty ? 'Chọn...' : label,
                                          style: TextStyle(
                                            color: label.isEmpty
                                                ? AppColors.textSecondary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.arrow_drop_down,
                                        color: AppColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: AppColors.primary,
                          ),
                          tooltip: 'Thêm danh mục',
                          onPressed: () async {
                            final id = await _addCategoryDialog(ctx, db);
                            if (id != null) setSheet(() => selectedId = id);
                          },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descC,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final cats = await db.categories().first;
                    final cat = cats.where((c) => c.id == selectedId);
                    if (nameC.text.trim().isEmpty || cat.isEmpty) {
                      if (ctx.mounted) {
                        toast(ctx, 'Nhập tên và chọn danh mục');
                      }
                      return;
                    }
                    final p = Product(
                      id: '',
                      name: nameC.text.trim(),
                      description: descC.text.trim(),
                      categoryId: cat.first.id,
                      categoryName: cat.first.name,
                      imagePath: imagePath,
                    );
                    final id = await db.upsertProduct(p);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      toast(context, 'Đã thêm sản phẩm');
                      context.push('/products/$id');
                    }
                  },
                  child: const Text('Lưu sản phẩm'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteProduct(BuildContext context, Db db, Product p) async {
    final imgSvc = context.read<ImageService>();
    final ok = await confirmDialog(
      context,
      title: 'Xóa sản phẩm',
      message: 'Xóa "${p.name}"? Không thể hoàn tác.',
      confirm: 'Xóa',
    );
    if (!ok) return;
    if (context.mounted) toast(context, 'Đã xóa sản phẩm');
    // Co hàng lại (đẩy các dòng dưới lên) rồi mới xóa dữ liệu.
    final slidable = context.mounted ? Slidable.of(context) : null;
    if (slidable != null) {
      slidable.dismiss(
        ResizeRequest(const Duration(milliseconds: 300), () {
          imgSvc.delete(p.imagePath);
          db.deleteProduct(p.id);
        }),
      );
    } else {
      await imgSvc.delete(p.imagePath);
      await db.deleteProduct(p.id);
    }
  }

  /// Bottom sheet chọn danh mục → trả về id đã chọn.
  Future<String?> _pickCategory(
    BuildContext context,
    List<ProductCategory> cats,
    String? current,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Chọn danh mục',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in cats)
              ListTile(
                leading: const Icon(
                  Icons.label_outline,
                  color: AppColors.primary,
                ),
                title: Text(
                  c.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: current == c.id
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, c.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Dialog nhập tên danh mục mới → trả về id vừa tạo.
  Future<String?> _addCategoryDialog(BuildContext context, Db db) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Thêm danh mục'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên danh mục'),
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
    if (name == null || name.isEmpty) return null;
    final id = await db.upsertCategory(ProductCategory(id: '', name: name));
    if (context.mounted) toast(context, 'Đã thêm danh mục');
    return id;
  }

  /// Dialog sửa tên danh mục (giữ id).
  Future<void> _editCategoryDialog(
    BuildContext context,
    Db db,
    ProductCategory cat,
  ) async {
    final c = TextEditingController(text: cat.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Sửa danh mục'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên danh mục'),
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
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == cat.name) return;
    await db.upsertCategory(ProductCategory(id: cat.id, name: name));
    if (context.mounted) toast(context, 'Đã cập nhật danh mục');
  }

  /// Quản lý danh mục: xem / thêm / xóa.
  Future<void> _manageCategories(BuildContext context, Db db) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Danh mục',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: () => _addCategoryDialog(ctx, db),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: StreamBuilder<List<ProductCategory>>(
                stream: db.categories(),
                builder: (context, snap) {
                  final cats = snap.data ?? [];
                  if (cats.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Chưa có danh mục',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in cats)
                        ListTile(
                          leading: const Icon(
                            Icons.label_outline,
                            color: AppColors.primary,
                          ),
                          title: Text(c.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.primary,
                                ),
                                tooltip: 'Sửa tên',
                                onPressed: () =>
                                    _editCategoryDialog(ctx, db, c),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                ),
                                onPressed: () async {
                                  final ok = await confirmDialog(
                                    ctx,
                                    title: 'Xóa danh mục',
                                    message:
                                        'Xóa "${c.name}"? Sản phẩm cũ không bị ảnh hưởng.',
                                    confirm: 'Xóa',
                                  );
                                  if (ok) {
                                    await db.deleteCategory(c.id);
                                    if (ctx.mounted) {
                                      toast(ctx, 'Đã xóa danh mục');
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
