import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
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
                body: Center(child: CircularProgressIndicator()));
          }
          final p = snap.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(p.name),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: ImagePickerBox(
                          path: p.imagePath,
                          size: 160,
                          onTap: () async {
                            final path = await pickImage(
                                context, context.read<ImageService>());
                            if (path != null) {
                              await db.upsertProduct(_copyVariants(
                                  Product(
                                    id: p.id,
                                    name: p.name,
                                    description: p.description,
                                    categoryId: p.categoryId,
                                    categoryName: p.categoryName,
                                    imagePath: path,
                                  ),
                                  p.variants));
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(p.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      if (p.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(p.description,
                            style:
                                const TextStyle(color: AppColors.textSecondary)),
                      ],
                      const Divider(height: 28),
                      KVRow('Danh mục', p.categoryName),
                      const SizedBox(height: 16),
                      const Text('Phân loại',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final v in p.variants)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(v.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text('${v.packagings.length} quy cách'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _PackagingScreen(
                                    product: p, variantId: v.id),
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
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên phân loại'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Thêm')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      final variants = [...p.variants, ProductVariant(name: c.text.trim())];
      await db.upsertProduct(_copyVariants(p, variants));
    }
  }
}

Product _copyVariants(Product p, List<ProductVariant> variants) => Product(
      id: p.id,
      name: p.name,
      description: p.description,
      categoryId: p.categoryId,
      categoryName: p.categoryName,
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
          final v = p.variants.firstWhere((e) => e.id == variantId,
              orElse: () => product.variants.firstWhere((e) => e.id == variantId));
          return CustomScrollView(
            slivers: [
              SliverAppBar(pinned: true, title: Text(v.name)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                            title: Text(pk.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16)),
                            subtitle: pk.active
                                ? null
                                : const Text('Ngừng bán',
                                    style: TextStyle(color: AppColors.danger)),
                            trailing: Text(money(pk.price),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppColors.primary)),
                            onTap: () =>
                                _editPackaging(context, db, p, v, pk),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _PriceHistorySection(productId: p.id, variantId: v.id),
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

  Future<void> _editPackaging(BuildContext context, Db db, Product p,
      ProductVariant v, Packaging? existing) async {
    final nameC = TextEditingController(text: existing?.name ?? '');
    final priceC =
        TextEditingController(text: existing == null ? '' : '${existing.price}');
    final costC = TextEditingController(
        text: existing == null ? '' : '${existing.costPrice}');
    final noteC = TextEditingController(text: existing?.note ?? '');
    bool active = existing?.active ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'Thêm quy cách' : 'Sửa quy cách',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                    controller: nameC,
                    decoration: const InputDecoration(
                        labelText: 'Quy cách', hintText: '1kg')),
                const SizedBox(height: 12),
                TextField(
                    controller: priceC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Giá bán (đồng)')),
                const SizedBox(height: 12),
                TextField(
                    controller: costC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Giá vốn (tham khảo)')),
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
                    decoration: const InputDecoration(labelText: 'Ghi chú')),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (existing != null)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger)),
                          onPressed: () async {
                            final pks = v.packagings
                                .where((e) => e.id != existing.id)
                                .toList();
                            await _saveVariant(db, p, v, pks);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('Xóa'),
                        ),
                      ),
                    if (existing != null) const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final newPrice = int.tryParse(
                                  priceC.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0;
                          final pk = Packaging(
                            id: existing?.id,
                            name: nameC.text.trim(),
                            price: newPrice,
                            costPrice: int.tryParse(
                                    costC.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
                                0,
                            active: active,
                            note: noteC.text.trim(),
                          );
                          final pks = existing == null
                              ? [...v.packagings, pk]
                              : v.packagings
                                  .map((e) => e.id == pk.id ? pk : e)
                                  .toList();
                          await _saveVariant(db, p, v, pks);
                          // §5.3: ghi lịch sử khi sửa giá.
                          if (existing != null && existing.price != newPrice) {
                            final user = ctx.read<AuthProvider>().user;
                            await db.logPriceChange(
                              productId: p.id,
                              productName: p.name,
                              variantId: v.id,
                              variantName: v.name,
                              packagingId: pk.id,
                              packagingName: pk.name,
                              oldPrice: existing.price,
                              newPrice: newPrice,
                              actorId: user?.id ?? '',
                              actorName: user?.name ?? '',
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
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
      Db db, Product p, ProductVariant v, List<Packaging> pks) async {
    final newV = ProductVariant(id: v.id, name: v.name, packagings: pks);
    final variants =
        p.variants.map((e) => e.id == v.id ? newV : e).toList();
    await db.upsertProduct(_copyVariants(p, variants));
  }
}

/// §5.3 — lịch sử thay đổi giá của các quy cách trong phân loại.
class _PriceHistorySection extends StatelessWidget {
  final String productId;
  final String variantId;
  const _PriceHistorySection(
      {required this.productId, required this.variantId});

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return StreamBuilder<List<PriceHistory>>(
      stream: db.priceHistory(productId),
      builder: (context, snap) {
        final all = (snap.data ?? [])
            .where((h) => h.variantId == variantId || h.variantId.isEmpty)
            .toList();
        if (all.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Lịch sử giá',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SectionCard(
              child: Column(
                children: [
                  for (final h in all.take(20))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(h.packagingName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${fmtDateTime(h.at)}${h.actorName.isEmpty ? '' : ' · ${h.actorName}'}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text('${money(h.oldPrice)} → ',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  decoration: TextDecoration.lineThrough)),
                          Text(money(h.newPrice),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
