import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../core/enums.dart';
import '../core/formatters.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/carrier.dart';
import '../models/customer.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../models/product.dart';
import '../models/shop_info.dart';

/// Single Firestore gateway. Business actions (create order, record payment,
/// status transitions) run in transactions and always append timeline +
/// notifications, per spec §20.
class Db {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('customers');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection('payments');
  CollectionReference<Map<String, dynamic>> get _notifs =>
      _db.collection('notifications');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _carriers =>
      _db.collection('carriers');

  // ---------- Thông tin cửa hàng in trên phiếu ----------
  DocumentReference<Map<String, dynamic>> get _shopDoc =>
      _db.collection('meta').doc('shop');

  /// Tiêu đề + SĐT in trên phiếu giao hàng.
  ///
  /// Chưa đặt SĐT riêng thì lấy SĐT tài khoản **Chủ** — số Chủ nhập lúc thiết
  /// lập lần đầu, nên phiếu có số đúng ngay mà không cần vào Cài đặt.
  Stream<ShopInfo> shopInfo() => _shopDoc.snapshots().asyncMap((d) async {
    final info = ShopInfo.fromMap(d.data());
    if (info.phone.isNotEmpty) return info;
    return info.copyWith(phone: await _ownerPhone());
  });

  /// Bản ghi **thô** ở `meta/shop` — KHÔNG thay SĐT trống bằng số của Chủ.
  /// Màn Cài đặt phiếu cần bản này để biết người dùng có đặt SĐT riêng hay
  /// không; nếu dùng [shopInfo] thì ô nhập sẽ bị đổ sẵn số của Chủ và bấm Lưu
  /// là chép cứng số đó vào, Chủ đổi số sau này phiếu vẫn in số cũ.
  Future<ShopInfo> shopInfoRaw() async =>
      ShopInfo.fromMap((await _shopDoc.get()).data());

  /// SĐT của tài khoản Chủ. Chuỗi rỗng nếu chưa có Chủ (chưa thiết lập xong).
  ///
  /// Có thể có **nhiều Chủ** (2 người cùng quản 1 cửa hàng) nên phải chọn
  /// **tất định**: sắp theo uid rồi lấy đầu. Nếu dùng `limit(1)` thì Firestore
  /// trả doc nào tuỳ lúc → phiếu in lúc ra số Chủ này, lúc ra số Chủ kia.
  /// Muốn chắc chắn thì đặt SĐT riêng ở **Cài đặt phiếu**.
  Future<String> ownerPhone() => _ownerPhone();

  Future<String> _ownerPhone() async {
    final owners = await _ownerDocs();
    if (owners.isEmpty) return '';
    owners.sort((a, b) => a.id.compareTo(b.id));
    return (owners.first.data()['phone'] as String?)?.trim() ?? '';
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _ownerDocs() async => (await _users
          .where('role', isEqualTo: UserRole.owner.name)
          .get())
      .docs;

  /// Số tài khoản Chủ hiện có. Dùng để KHÔNG cho xoá/hạ cấp/khoá Chủ cuối cùng
  /// — mất hết Chủ là không ai vào được Quản lý người dùng để dựng lại.
  Future<int> _ownerCount() async => (await _ownerDocs()).length;

  /// Số Chủ còn **bật** (active). Khoá nốt người cuối cũng khoá luôn quản trị.
  Future<int> _activeOwnerCount() async =>
      (await _ownerDocs()).where((d) => d.data()['active'] != false).length;

  Future<void> saveShopInfo(ShopInfo info) =>
      _shopDoc.set(info.toMap(), SetOptions(merge: true));

  // ---------- Users (quản lý người dùng) ----------
  Stream<List<AppUser>> users() => _users.snapshots().map(
    (s) =>
        s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
          ..sort((a, b) => a.role.index.compareTo(b.role.index)),
  );

  Future<void> setUserActive(String uid, bool active) async {
    if (!active) {
      final snap = await _users.doc(uid).get();
      if (roleFromName(snap.data()?['role']) == UserRole.owner &&
          await _activeOwnerCount() <= 1) {
        throw Exception(
          'Đây là tài khoản Chủ đang hoạt động duy nhất — khoá lại thì không '
          'ai quản trị được nữa.',
        );
      }
    }
    await _users.doc(uid).update({'active': active});
  }

  /// Xoá hồ sơ người dùng (bấm nhầm khi tạo tài khoản thì xoá được).
  ///
  /// CHỈ xoá doc Firestore — tài khoản **Firebase Auth không xoá được từ
  /// client** (cần Admin SDK ở `noti-server` hoặc xoá tay trong Console). Hệ
  /// quả: (1) người bị xoá không đăng nhập được nữa vì `AuthService.signIn`
  /// từ chối account không có hồ sơ; (2) SĐT đó vẫn bị chiếm, tạo lại cùng số
  /// sẽ báo `email-already-in-use`.
  Future<void> deleteUser(
    String uid, {
    String actorId = '',
    String actorName = '',
  }) async {
    final snap = await _users.doc(uid).get();
    if (!snap.exists) return; // ai đó vừa xoá rồi — coi như xong
    if (uid == actorId) {
      throw Exception('Không thể tự xoá tài khoản của chính mình.');
    }
    // Chặn ở tầng Db chứ không chỉ ở UI: 2 Chủ cùng mở màn này, mỗi người xoá
    // người kia thì danh sách trên máy ai cũng còn 2 dòng, UI cho qua hết.
    if (roleFromName(snap.data()?['role']) == UserRole.owner &&
        await _ownerCount() <= 1) {
      throw Exception(
        'Đây là tài khoản Chủ duy nhất — xoá đi thì không ai quản trị được nữa.',
      );
    }
    await _users.doc(uid).delete();
    await _audit(
      action: 'DELETE_USER',
      entityType: 'user',
      entityId: uid,
      actorId: actorId,
      actorName: actorName,
      before: snap.data(),
      note: 'Xoá hồ sơ người dùng (tài khoản Firebase Auth vẫn còn)',
    );
  }

  /// Cập nhật hồ sơ user (tên / vai trò). Không đổi SĐT vì gắn với đăng nhập.
  ///
  /// Hạ cấp Chủ cuối cùng bị chặn — nếu không thì tự tay bấm nhầm là khoá
  /// chính mình ra ngoài, không còn ai vào `/users` để dựng lại Chủ.
  Future<void> updateUser(String uid, {String? name, UserRole? role}) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (role != null) data['role'] = role.name;
    if (data.isEmpty) return;
    if (role != null && role != UserRole.owner) {
      final snap = await _users.doc(uid).get();
      if (roleFromName(snap.data()?['role']) == UserRole.owner &&
          await _ownerCount() <= 1) {
        throw Exception(
          'Đây là tài khoản Chủ duy nhất — đổi vai trò thì không ai quản trị '
          'được nữa. Tạo thêm một Chủ khác trước đã.',
        );
      }
    }
    await _users.doc(uid).update(data);
  }

