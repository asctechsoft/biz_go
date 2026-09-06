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
      appBar: AppBar(title: const Text('Sản phẩm')),
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
                    final p = Product(
                      id: '',
                      name: nameC.text.trim(),
                      description: descC.text.trim(),
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

}
