import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/demo_accounts.dart';
import '../models/customer.dart';
import '../models/fleet.dart';
import '../models/product.dart';
import 'auth_service.dart';

/// Seeds demo catalog/customers/fleet + a demo admin account so the app is
/// usable immediately. Idempotent via meta/seeded flag.
class SeedService {
  final _db = FirebaseFirestore.instance;
  final _auth = AuthService();

  static const demoPhone = '0900000000'; // Chủ — điền sẵn ở màn login
  static const demoPassword = DemoAccounts.password;

  Future<bool> isSeeded() async {
    final doc = await _db.collection('meta').doc('seeded').get();
    return doc.exists && (doc.data()?['done'] == true);
  }

  /// Tạo tài khoản Chủ ban đầu (theo DemoAccounts.list). Các vai trò khác do
  /// Chủ tự tạo qua "Quản lý người dùng". Idempotent.
  Future<void> ensureDemoUser() async {
    for (final a in DemoAccounts.list) {
      await _auth.ensureAccount(
        phone: a.$1,
        password: DemoAccounts.password,
        name: a.$2,
        role: a.$3,
        // Tài khoản bootstrap → buộc đổi SĐT/mật khẩu ở lần đăng nhập đầu.
        mustChangeCredentials: true,
      );
    }
  }

  Future<void> seedAll() async {
    if (await isSeeded()) return;

    // Categories
    final cats = <String, String>{};
    for (final name in ['Khoai lang', 'Ngô chiên', 'Cùi bưởi', 'Khoai dẻo']) {
      final ref = await _db.collection('categories').add({'name': name});
      cats[name] = ref.id;
    }

    Product p(String name, String cat, String desc, List<ProductVariant> v) =>
        Product(
          id: '',
          name: name,
          description: desc,
          categoryId: cats[cat]!,
          categoryName: cat,
          variants: v,
        );

    ProductVariant vr(String name, List<Packaging> pk) =>
        ProductVariant(name: name, packagings: pk);
    Packaging pk(String name, int price, int cost) =>
        Packaging(name: name, price: price, costPrice: cost);

    final products = [
      p('Khoai lang mật', 'Khoai lang', 'Khoai lang mật sấy dẻo', [
        vr('Khoai mật dẻo', [
          pk('500g', 55000, 30000),
          pk('1kg', 100000, 60000),
          pk('2kg', 190000, 115000),
        ]),
        vr('Khoai mật sấy', [
          pk('500g', 60000, 35000),
          pk('1kg', 110000, 65000),
        ]),
      ]),
      p('Khoai lang tím', 'Khoai lang', 'Khoai lang tím sấy dẻo', [
        vr('Khoai tím dẻo', [pk('500g', 60000, 32000), pk('1kg', 110000, 62000)]),
      ]),
      p('Ngô chiên', 'Ngô chiên', 'Ngô chiên giòn', [
        vr('Ngô chiên giòn', [pk('250g', 55000, 30000), pk('500g', 100000, 58000)]),
      ]),
      p('Cùi bưởi sấy', 'Cùi bưởi', 'Cùi bưởi sấy dẻo', [
        vr('Cùi bưởi sấy dẻo', [pk('200g', 45000, 25000), pk('500g', 85000, 50000)]),
      ]),
    ];
    for (final prod in products) {
      await _db.collection('products').add(prod.toMap());
    }

    // Customers
    final customers = [
      Customer(
        id: '',
        name: 'Trần Thị Mai',
        phone: '0988123456',
        note: 'Khách quen, giao giờ hành chính',
        addresses: [
          CustomerAddress(
              label: 'Nhà riêng',
              receiver: 'Trần Thị Mai',
              phone: '0988123456',
              address: '25 Nguyễn Trãi, Hà Nội',
              isDefault: true),
          CustomerAddress(
              label: 'Cửa hàng 1',
              receiver: 'Trần Thị Mai',
              phone: '0988123456',
              address: '18 Trần Phú, Hà Nội'),
        ],
      ),
      Customer(
          id: '',
          name: 'Nguyễn Văn A',
          phone: '0977888999',
          addresses: [
            CustomerAddress(
                label: 'Nhà riêng',
                receiver: 'Nguyễn Văn A',
                phone: '0977888999',
                address: '12 Láng Hạ, Hà Nội',
                isDefault: true),
          ]),
      Customer(
          id: '',
          name: 'Lê Thị Hằng',
          phone: '0966555444',
          addresses: [
            CustomerAddress(
                label: 'Nhà riêng',
                receiver: 'Lê Thị Hằng',
                phone: '0966555444',
                address: '56 Lê Lợi, Hà Nội',
                isDefault: true),
          ]),
      Customer(
          id: '',
          name: 'Phạm Văn Cường',
          phone: '0933222111',
          addresses: [
            CustomerAddress(
                label: 'Nhà riêng',
                receiver: 'Phạm Văn Cường',
                phone: '0933222111',
                address: '100 Phan Đình Phùng, Hà Nội',
                isDefault: true),
          ]),
    ];
    for (final c in customers) {
      await _db.collection('customers').add(c.toMap());
    }

    // Vehicles + drivers
    final v1 = await _db.collection('vehicles').add(Vehicle(
            id: '', plate: '29C-12345', type: 'Tải 1.25T', capacityKg: 1250)
        .toMap());
    await _db.collection('vehicles').add(
        Vehicle(id: '', plate: '29H-67890', type: 'Van', capacityKg: 800).toMap());
    await _db.collection('drivers').add(Driver(
            id: '',
            name: 'Nguyễn Văn A',
            phone: '0988555666',
            defaultVehicleId: v1.id)
        .toMap());
    await _db
        .collection('drivers')
        .add(Driver(id: '', name: 'Trần Văn B', phone: '0977111222').toMap());

    await _db.collection('meta').doc('seeded').set({'done': true});
  }
}