  CollectionReference<Map<String, dynamic>> get _priceHistory =>
      _db.collection('price_history');
  CollectionReference<Map<String, dynamic>> get _audits =>
      _db.collection('audit_logs');

  // ---------- Audit log (spec §2, §20) ----------
  Future<void> _audit({
    required String action,
    required String entityType,
    required String entityId,
    String actorId = '',
    String actorName = '',
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String note = '',
  }) async {
    await _audits.add({
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'actorId': actorId,
      'actorName': actorName,
      'before': before,
      'after': after,
      'note': note,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<List<AuditLog>> audits({int limit = 200}) => _audits
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => AuditLog.fromMap(d.id, d.data())).toList());

  // ---------- Products ----------
  Stream<List<Product>> products() => _products
      .orderBy('nameLower')
      .snapshots()
      .map((s) => s.docs.map((d) => Product.fromMap(d.id, d.data())).toList());

  Stream<Product> product(String id) => _products
      .doc(id)
      .snapshots()
      .map((d) => Product.fromMap(d.id, d.data()!));

  Future<String> upsertProduct(Product p) async {
    if (p.id.isEmpty) {
      final ref = await _products.add(p.toMap());
      return ref.id;
    }
    await _products.doc(p.id).set(p.toMap());
    return p.id;
  }

  Future<void> deleteProduct(String id) => _products.doc(id).delete();

  // ---------- Đơn vị quy cách (units) ----------
  static const defaultUnits = ['gam', 'kg', 'tạ', 'tấn'];
  DocumentReference<Map<String, dynamic>> get _unitsDoc =>
      _db.collection('meta').doc('product_units');

  /// Danh sách đơn vị: mặc định + các đơn vị tùy chỉnh đã lưu.
  Stream<List<String>> units() => _unitsDoc.snapshots().map((d) {
    final custom = ((d.data()?['items'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final all = [...defaultUnits];
    for (final u in custom) {
      if (!all.contains(u)) all.add(u);
    }
    return all;
  });

  /// Lưu đơn vị tùy chỉnh mới vào list (bỏ qua nếu trùng default).
  Future<void> addUnit(String unit) async {
    final u = unit.trim();
    if (u.isEmpty || defaultUnits.contains(u)) return;
    await _unitsDoc.set({
      'items': FieldValue.arrayUnion([u]),
    }, SetOptions(merge: true));
  }

  // ---------- Nhà xe (danh mục) ----------
  // Sổ tay nhà xe hay dùng: khai một lần ở Cài đặt › Nhà xe rồi chọn lại khi
  // thêm địa chỉ khách. Chỉ là **gợi ý** — địa chỉ khách và đơn hàng vẫn giữ
  // bản chép riêng, nên sửa/xoá ở đây không đổi dữ liệu cũ.

  /// Danh mục nhà xe, sắp theo tên. KHÔNG `orderBy('nameLower')` — doc thiếu
  /// field đó bị Firestore loại thẳng khỏi kết quả; sort trong Dart cho chắc.
  Stream<List<Carrier>> carriers() => _carriers.snapshots().map((s) {
    final list = s.docs.map((d) => Carrier.fromMap(d.id, d.data())).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });

  Future<String> upsertCarrier(Carrier c) async {
    if (c.id.isEmpty) {
      final ref = await _carriers.add(c.toMap());
      return ref.id;
    }
    await _carriers.doc(c.id).set(c.toMap());
    return c.id;
  }

  /// Xoá nhà xe khỏi danh mục. Địa chỉ khách / đơn cũ đang ghi tên nhà xe này
  /// KHÔNG bị ảnh hưởng (chuỗi đã chép sang), chỉ mất gợi ý cho lần sau.
  Future<void> deleteCarrier(String id) => _carriers.doc(id).delete();

  // ---------- Customers ----------
  // KHÔNG orderBy('nameLower'): doc khách cũ chưa có field đó bị Firestore
  // loại thẳng khỏi kết quả → khách "biến mất". Lấy hết rồi sort trong Dart
  // (đúng convention tránh index). Doc nào parse lỗi thì bỏ qua + log, đừng
  // để một doc hỏng làm chết cả stream (spinner quay vô tận).
  Stream<List<Customer>> customers() => _customers.snapshots().map((s) {
        final list = <Customer>[];
        for (final d in s.docs) {
          try {
            list.add(Customer.fromMap(d.id, d.data()));
          } catch (e) {
            debugPrint('CUSTOMER PARSE ERROR ${d.id}: $e');
          }
        }
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  Stream<Customer> customer(String id) => _customers
      .doc(id)
      .snapshots()
      .map((d) => Customer.fromMap(d.id, d.data()!));

  Future<String> upsertCustomer(Customer c) async {
    if (c.id.isEmpty) {
      final ref = await _customers.add(c.toMap());
      return ref.id;
    }
    // Keep aggregate fields untouched on edit by merging.
    await _customers.doc(c.id).set(c.toMap(), SetOptions(merge: true));
    return c.id;
  }

  /// Xoá hồ sơ khách hàng.
  ///
  /// **Còn nợ thì không xoá** — xoá đi là mất dấu khoản phải thu, không đối
  /// chiếu lại được. Chặn ngay ở tầng Db chứ không chỉ ở UI: đọc lại `debt`
  /// từ Firestore ngay trước khi xoá, phòng trường hợp màn hình đang cầm dữ
  /// liệu cũ (vừa có đơn mới ghi nợ ở máy khác).
  ///
  /// Đơn cũ KHÔNG bị xoá và vẫn hiển thị đúng: đơn snapshot tên + SĐT + địa
  /// chỉ giao ngay lúc tạo, không đọc ngược sang `customers`.
  Future<void> deleteCustomer(
    String id, {
    String actorId = '',
    String actorName = '',
  }) async {
    final snap = await _customers.doc(id).get();
    final data = snap.data();
    final debt = (data?['debt'] ?? 0) as int;
    if (debt > 0) {
      throw Exception(
        'Khách còn nợ ${money(debt)} — thu hết nợ rồi mới xoá được.',
      );
    }
    await _customers.doc(id).delete();
    await _audit(
      action: 'DELETE_CUSTOMER',
      entityType: 'customer',
      entityId: id,
      actorId: actorId,
      actorName: actorName,
      before: data,
      note: 'Xoá hồ sơ khách hàng (đơn cũ giữ nguyên)',
    );
  }

  // ---------- Orders (queries) ----------
  /// Đơn trong [days] ngày gần nhất (mặc định 30).
  ///
  /// KHÔNG tải hết collection: 20 đơn/ngày thì sau vài tháng là hàng nghìn doc,
  /// mỗi lần mở tab đọc lại toàn bộ — chậm máy và tốn lượt đọc Firestore. Màn
  /// Đơn hàng tăng [days] khi bấm "Tải thêm".
  ///
  /// Range + orderBy cùng trên `createdAt` nên không cần composite index.
  Stream<List<Order>> orders({int days = 30}) {
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1)).millisecondsSinceEpoch;
    return _orders
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Order.fromMap(d.id, d.data())).toList());
  }

  /// Toàn bộ đơn, không giới hạn ngày. Dùng cho báo cáo/xuất Excel — chỗ đó
  /// người dùng chủ động chọn khoảng thời gian nên chấp nhận đọc nhiều.
  Stream<List<Order>> allOrders() => _orders
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Order.fromMap(d.id, d.data())).toList());

