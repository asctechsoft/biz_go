import 'package:uuid/uuid.dart';

/// Danh mục → Sản phẩm → Phân loại (variant) → Quy cách/Bao bì (packaging) → Giá.

class ProductCategory {
  final String id;
  final String name;
  ProductCategory({required this.id, required this.name});

  factory ProductCategory.fromMap(String id, Map<String, dynamic> m) =>
      ProductCategory(id: id, name: m['name'] ?? '');
  Map<String, dynamic> toMap() => {'name': name};
}

class Packaging {
  final String id;
  final String name; // 500g, 1kg, 2kg
  final int price; // giá bán (đồng)
  final int costPrice; // giá vốn tham khảo
  final bool active; // đang bán
  final String note;

  Packaging({
    String? id,
    required this.name,
    required this.price,
    this.costPrice = 0,
    this.active = true,
    this.note = '',
  }) : id = id ?? const Uuid().v4();

  factory Packaging.fromMap(Map<String, dynamic> m) => Packaging(
        id: m['id'],
        name: m['name'] ?? '',
        price: (m['price'] ?? 0) as int,
        costPrice: (m['costPrice'] ?? 0) as int,
        active: m['active'] ?? true,
        note: m['note'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'costPrice': costPrice,
        'active': active,
        'note': note,
      };
}

class ProductVariant {
  final String id;
  final String name; // Khoai mật dẻo, Khoai mật sấy
  final List<Packaging> packagings;

  ProductVariant({
    String? id,
    required this.name,
    this.packagings = const [],
  }) : id = id ?? const Uuid().v4();

  factory ProductVariant.fromMap(Map<String, dynamic> m) => ProductVariant(
        id: m['id'],
        name: m['name'] ?? '',
        packagings: ((m['packagings'] as List?) ?? [])
            .map((e) => Packaging.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'packagings': packagings.map((e) => e.toMap()).toList(),
      };
}

/// One price-change record (spec §5.3). Old orders keep their snapshot.
class PriceHistory {
  final String id;
  final String productName;
  final String variantId;
  final String variantName;
  final String packagingName;
  final int oldPrice;
  final int newPrice;
  final String actorName;
  final DateTime at;

  PriceHistory({
    required this.id,
    this.productName = '',
    this.variantId = '',
    this.variantName = '',
    this.packagingName = '',
    required this.oldPrice,
    required this.newPrice,
    this.actorName = '',
    required this.at,
  });

  factory PriceHistory.fromMap(String id, Map<String, dynamic> m) => PriceHistory(
        id: id,
        productName: m['productName'] ?? '',
        variantId: m['variantId'] ?? '',
        variantName: m['variantName'] ?? '',
        packagingName: m['packagingName'] ?? '',
        oldPrice: (m['oldPrice'] ?? 0) as int,
        newPrice: (m['newPrice'] ?? 0) as int,
        actorName: m['actorName'] ?? '',
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] ?? 0) as int),
      );
}

class Product {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final String? imagePath; // local compressed image path
  final List<ProductVariant> variants;

  Product({
    required this.id,
    required this.name,
    this.description = '',
    required this.categoryId,
    this.categoryName = '',
    this.imagePath,
    this.variants = const [],
  });

  int get variantCount => variants.length;

  factory Product.fromMap(String id, Map<String, dynamic> m) => Product(
        id: id,
        name: m['name'] ?? '',
        description: m['description'] ?? '',
        categoryId: m['categoryId'] ?? '',
        categoryName: m['categoryName'] ?? '',
        imagePath: m['imagePath'],
        variants: ((m['variants'] as List?) ?? [])
            .map((e) => ProductVariant.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'imagePath': imagePath,
        'variants': variants.map((e) => e.toMap()).toList(),
        'nameLower': name.toLowerCase(),
      };
}