  /// Bật/tắt cờ **Gấp**. Đơn gấp ghim lên đầu danh sách trong ngày.
  Future<void> setOrderPriority(
    Order o,
    bool priority, {
    required String actorId,
    required String actorName,
  }) async {
    await _orders.doc(o.id).update({'priority': priority});
    await _appendTimeline(
      o.id,
      TimelineEvent(
        at: DateTime.now(),
        title: priority ? 'Đánh dấu GẤP' : 'Bỏ đánh dấu GẤP',
        actorId: actorId,
        actorName: actorName,
      ),
    );
    await _audit(
      action: priority ? 'mark_priority' : 'unmark_priority',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: {'priority': o.priority},
      after: {'priority': priority},
    );
    // Chỉ báo khi BẬT — tắt cờ thì không ai cần biết gấp gáp gì.
    if (priority) {
      await _notify(
        title: 'Đơn GẤP: ${o.code}',
        body: '${o.customerName} · cần ưu tiên xử lý trước',
        refType: NotifRefType.order,
        refId: o.id,
        roles: {UserRole.owner, UserRole.checker},
        icon: 'alert',
      );
    }
  }

  /// Trả `null` khi doc không còn (đơn bị xoá) — KHÔNG `data()!`, vì đơn xoá
  /// khi màn chi tiết đang mở hoặc mở từ thông báo cũ là crash null-check.
  Stream<Order?> order(String id) => _orders
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Order.fromMap(d.id, d.data()!) : null);

  /// Đơn có được **xoá hẳn** không: chỉ khi vừa tạo và chưa ai đụng vào.
  ///
  /// Dùng trạng thái chứ KHÔNG dùng mốc thời gian ("tạo trong 10 phút"): kho
  /// nhanh tay thì 3 phút đã soạn xong hàng — xoá lúc đó là sai; ngược lại
  /// phát hiện nhầm sau nửa tiếng mà chưa ai động vào thì xoá vẫn an toàn.
  ///
  /// Đã thu tiền thì KHÔNG xoá — phải huỷ đơn để còn ghi payment hoàn.
  static bool canDelete(Order o) =>
      o.orderStatus == OrderStatus.NEW &&
      o.warehouseStatus == WarehouseStatus.WAITING &&
      o.deliveryStatus == DeliveryStatus.WAITING_ASSIGNMENT &&
      o.paidAmount == 0;

  /// Xoá hẳn đơn tạo nhầm (khác **huỷ đơn**: huỷ giữ lại dấu vết, xoá thì mất
  /// hẳn khỏi `orders`).
  ///
  /// Trả lại đúng những gì `createOrder` đã cộng vào tổng hợp khách, và ghi
  /// `audit_logs` kèm **toàn bộ nội dung đơn** — doc gốc biến mất nên nhật ký
  /// là chỗ duy nhất còn tra lại được.
  Future<void> deleteOrder(
    Order o, {
    required String actorId,
    required String actorName,
  }) async {
    if (!canDelete(o)) {
      throw Exception(
        'Đơn đã vào quy trình hoặc đã thu tiền — dùng "Hủy đơn" thay vì xoá.',
      );
    }
    // Chặn thêm một lớp: có payment nào bám vào đơn thì xoá đơn là mất đối
    // chứng của khoản tiền đó.
    final pays = await _payments.where('orderId', isEqualTo: o.id).limit(1).get();
    if (pays.docs.isNotEmpty) {
      throw Exception('Đơn đã có phiếu thu — dùng "Hủy đơn" thay vì xoá.');
    }

    final orderRef = _orders.doc(o.id);
    final custRef = _customers.doc(o.customerId);
    Map<String, dynamic>? snapshotData;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) return; // ai đó vừa xoá rồi
      final cur = Order.fromMap(snap.id, snap.data()!);
      if (!canDelete(cur)) {
        throw Exception('Đơn vừa được xử lý nên không xoá được nữa.');
      }
      snapshotData = snap.data();

      final outstanding = cur.total - cur.paidAmount;
      tx.delete(orderRef);
      // Gỡ đúng phần `createOrder` đã cộng vào.
      tx.set(custRef, {
        'orderCount': FieldValue.increment(-1),
        'totalPurchased': FieldValue.increment(-cur.total),
        'totalPaid': FieldValue.increment(-cur.paidAmount),
        'debt': FieldValue.increment(-(outstanding > 0 ? outstanding : 0)),
      }, SetOptions(merge: true));
    });

    if (snapshotData == null) return; // đã bị xoá từ trước
    await _audit(
      action: 'delete_order',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: snapshotData,
      note: 'Xoá đơn ${o.code} · ${o.customerName} · ${money(o.total)}',
    );
    await _notify(
      title: 'Đơn ${o.code} đã bị xoá',
      body: '${o.customerName} · tạo nhầm',
      refType: NotifRefType.order,
      refId: o.id,
      // Chỉ Kiểm hàng: đây là tin cho người soạn hàng, mà kho giờ chỉ còn
      // vai trò đó lo (Sale chỉ tạo đơn, không đụng kho).
      roles: {UserRole.checker},
      icon: 'fail',
    );
  }

  Stream<List<Order>> ordersByCustomer(String customerId) => _orders
      .where('customerId', isEqualTo: customerId)
      .snapshots()
      .map(
        (s) =>
            (s.docs.map((d) => Order.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
      );

  /// Đơn đã đóng hàng, **chờ xuất phát** — nguồn cho màn Giao hàng và tab
  /// "Đã đóng" ở màn Kho. Lọc `warehouseStatus` trên Firestore rồi lọc tiếp
  /// trong Dart để khỏi cần composite index.
  Stream<List<Order>> ordersWaitingDepart() => _orders
      .where('warehouseStatus', isEqualTo: WarehouseStatus.PACKED.name)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => Order.fromMap(d.id, d.data()))
            .where(
              (o) =>
                  o.orderStatus != OrderStatus.CANCELLED &&
                  _waitingDepart.contains(o.deliveryStatus),
            )
            .toList()
          // Đơn GẤP lên đầu, còn lại theo giờ dự kiến xuất phát (chưa đặt giờ
          // thì tính giờ tạo đơn) — xem `Order.byDepartOrder`.
          ..sort(Order.byDepartOrder),
      );

  /// Đơn đang trên đường — Chủ đối soát cuối ngày ở đây.
  /// `ARRIVED` là trạng thái legacy của luồng tài xế cũ, vẫn gom vào đây để
  /// đơn kẹt lại từ trước không biến mất khỏi màn đối soát.
  Stream<List<Order>> ordersDelivering() => _orders
      .where('deliveryStatus', whereIn: _delivering.map((e) => e.name).toList())
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => Order.fromMap(d.id, d.data()))
            .where((o) => o.orderStatus != OrderStatus.CANCELLED)
            .toList()
          // Giữ nguyên thứ tự đã xếp lúc chờ đi, để người giao chạy đúng tuyến.
          ..sort(Order.byDepartOrder),
      );

  /// Đơn đã chốt trong ngày [day] — tab "Xong hôm nay" của màn đối soát.
  ///
  /// Range trên `createdAt` (lùi [lookbackDays] ngày) để KHÔNG quét cả
  /// collection — đơn chốt hôm nay thì gần như chắc chắn được tạo trong khoảng
  /// đó, mà vẫn chỉ dùng một field nên không cần composite index. Trạng thái
  /// và mốc chốt lọc tiếp trong Dart.
  Stream<List<Order>> ordersSettledOn(DateTime day, {int lookbackDays = 30}) {
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    final since = from
        .subtract(Duration(days: lookbackDays))
        .millisecondsSinceEpoch;
    return _orders
        .where('createdAt', isGreaterThanOrEqualTo: since)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Order.fromMap(d.id, d.data()))
              .where((o) {
                if (!_settled.contains(o.deliveryStatus)) return false;
                // Đơn không có field "giờ chốt" riêng → lấy mốc cuối trong
                // timeline (bước chốt luôn là event mới nhất).
                final at = o.timeline.isEmpty
                    ? o.createdAt
                    : o.timeline
                          .map((e) => e.at)
                          .reduce((a, b) => a.isAfter(b) ? a : b);
                return !at.isBefore(from) && at.isBefore(to);
              })
              .toList(),
        );
  }

  /// Trạng thái thanh toán do **người dùng tự chốt** — `Db` KHÔNG tự suy lại
  /// từ số tiền đã thu. `REFUNDED` cũng bất động nhưng do `cancelOrder` sinh
  /// ra nên không nằm ở đây.
  static const _userSetPayStatus = {
    PaymentStatus.COD,
    PaymentStatus.CARRIER,
    PaymentStatus.DEBT,
  };

  /// Đơn đã đóng hàng nhưng chưa cho đi.
  /// `ASSIGNED`/`LOADING` là tàn dư luồng chuyến xe cũ — vẫn cho xuất phát.
  static const _waitingDepart = {
    DeliveryStatus.WAITING_ASSIGNMENT,
    DeliveryStatus.ASSIGNED,
    DeliveryStatus.LOADING,
    DeliveryStatus.RESCHEDULED,
  };

  static const _delivering = {
    DeliveryStatus.ON_THE_WAY,
    DeliveryStatus.ARRIVED,
  };

  static const _settled = {
    DeliveryStatus.DELIVERED,
    DeliveryStatus.FAILED,
    DeliveryStatus.RETURNED,
  };

  // ---------- Sequence counters ----------
  Future<int> _nextSeq(String kind, DateTime day) async {
    final key = '${kind}_${DateFormat('yyMMdd').format(day)}';
    final ref = _db.collection('counters').doc(key);
    return _db.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final next = ((snap.data()?['seq'] ?? 0) as int) + 1;
      tx.set(ref, {'seq': next});
      return next;
    });
  }

  // ---------- Create order (spec §7) ----------
  Future<Order> createOrder(
    Order draft, {
    required String actorId,
    required String actorName,
  }) async {
    final now = draft.createdAt;
    final seq = await _nextSeq('order', now);
    final code = orderCode(now, seq);
    final ref = _orders.doc();

    // Initial payment status from prepaid.
    PaymentStatus ps;
    if (_userSetPayStatus.contains(draft.paymentStatus)) {
      ps = draft.paymentStatus;
    } else if (draft.prepaid <= 0) {
      ps = PaymentStatus.UNPAID;
    } else if (draft.prepaid >= draft.total) {
      ps = PaymentStatus.PAID;
    } else {
      ps = PaymentStatus.PARTIAL;
    }

    final order = Order(
      id: ref.id,
      code: code,
      createdAt: now,
      customerId: draft.customerId,
      customerName: draft.customerName,
      customerPhone: draft.customerPhone,
      deliveryAddress: draft.deliveryAddress,
      deliveryReceiver: draft.deliveryReceiver,
      deliveryPhone: draft.deliveryPhone,
      deliveryMapUrl: draft.deliveryMapUrl,
      deliveryCarrierName: draft.deliveryCarrierName,
      deliveryCarrierPhone: draft.deliveryCarrierPhone,
      deliveryAddressNote: draft.deliveryAddressNote,
      items: draft.items,
      shippingFee: draft.shippingFee,
      discount: draft.discount,
      prepaid: draft.prepaid,
      paidAmount: draft.prepaid,
      paymentStatus: ps,
      plannedDepartAt: draft.plannedDepartAt,
      note: draft.note,
      deliveryNote: draft.deliveryNote,
      timeline: [
        TimelineEvent(
          at: now,
          title: 'Tạo đơn',
          actorId: actorId,
          actorName: actorName,
        ),
      ],
    );

    final custRef = _customers.doc(order.customerId);
    await _db.runTransaction((tx) async {
      tx.set(ref, order.toMap());
      tx.set(custRef, {
        'orderCount': FieldValue.increment(1),
        'totalPurchased': FieldValue.increment(order.total),
        'totalPaid': FieldValue.increment(order.prepaid),
        'debt': FieldValue.increment(order.total - order.prepaid),
      }, SetOptions(merge: true));
    });

    await _notify(
      title: 'Đơn mới ${order.code}',
      body: order.items.isNotEmpty ? order.items.first.reportLabel : '',
      refType: NotifRefType.order,
      refId: ref.id,
      roles: {UserRole.checker},
      icon: 'new',
    );
    await _audit(
      action: 'create_order',
      entityType: 'order',
      entityId: ref.id,
      actorId: actorId,
      actorName: actorName,
      after: {
        'code': order.code,
        'total': order.total,
        'prepaid': order.prepaid,
        'paymentStatus': ps.name,
      },
      note: '${order.customerName} · ${money(order.total)}',
    );
    return order;
  }

  /// Sửa đơn **chưa xuất phát**: thêm/bớt mặt hàng, đổi số lượng, đổi giá,
  /// phí giao, giảm giá, ghi chú, giờ xuất phát dự kiến.
  ///
  /// KHÔNG đụng `prepaid`/`paidAmount` — tiền đã thu là bất biến (xem quy ước
  /// payment). Chỉ **tổng đơn** đổi, nên phải chỉnh lại `remaining`,
  /// `paymentStatus` và **công nợ khách** theo đúng phần chênh, hết.
  ///
  /// Chạy trong transaction và đọc lại đơn từ Firestore trước khi ghi: hai
  /// người cùng sửa, hoặc kho vừa đóng hàng xong trong lúc màn sửa đang mở,
  /// thì phải chặn chứ không ghi đè bằng dữ liệu cũ trên máy.
  Future<void> editOrder({
    required Order order,
    required List<OrderItem> items,
    required int shippingFee,
    required int discount,
    required String note,
    required String deliveryNote,
    DateTime? plannedDepartAt,
    required String actorId,
    required String actorName,
  }) async {
    if (items.isEmpty) throw Exception('Đơn phải có ít nhất một mặt hàng.');

    final orderRef = _orders.doc(order.id);
    final custRef = _customers.doc(order.customerId);
    var summary = '';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      final cur = Order.fromMap(snap.id, snap.data()!);
      if (cur.orderStatus == OrderStatus.CANCELLED) {
        throw Exception('Đơn đã hủy nên không sửa được.');
      }
      if (!_waitingDepart.contains(cur.deliveryStatus)) {
        throw Exception(
          'Đơn đã xuất phát nên không sửa được nữa — hàng đang trên đường.',
        );
      }

      final subtotal = items.fold<int>(0, (s, i) => s + i.lineTotal);
      final total = subtotal + shippingFee - discount;
      final paid = cur.paidAmount;

      // Công nợ khách = tổng phần còn phải thu của từng đơn, nên chỉ dịch đúng
      // phần chênh. Kẹp 0 như `cancelOrder` để khách trả dư không làm nợ âm.
      final oldOutstanding = cur.total - paid > 0 ? cur.total - paid : 0;
      final newOutstanding = total - paid > 0 ? total - paid : 0;

      var ps = cur.paymentStatus;
      // COD / Thu qua nhà xe / Công nợ / Đã hoàn tiền là trạng thái người dùng
      // tự chốt (hoặc do hủy đơn) — đừng tự đổi. Còn lại suy ra từ số đã thu so
      // với tổng MỚI.
      if (!_userSetPayStatus.contains(ps) && ps != PaymentStatus.REFUNDED) {
        ps = paid <= 0
            ? PaymentStatus.UNPAID
            : (paid >= total ? PaymentStatus.PAID : PaymentStatus.PARTIAL);
      }

      summary = '${cur.items.length} → ${items.length} mặt hàng · '
          '${money(cur.total)} → ${money(total)}';

      tx.update(orderRef, {
        'items': items.map((e) => e.toMap()).toList(),
        'shippingFee': shippingFee,
        'discount': discount,
        'subtotal': subtotal,
        'total': total,
        'remaining': total - paid,
        'paymentStatus': ps.name,
        'note': note,
        'deliveryNote': deliveryNote,
        'plannedDepartAt': plannedDepartAt?.millisecondsSinceEpoch,
        'timeline': FieldValue.arrayUnion([
          TimelineEvent(
            at: DateTime.now(),
            title: 'Sửa đơn',
            note: summary,
            actorId: actorId,
            actorName: actorName,
          ).toMap(),
        ]),
      });

      tx.set(custRef, {
        'totalPurchased': FieldValue.increment(total - cur.total),
        'debt': FieldValue.increment(newOutstanding - oldOutstanding),
      }, SetOptions(merge: true));
    });

    await _audit(
      action: 'edit_order',
      entityType: 'order',
      entityId: order.id,
      actorId: actorId,
      actorName: actorName,
      before: {'items': order.items.length, 'total': order.total},
      after: {
        'items': items.length,
        'total': items.fold<int>(0, (s, i) => s + i.lineTotal) +
            shippingFee -
            discount,
      },
      note: summary,
    );
    // Kho có thể đã soạn xong theo danh sách cũ → phải biết đơn vừa đổi.
    await _notify(
      title: 'Đơn ${order.code} vừa được sửa',
      body: summary,
      refType: NotifRefType.order,
      refId: order.id,
      roles: {UserRole.checker},
      icon: 'alert',
    );
  }

  Future<void> _appendTimeline(String orderId, TimelineEvent e) async {
    await _orders.doc(orderId).update({
      'timeline': FieldValue.arrayUnion([e.toMap()]),
    });
  }

  // ---------- Kho: ĐÓNG HÀNG, một bước duy nhất ----------
  //
  // Luồng kho gọn còn: đơn tạo xong (WAITING) → bấm **Đóng hàng** (PACKED) →
  // **Xuất phát**. KHÔNG còn PREPARING/PREPARED/PACKING (3 trạng thái đó thành
  // legacy, chỉ đọc cho đơn cũ) và KHÔNG còn cấp mã kiện `KIyyMMdd-NNN` hay
  // nhập khối lượng lúc đóng — `packageCode`/`weightKg`/`weightUnit` cũng thành
  // legacy, không ghi mới nữa. Đơn cũ đang kẹt ở trạng thái giữa vẫn bấm được
  // nút này để đi tiếp.
  Future<void> markPacked(Order o, String actorId, String actorName) async {
    // Chốt ở tầng Db chứ không chỉ ở UI: 2 người mở cùng một đơn thì trên máy
    // ai cũng còn thấy nút. Bấm lại đơn đã đóng thì bỏ qua, không sinh timeline
    // rác (cùng quy tắc với `departOrder`).
    if (o.warehouseStatus == WarehouseStatus.PACKED) return;
    if (o.orderStatus == OrderStatus.CANCELLED) {
      throw Exception('Đơn đã hủy.');
    }
    await _orders.doc(o.id).update({
      'warehouseStatus': WarehouseStatus.PACKED.name,
      'orderStatus': OrderStatus.PROCESSING.name,
    });
    await _appendTimeline(
      o.id,
      TimelineEvent(
        at: DateTime.now(),
        title: 'Đóng hàng xong',
        actorId: actorId,
        actorName: actorName,
      ),
    );
    await _audit(
      action: 'pack_order',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: {'warehouseStatus': o.warehouseStatus.name},
      after: {'warehouseStatus': WarehouseStatus.PACKED.name},
    );
    await _notify(
      title: 'Đơn ${o.code} chờ xuất phát',
      body: 'Kho đã đóng hàng xong',
      refType: NotifRefType.order,
      refId: o.id,
      roles: {UserRole.owner},
      icon: 'truck',
    );
  }

  // ---------- Payments (spec §12) ----------
  Future<void> recordPayment({
    required Order order,
    required int amount,
    required PaymentMethod method,
    required String actorId,
    required String actorName,
    String note = '',
  }) async {
    if (amount <= 0) return;
    final payRef = _payments.doc();
    final orderRef = _orders.doc(order.id);
    final custRef = _customers.doc(order.customerId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      final current = Order.fromMap(snap.id, snap.data()!);
      final newPaid = current.paidAmount + amount;
      final remaining = current.total - newPaid;
      final ps = remaining <= 0 ? PaymentStatus.PAID : PaymentStatus.PARTIAL;

      final payment = Payment(
        id: payRef.id,
        orderId: order.id,
        orderCode: current.code,
        customerId: current.customerId,
        customerName: current.customerName,
        amount: amount,
        method: method,
        at: DateTime.now(),
        actorId: actorId,
        actorName: actorName,
        note: note,
      );
      tx.set(payRef, payment.toMap());
      tx.update(orderRef, {
        'paidAmount': newPaid,
        'remaining': remaining,
        'paymentStatus': ps.name,
        'timeline': FieldValue.arrayUnion([
          TimelineEvent(
            at: payment.at,
            title: 'Thu ${money(amount)}',
            note: note,
            actorId: actorId,
            actorName: actorName,
          ).toMap(),
        ]),
      });
      tx.set(custRef, {
        'totalPaid': FieldValue.increment(amount),
        'debt': FieldValue.increment(-amount),
      }, SetOptions(merge: true));
    });

    await _audit(
      action: 'record_payment',
      entityType: 'payment',
      entityId: payRef.id,
      actorId: actorId,
      actorName: actorName,
      after: {
        'orderId': order.id,
        'orderCode': order.code,
        'amount': amount,
        'method': method.name,
      },
      note: '${order.customerName} · ${money(amount)}',
    );

    // Notify accountant on remaining debt.
    final remaining = order.total - (order.paidAmount + amount);
    if (remaining > 0) {
      await _notify(
        title: 'Công nợ mới ${money(remaining)}',
        body: '${order.customerName} còn thiếu tại đơn ${order.code}',
        refType: NotifRefType.debt,
        refId: order.customerId,
        roles: {UserRole.owner},
        icon: 'debt',
      );
    }
  }

  /// Thu công nợ của khách, phân bổ vào nhiều đơn còn nợ (spec §12.4).
  /// [allocations] = {orderId: amount}. Nếu null → phân bổ FIFO đơn cũ nhất trước.
  /// Mỗi đơn được phân bổ tạo một payment độc lập (không sửa payment cũ).
  Future<void> collectCustomerDebt({
    required String customerId,
    required int amount,
    required PaymentMethod method,
    required String actorId,
    required String actorName,
    Map<String, int>? allocations,
    String note = '',
  }) async {
    if (amount <= 0) return;
    final snap = await _orders.where('customerId', isEqualTo: customerId).get();
    final debtOrders =
        snap.docs
            .map((d) => Order.fromMap(d.id, d.data()))
            .where(
              (o) => o.remaining > 0 && o.orderStatus != OrderStatus.CANCELLED,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final plan = <String, int>{};
    if (allocations != null) {
      allocations.forEach((k, v) {
        if (v > 0) plan[k] = v;
      });
    } else {
      var left = amount;
      for (final o in debtOrders) {
        if (left <= 0) break;
        final take = left < o.remaining ? left : o.remaining;
        plan[o.id] = take;
        left -= take;
      }
    }

    for (final entry in plan.entries) {
      final match = debtOrders.where((e) => e.id == entry.key);
      if (match.isEmpty) continue;
      await recordPayment(
        order: match.first,
        amount: entry.value,
        method: method,
        actorId: actorId,
        actorName: actorName,
        note: note.isEmpty ? 'Thu công nợ' : note,
      );
    }
  }

  Stream<List<Payment>> paymentsByOrder(String orderId) => _payments
      .where('orderId', isEqualTo: orderId)
      .snapshots()
      .map(
        (s) =>
            (s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.at.compareTo(b.at))),
      );

  Stream<List<Payment>> paymentsAll() => _payments.snapshots().map(
    (s) => s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList(),
  );

  Stream<List<Payment>> paymentsByCustomer(String customerId) => _payments
      .where('customerId', isEqualTo: customerId)
      .snapshots()
      .map(
        (s) =>
            (s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => b.at.compareTo(a.at))),
      );

  // ---------- Price history (spec §5.3) ----------
  Future<void> logPriceChange({
    required String productId,
    required String productName,
    required String variantId,
    required String variantName,
    required String packagingId,
    required String packagingName,
    required int oldPrice,
    required int newPrice,
    String actorId = '',
    String actorName = '',
  }) async {
    if (oldPrice == newPrice) return;
    await _priceHistory.add({
      'productId': productId,
      'productName': productName,
      'variantId': variantId,
      'variantName': variantName,
      'packagingId': packagingId,
      'packagingName': packagingName,
      'oldPrice': oldPrice,
      'newPrice': newPrice,
      'actorId': actorId,
      'actorName': actorName,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    await _audit(
      action: 'price_change',
      entityType: 'packaging',
      entityId: packagingId,
      actorId: actorId,
      actorName: actorName,
      before: {'price': oldPrice},
      after: {'price': newPrice},
      note: '$productName $packagingName',
    );
  }

  Stream<List<PriceHistory>> priceHistory(String productId) => _priceHistory
      .where('productId', isEqualTo: productId)
      .snapshots()
      .map(
        (s) =>
            s.docs.map((d) => PriceHistory.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => b.at.compareTo(a.at)),
      );

  /// Đổi **giờ dự kiến xuất phát** của đơn (đặt lại hoặc xoá bằng `null`).
  /// Chỉ đổi được khi đơn CHƯA đi — đã lên đường rồi thì giờ dự kiến vô nghĩa
  /// và sửa nó chỉ làm hàng đợi nhảy lung tung.
  Future<void> setPlannedDepart(
    Order o,
    DateTime? at, {
    required String actorId,
    required String actorName,
  }) async {
    if (!_waitingDepart.contains(o.deliveryStatus)) {
      throw Exception('Đơn đã xuất phát nên không đổi được giờ dự kiến.');
    }
    await _orders.doc(o.id).update({
      'plannedDepartAt': at?.millisecondsSinceEpoch,
    });
    await _appendTimeline(
      o.id,
      TimelineEvent(
        at: DateTime.now(),
        title: at == null
            ? 'Bỏ giờ xuất phát dự kiến'
            : 'Đặt giờ xuất phát dự kiến: ${fmtDateTime(at)}',
        actorId: actorId,
        actorName: actorName,
      ),
    );
    await _audit(
      action: 'set_planned_depart',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: {'plannedDepartAt': o.plannedDepartAt?.millisecondsSinceEpoch},
      after: {'plannedDepartAt': at?.millisecondsSinceEpoch},
    );
  }

  // ---------- Cho đơn xuất phát (§11.2 rút gọn) ----------
  /// Đơn đã đóng hàng → **Đang giao**. Không còn chuyến/tài xế: kho đóng xong
  /// là bấm đi luôn. Chạy lại trên đơn đã đi thì bỏ qua, nên bấm nhầm 2 lần
  /// không sinh timeline rác.
  Future<void> departOrder(Order o, String actorId, String actorName) async {
    if (!_waitingDepart.contains(o.deliveryStatus)) return;
    if (o.warehouseStatus != WarehouseStatus.PACKED) {
      throw Exception('Đơn chưa đóng hàng xong nên chưa xuất phát được.');
    }
    if (o.orderStatus == OrderStatus.CANCELLED) {
      throw Exception('Đơn đã hủy.');
    }
    final now = DateTime.now();
    await _orders.doc(o.id).update({
      'deliveryStatus': DeliveryStatus.ON_THE_WAY.name,
      'orderStatus': OrderStatus.PROCESSING.name,
      'timeline': FieldValue.arrayUnion([
        TimelineEvent(
          at: now,
          title: 'Xuất phát giao hàng',
          actorId: actorId,
          actorName: actorName,
        ).toMap(),
      ]),
    });
    await _audit(
      action: 'depart_order',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: {'deliveryStatus': o.deliveryStatus.name},
      after: {'deliveryStatus': DeliveryStatus.ON_THE_WAY.name},
    );
    await _notify(
      title: 'Đơn ${o.code} đã xuất phát',
      body: '${o.customerName} · ${o.deliveryAddress}',
      refType: NotifRefType.order,
      refId: o.id,
      roles: {UserRole.owner},
      icon: 'depart',
    );
  }

  /// Cho **nhiều đơn** đi cùng lúc (nút "Xuất phát tất cả").
  ///
  /// Cập nhật đơn bằng một batch để không nửa vời khi rớt mạng giữa chừng;
  /// audit + 1 thông báo gộp ghi sau, hỏng thì cũng không kẹt trạng thái đơn.
  /// Trả về số đơn thực sự được cho đi.
  Future<int> departOrders(
    List<Order> orders,
    String actorId,
    String actorName,
  ) async {
    final go = orders
        .where(
          (o) =>
              o.warehouseStatus == WarehouseStatus.PACKED &&
              o.orderStatus != OrderStatus.CANCELLED &&
              _waitingDepart.contains(o.deliveryStatus),
        )
        .toList();
    if (go.isEmpty) return 0;

    final now = DateTime.now();
    final event = TimelineEvent(
      at: now,
      title: 'Xuất phát giao hàng',
      actorId: actorId,
      actorName: actorName,
    ).toMap();
    final batch = _db.batch();
    for (final o in go) {
      batch.update(_orders.doc(o.id), {
        'deliveryStatus': DeliveryStatus.ON_THE_WAY.name,
        'orderStatus': OrderStatus.PROCESSING.name,
        'timeline': FieldValue.arrayUnion([event]),
      });
    }
    await batch.commit();

    for (final o in go) {
      await _audit(
        action: 'depart_order',
        entityType: 'order',
        entityId: o.id,
        actorId: actorId,
        actorName: actorName,
        before: {'deliveryStatus': o.deliveryStatus.name},
        after: {'deliveryStatus': DeliveryStatus.ON_THE_WAY.name},
        note: 'Xuất phát hàng loạt',
      );
    }
    await _notify(
      title: '${go.length} đơn đã xuất phát',
      body: go.map((o) => o.code).join(', '),
      refType: NotifRefType.order,
      refId: go.first.id,
      roles: {UserRole.owner},
      icon: 'depart',
    );
    return go.length;
  }

  // ---------- Đối soát cuối ngày (§11.3-11.5) ----------
  /// Giao thành công + thu tiền trong một bước. Chỉ Chủ gọi (xem `Perm`).
  Future<void> markDelivered({
    required Order order,
    required int collected,
    required PaymentMethod method,
    required String actorId,
    required String actorName,
    String note = '',
    // Khách hẹn trả sau — giao thành công nhưng KHÔNG thu gì lúc này. Chốt
    // luôn `paymentStatus: DEBT` (một trong `_userSetPayStatus`, xem đó) để
    // đơn hiện đúng chip "Công nợ" thay vì rơi về mặc định lúc tạo đơn, và
    // lọt vào màn Cài đặt › Công nợ (lọc theo `remaining > 0` trên đơn đã
    // giao). Thu tiền sau vẫn qua nút "Thu tiền" thường (`recordPayment`) —
    // nó tự suy `paymentStatus` lại thành PARTIAL/PAID theo số thực thu.
    bool markAsDebt = false,
  }) async {
    if (collected > 0) {
      await recordPayment(
        order: order,
        amount: collected,
        method: method,
        actorId: actorId,
        actorName: actorName,
        note: note,
      );
    }
    await _orders.doc(order.id).update({
      'deliveryStatus': DeliveryStatus.DELIVERED.name,
      'orderStatus': OrderStatus.COMPLETED.name,
      if (markAsDebt) 'paymentStatus': PaymentStatus.DEBT.name,
    });
    await _appendTimeline(
      order.id,
      TimelineEvent(
        at: DateTime.now(),
        title: 'Giao thành công',
        note: markAsDebt
            ? 'Khách hẹn trả sau · còn nợ ${money(order.remaining)}'
            : '',
        actorName: actorName,
      ),
    );
    await _audit(
      action: 'deliver_order',
      entityType: 'order',
      entityId: order.id,
      actorId: actorId,
      actorName: actorName,
      after: {
        'deliveryStatus': DeliveryStatus.DELIVERED.name,
        'collected': collected,
        if (markAsDebt) 'paymentStatus': PaymentStatus.DEBT.name,
      },
    );
    await _notify(
      title: 'Đơn ${order.code} giao thành công',
      body: markAsDebt
          ? '${order.customerName} · còn nợ ${money(order.remaining)}'
          : order.customerName,
      refType: NotifRefType.order,
      refId: order.id,
      roles: {UserRole.owner, UserRole.checker},
      icon: 'success',
    );
  }

  Future<void> markDeliveryFailed({
    required Order order,
    required DeliveryStatus status, // FAILED / RESCHEDULED / RETURNED
    required String reason,
    required String actorId,
    required String actorName,
    DateTime? rescheduleAt,
  }) async {
    await _orders.doc(order.id).update({'deliveryStatus': status.name});
    await _appendTimeline(
      order.id,
      TimelineEvent(
        at: DateTime.now(),
        title: deliveryStatusUi(status).label,
        note: reason,
        actorId: actorId,
        actorName: actorName,
      ),
    );
    await _audit(
      action: 'delivery_failed',
      entityType: 'order',
      entityId: order.id,
      actorId: actorId,
      actorName: actorName,
      before: {'deliveryStatus': order.deliveryStatus.name},
      after: {'deliveryStatus': status.name},
      note: reason,
    );
    await _notify(
      title: 'Đơn ${order.code} ${deliveryStatusUi(status).label}',
      body: reason,
      refType: NotifRefType.order,
      refId: order.id,
      roles: {UserRole.owner},
      icon: 'fail',
    );
  }

  // ---------- Cancel order (spec §13, §22) ----------
  /// Hủy đơn: đối trừ công nợ khách, KHÔNG xóa payment cũ. Nếu đã thu tiền thì
  /// ghi một payment hoàn tiền (âm) để giữ dấu vết và trả totalPaid về đúng.
  Future<void> cancelOrder(
    Order o,
    String reason,
    String actorName, {
    String actorId = '',
  }) async {
    final orderRef = _orders.doc(o.id);
    final custRef = _customers.doc(o.customerId);
    var refunded = 0;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      final cur = Order.fromMap(snap.id, snap.data()!);
      if (cur.orderStatus == OrderStatus.CANCELLED) return;
      final outstanding = cur.total - cur.paidAmount; // còn phải thu
      refunded = cur.paidAmount;
      final ps = cur.paidAmount > 0
          ? PaymentStatus.REFUNDED
          : cur.paymentStatus;

      tx.update(orderRef, {
        'orderStatus': OrderStatus.CANCELLED.name,
        'cancelReason': reason,
        'paymentStatus': ps.name,
        'timeline': FieldValue.arrayUnion([
          TimelineEvent(
            at: DateTime.now(),
            title: 'Hủy đơn',
            note: reason,
            actorId: actorId,
            actorName: actorName,
          ).toMap(),
        ]),
      });

      // Gỡ toàn bộ đóng góp của đơn khỏi tổng hợp khách.
      tx.set(custRef, {
        'totalPurchased': FieldValue.increment(-cur.total),
        'totalPaid': FieldValue.increment(-cur.paidAmount),
        'debt': FieldValue.increment(-(outstanding > 0 ? outstanding : 0)),
      }, SetOptions(merge: true));

      // Ghi payment hoàn tiền (âm) — không đụng payment gốc.
      if (cur.paidAmount > 0) {
        final refRef = _payments.doc();
        tx.set(
          refRef,
          Payment(
            id: refRef.id,
            orderId: cur.id,
            orderCode: cur.code,
            customerId: cur.customerId,
            customerName: cur.customerName,
            amount: -cur.paidAmount,
            method: PaymentMethod.cash,
            at: DateTime.now(),
            actorId: actorId,
            actorName: actorName,
            note: 'Hoàn tiền do hủy đơn: $reason',
          ).toMap(),
        );
      }
    });

    await _audit(
      action: 'cancel_order',
      entityType: 'order',
      entityId: o.id,
      actorId: actorId,
      actorName: actorName,
      before: {'orderStatus': o.orderStatus.name, 'paidAmount': o.paidAmount},
      after: {'orderStatus': OrderStatus.CANCELLED.name, 'refunded': refunded},
      note: reason,
    );

    await _notify(
      title: 'Đơn ${o.code} đã hủy',
      body: reason,
      refType: NotifRefType.order,
      refId: o.id,
      roles: {UserRole.owner, UserRole.checker},
      icon: 'fail',
    );
  }

  // ---------- Notifications ----------
  Future<void> _notify({
    required String title,
    required String body,
    required NotifRefType refType,
    required String refId,
    required Set<UserRole> roles,
    String icon = 'bell',
  }) async {
    final n = AppNotification(
      id: '',
      title: title,
      body: body,
      refType: refType,
      refId: refId,
      targetRoles: roles,
      at: DateTime.now(),
      icon: icon,
    );
    await _notifs.add(n.toMap());
  }

  Stream<List<AppNotification>> notifications(UserRole role) => _notifs
      .orderBy('at', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => AppNotification.fromMap(d.id, d.data()))
            .where(
              (n) => n.targetRoles.contains(role) || role == UserRole.owner,
            )
            .toList(),
      );

  Future<void> markNotifRead(String id) =>
      _notifs.doc(id).update({'read': true});

  Future<void> markAllNotifsRead(UserRole role) async {
    final snap = await _notifs.where('read', isEqualTo: false).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
