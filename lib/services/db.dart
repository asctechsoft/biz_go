import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:intl/intl.dart';

import '../core/enums.dart';
import '../core/formatters.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/audit_log.dart';
import '../models/customer.dart';
import '../models/fleet.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../models/product.dart';

/// Single Firestore gateway. Business actions (create order, record payment,
/// status transitions) run in transactions and always append timeline +
/// notifications, per spec §20.
class Db {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('categories');
  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('products');
  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('customers');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection('payments');
  CollectionReference<Map<String, dynamic>> get _vehicles =>
      _db.collection('vehicles');
  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('drivers');
  CollectionReference<Map<String, dynamic>> get _trips => _db.collection('trips');
  CollectionReference<Map<String, dynamic>> get _notifs =>
      _db.collection('notifications');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ---------- Users (quản lý người dùng) ----------
  Stream<List<AppUser>> users() => _users
      .snapshots()
      .map((s) => s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.role.index.compareTo(b.role.index)));

  Stream<List<AppUser>> usersByRole(UserRole role) => _users
      .where('role', isEqualTo: role.name)
      .snapshots()
      .map((s) => s.docs
          .map((d) => AppUser.fromMap(d.id, d.data()))
          .where((u) => u.active)
          .toList());

  Future<void> setUserActive(String uid, bool active) =>
      _users.doc(uid).update({'active': active});

  /// Cập nhật hồ sơ user (tên / vai trò). Không đổi SĐT vì gắn với đăng nhập.
  Future<void> updateUser(String uid, {String? name, UserRole? role}) {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (role != null) data['role'] = role.name;
    if (data.isEmpty) return Future.value();
    return _users.doc(uid).update(data);
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

  // ---------- Categories ----------
  Stream<List<ProductCategory>> categories() => _categories
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => ProductCategory.fromMap(d.id, d.data())).toList());

  Future<String> upsertCategory(ProductCategory c) async {
    if (c.id.isEmpty) {
      final ref = await _categories.add(c.toMap());
      return ref.id;
    }
    await _categories.doc(c.id).set(c.toMap());
    return c.id;
  }

  Future<void> deleteCategory(String id) => _categories.doc(id).delete();

  // ---------- Products ----------
  Stream<List<Product>> products() => _products
      .orderBy('nameLower')
      .snapshots()
      .map((s) => s.docs.map((d) => Product.fromMap(d.id, d.data())).toList());

  Stream<Product> product(String id) =>
      _products.doc(id).snapshots().map((d) => Product.fromMap(d.id, d.data()!));

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

  // ---------- Customers ----------
  Stream<List<Customer>> customers() => _customers
      .orderBy('nameLower')
      .snapshots()
      .map((s) => s.docs.map((d) => Customer.fromMap(d.id, d.data())).toList());

  Stream<Customer> customer(String id) =>
      _customers.doc(id).snapshots().map((d) => Customer.fromMap(d.id, d.data()!));

  Future<String> upsertCustomer(Customer c) async {
    if (c.id.isEmpty) {
      final ref = await _customers.add(c.toMap());
      return ref.id;
    }
    // Keep aggregate fields untouched on edit by merging.
    await _customers.doc(c.id).set(c.toMap(), SetOptions(merge: true));
    return c.id;
  }

  // ---------- Orders (queries) ----------
  Stream<List<Order>> orders() => _orders
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Order.fromMap(d.id, d.data())).toList());

  Stream<Order> order(String id) =>
      _orders.doc(id).snapshots().map((d) => Order.fromMap(d.id, d.data()!));

  Stream<List<Order>> ordersByCustomer(String customerId) => _orders
      .where('customerId', isEqualTo: customerId)
      .snapshots()
      .map((s) => (s.docs.map((d) => Order.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt))));

  Stream<List<Order>> ordersByTrip(String tripId) => _orders
      .where('tripId', isEqualTo: tripId)
      .snapshots()
      .map((s) => (s.docs.map((d) => Order.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence))));

  /// Orders that are PACKED and not yet on a trip — dispatch pool.
  Stream<List<Order>> ordersReadyForTrip() => _orders
      .where('warehouseStatus', isEqualTo: WarehouseStatus.PACKED.name)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Order.fromMap(d.id, d.data()))
          .where((o) => o.tripId == null && o.orderStatus != OrderStatus.CANCELLED)
          .toList());

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
  Future<Order> createOrder(Order draft,
      {required String actorId, required String actorName}) async {
    final now = draft.createdAt;
    final seq = await _nextSeq('order', now);
    final code = orderCode(now, seq);
    final ref = _orders.doc();

    // Initial payment status from prepaid.
    PaymentStatus ps;
    if (draft.paymentStatus == PaymentStatus.COD ||
        draft.paymentStatus == PaymentStatus.DEBT) {
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
      deliveryLabel: draft.deliveryLabel,
      deliveryAddress: draft.deliveryAddress,
      deliveryReceiver: draft.deliveryReceiver,
      deliveryPhone: draft.deliveryPhone,
      items: draft.items,
      shippingFee: draft.shippingFee,
      discount: draft.discount,
      prepaid: draft.prepaid,
      paidAmount: draft.prepaid,
      paymentStatus: ps,
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
      body: order.items.isNotEmpty ? order.items.first.displayName : '',
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

  Future<void> _appendTimeline(String orderId, TimelineEvent e) async {
    await _orders.doc(orderId).update({
      'timeline': FieldValue.arrayUnion([e.toMap()]),
    });
  }

  // ---------- Warehouse transitions (spec §9) ----------
  Future<void> startPreparing(Order o, String actorId, String actorName) =>
      _warehouseStep(o, WarehouseStatus.PREPARING, OrderStatus.PROCESSING,
          'Kho bắt đầu chuẩn bị', actorId, actorName);

  Future<void> markPrepared(Order o, String actorId, String actorName) async {
    await _warehouseStep(o, WarehouseStatus.PREPARED, OrderStatus.PROCESSING,
        'Kho đã chuẩn bị xong', actorId, actorName);
    await _notify(
        title: 'Đơn ${o.code} chờ đóng hàng',
        body: 'Kho đã chuẩn bị xong',
        refType: NotifRefType.order,
        refId: o.id,
        roles: {UserRole.checker},
        icon: 'box');
  }

  /// §8 intermediate: packer starts packing (PREPARED → PACKING).
  Future<void> startPacking(Order o, String actorId, String actorName) =>
      _warehouseStep(o, WarehouseStatus.PACKING, OrderStatus.PROCESSING,
          'Bắt đầu đóng hàng', actorId, actorName);

  Future<void> markPacked(Order o, String actorId, String actorName,
      {int? packageCount, double? weightKg, String note = ''}) async {
    await _orders.doc(o.id).update({
      'warehouseStatus': WarehouseStatus.PACKED.name,
      'packageCount': packageCount,
      'weightKg': weightKg,
    });
    await _appendTimeline(
        o.id,
        TimelineEvent(
            at: DateTime.now(),
            title: 'Đóng hàng xong',
            note: note,
            actorId: actorId,
            actorName: actorName));
    await _audit(
        action: 'pack_order',
        entityType: 'order',
        entityId: o.id,
        actorId: actorId,
        actorName: actorName,
        before: {'warehouseStatus': o.warehouseStatus.name},
        after: {
          'warehouseStatus': WarehouseStatus.PACKED.name,
          'packageCount': packageCount,
          'weightKg': weightKg,
        });
    await _notify(
        title: 'Đơn ${o.code} chờ xếp chuyến',
        body: 'Đã đóng hàng ${packageCount ?? ''} kiện',
        refType: NotifRefType.order,
        refId: o.id,
        roles: {UserRole.owner},
        icon: 'truck');
  }

  Future<void> _warehouseStep(Order o, WarehouseStatus ws, OrderStatus os,
      String title, String actorId, String actorName) async {
    await _orders.doc(o.id).update({
      'warehouseStatus': ws.name,
      'orderStatus': os.name,
    });
    await _appendTimeline(
        o.id,
        TimelineEvent(
            at: DateTime.now(),
            title: title,
            actorId: actorId,
            actorName: actorName));
    await _audit(
        action: 'warehouse_step',
        entityType: 'order',
        entityId: o.id,
        actorId: actorId,
        actorName: actorName,
        before: {'warehouseStatus': o.warehouseStatus.name},
        after: {'warehouseStatus': ws.name},
        note: title);
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
          ).toMap()
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
        note: '${order.customerName} · ${money(amount)}');

    // Notify accountant on remaining debt.
    final remaining = order.total - (order.paidAmount + amount);
    if (remaining > 0) {
      await _notify(
          title: 'Công nợ mới ${money(remaining)}',
          body: '${order.customerName} còn thiếu tại đơn ${order.code}',
          refType: NotifRefType.debt,
          refId: order.customerId,
          roles: {UserRole.owner},
          icon: 'debt');
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
    final snap =
        await _orders.where('customerId', isEqualTo: customerId).get();
    final debtOrders = snap.docs
        .map((d) => Order.fromMap(d.id, d.data()))
        .where((o) =>
            o.remaining > 0 && o.orderStatus != OrderStatus.CANCELLED)
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
      .map((s) => (s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => a.at.compareTo(b.at))));

  Stream<List<Payment>> paymentsAll() => _payments
      .snapshots()
      .map((s) => s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList());

  Stream<List<Payment>> paymentsByCustomer(String customerId) => _payments
      .where('customerId', isEqualTo: customerId)
      .snapshots()
      .map((s) => (s.docs.map((d) => Payment.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.at.compareTo(a.at))));

  // ---------- Vehicles / Drivers ----------
  Stream<List<Vehicle>> vehicles() => _vehicles
      .snapshots()
      .map((s) => s.docs.map((d) => Vehicle.fromMap(d.id, d.data())).toList());

  Future<String> upsertVehicle(Vehicle v) async {
    if (v.id.isEmpty) return (await _vehicles.add(v.toMap())).id;
    await _vehicles.doc(v.id).set(v.toMap());
    return v.id;
  }

  Future<void> deleteVehicle(String id) => _vehicles.doc(id).delete();

  Stream<List<Driver>> drivers() => _drivers
      .snapshots()
      .map((s) => s.docs.map((d) => Driver.fromMap(d.id, d.data())).toList());

  Future<String> upsertDriver(Driver d) async {
    if (d.id.isEmpty) return (await _drivers.add(d.toMap())).id;
    await _drivers.doc(d.id).set(d.toMap());
    return d.id;
  }

  Future<void> deleteDriver(String id) => _drivers.doc(id).delete();

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
        note: '$productName $packagingName');
  }

  Stream<List<PriceHistory>> priceHistory(String productId) => _priceHistory
      .where('productId', isEqualTo: productId)
      .snapshots()
      .map((s) => s.docs.map((d) => PriceHistory.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.at.compareTo(a.at)));

  // ---------- Trips (spec §10) ----------
  Stream<List<Trip>> trips() => _trips
      .orderBy('runDate', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Trip.fromMap(d.id, d.data())).toList());

  Stream<Trip> trip(String id) =>
      _trips.doc(id).snapshots().map((d) => Trip.fromMap(d.id, d.data()!));

  /// Chuyến của một tài xế (theo uid tài khoản) — app tài xế chỉ thấy chuyến mình.
  Stream<List<Trip>> tripsForDriver(String driverId) => _trips
      .where('driverId', isEqualTo: driverId)
      .snapshots()
      .map((s) => s.docs.map((d) => Trip.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.runDate.compareTo(a.runDate)));

  Future<Trip> createTrip({
    required DateTime runDate,
    required Vehicle vehicle,
    required Driver driver,
    DateTime? plannedDeparture,
    String note = '',
  }) async {
    final seq = await _nextSeq('trip', runDate);
    final ref = _trips.doc();
    final trip = Trip(
      id: ref.id,
      code: tripCode(runDate, seq),
      runDate: runDate,
      vehicleId: vehicle.id,
      vehiclePlate: vehicle.plate,
      driverId: driver.id,
      driverName: driver.name,
      driverPhone: driver.phone,
      status: TripStatus.READY,
      plannedDeparture: plannedDeparture,
      note: note,
    );
    await ref.set(trip.toMap());
    return trip;
  }

  /// Assign order to trip (spec §10.4 + §22: must be PACKED & not on another trip).
  Future<void> assignOrderToTrip(Order o, Trip t, int sequence) async {
    if (o.warehouseStatus != WarehouseStatus.PACKED) {
      throw Exception('Đơn chưa đóng hàng (PACKED) nên không thể xếp chuyến.');
    }
    if (o.tripId != null && o.tripId != t.id) {
      throw Exception('Đơn đã thuộc chuyến khác.');
    }
    // Chuyến đã xuất phát → đơn mới vào chuyến chuyển thẳng sang Đang giao,
    // nếu không sẽ kẹt ASSIGNED (không hiện nút giao, không xuất phát lại được).
    final departed = t.status == TripStatus.IN_PROGRESS;
    final now = DateTime.now();
    await _orders.doc(o.id).update({
      'tripId': t.id,
      'sequence': sequence,
      'deliveryStatus': (departed
              ? DeliveryStatus.ON_THE_WAY
              : DeliveryStatus.ASSIGNED)
          .name,
    });
    await _appendTimeline(
        o.id, TimelineEvent(at: now, title: 'Đã lên chuyến ${t.code}'));
    if (departed) {
      await _appendTimeline(o.id,
          TimelineEvent(at: now, title: 'Xe đang giao (chuyến đã xuất phát)'));
    }
    await _recountTrip(t.id);
    await _notify(
        title: 'Bạn có đơn trong chuyến ${t.code}',
        body: '${o.code} - ${o.customerName}',
        refType: NotifRefType.trip,
        refId: t.id,
        roles: {UserRole.shipper},
        icon: 'truck');
  }

  Future<void> removeOrderFromTrip(Order o) async {
    final tripId = o.tripId;
    await _orders.doc(o.id).update({
      'tripId': null,
      'sequence': 0,
      'deliveryStatus': DeliveryStatus.WAITING_ASSIGNMENT.name,
    });
    if (tripId != null) await _recountTrip(tripId);
  }

  Future<void> reorderTripSequences(String tripId, List<Order> ordered) async {
    final batch = _db.batch();
    for (var i = 0; i < ordered.length; i++) {
      batch.update(_orders.doc(ordered[i].id), {'sequence': i + 1});
    }
    await batch.commit();
  }

  Future<void> _recountTrip(String tripId) async {
    final snap = await _orders.where('tripId', isEqualTo: tripId).get();
    final orders = snap.docs.map((d) => Order.fromMap(d.id, d.data())).toList();
    final delivered =
        orders.where((o) => o.deliveryStatus == DeliveryStatus.DELIVERED).length;
    // Còn đơn nào đang chờ xử lý (chưa giao/hoàn) không?
    const pending = {
      DeliveryStatus.WAITING_ASSIGNMENT,
      DeliveryStatus.ASSIGNED,
      DeliveryStatus.LOADING,
      DeliveryStatus.ON_THE_WAY,
      DeliveryStatus.ARRIVED,
      DeliveryStatus.RESCHEDULED,
    };
    final anyPending = orders.any((o) => pending.contains(o.deliveryStatus));

    final data = <String, dynamic>{
      'orderCount': orders.length,
      'deliveredCount': delivered,
    };
    // Chuyến đã xuất phát + hết đơn chờ → tự hoàn thành chuyến.
    final tripDoc = await _trips.doc(tripId).get();
    final curStatus = tripDoc.data()?['status'];
    if (orders.isNotEmpty &&
        !anyPending &&
        curStatus == TripStatus.IN_PROGRESS.name) {
      data['status'] = TripStatus.COMPLETED.name;
    }
    await _trips.doc(tripId).update(data);
  }

  /// Xe xuất phát (§11.2) — hoặc "đẩy tiếp" đơn mới xếp vào chuyến đang chạy.
  /// Chỉ chuyển đơn CHƯA đi (ASSIGNED/WAITING/LOADING) sang ON_THE_WAY;
  /// KHÔNG đụng đơn đã giao/hoàn/hẹn lại. Chạy lại nhiều lần vẫn an toàn.
  Future<void> departTrip(Trip t, String actorId, String actorName) async {
    final now = DateTime.now();
    final wasInProgress = t.status == TripStatus.IN_PROGRESS;
    final tripData = <String, dynamic>{
      'status': TripStatus.IN_PROGRESS.name,
    };
    // Chỉ ghi giờ xuất phát ở lần đầu.
    if (!wasInProgress) {
      tripData['actualDeparture'] = now.millisecondsSinceEpoch;
    }
    await _trips.doc(t.id).update(tripData);

    const toDepart = {
      DeliveryStatus.WAITING_ASSIGNMENT,
      DeliveryStatus.ASSIGNED,
      DeliveryStatus.LOADING,
    };
    final snap = await _orders.where('tripId', isEqualTo: t.id).get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      final o = Order.fromMap(d.id, d.data());
      if (!toDepart.contains(o.deliveryStatus)) continue; // giữ nguyên đơn khác
      batch.update(d.reference, {
        'deliveryStatus': DeliveryStatus.ON_THE_WAY.name,
        'timeline': FieldValue.arrayUnion([
          TimelineEvent(at: now, title: 'Xe xuất phát', actorName: actorName)
              .toMap()
        ]),
      });
    }
    await batch.commit();
    await _notify(
        title: wasInProgress
            ? 'Chuyến ${t.code} có đơn mới đang giao'
            : 'Chuyến ${t.code} đã xuất phát',
        body: 'Tài xế ${t.driverName}',
        refType: NotifRefType.trip,
        refId: t.id,
        roles: {UserRole.owner},
        icon: 'depart');
  }

  // ---------- Delivery per order (spec §11.3-11.5) ----------
  Future<void> markArrived(Order o, String actorId, String actorName) async {
    await _orders.doc(o.id).update({
      'deliveryStatus': DeliveryStatus.ARRIVED.name,
    });
    await _appendTimeline(o.id,
        TimelineEvent(at: DateTime.now(), title: 'Đã tới điểm giao', actorName: actorName));
  }

  /// Successful delivery + collect money in one step.
  Future<void> markDelivered({
    required Order order,
    required int collected,
    required PaymentMethod method,
    required String actorId,
    required String actorName,
    String note = '',
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
    });
    await _appendTimeline(order.id,
        TimelineEvent(at: DateTime.now(), title: 'Giao thành công', actorName: actorName));
    if (order.tripId != null) await _recountTrip(order.tripId!);
    await _audit(
        action: 'deliver_order',
        entityType: 'order',
        entityId: order.id,
        actorId: actorId,
        actorName: actorName,
        after: {'deliveryStatus': DeliveryStatus.DELIVERED.name, 'collected': collected});
    await _notify(
        title: 'Đơn ${order.code} giao thành công',
        body: order.customerName,
        refType: NotifRefType.order,
        refId: order.id,
        roles: {UserRole.owner, UserRole.checker},
        icon: 'success');
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
            actorName: actorName));
    if (order.tripId != null) await _recountTrip(order.tripId!);
    await _notify(
        title: 'Đơn ${order.code} ${deliveryStatusUi(status).label}',
        body: reason,
        refType: NotifRefType.order,
        refId: order.id,
        roles: {UserRole.owner},
        icon: 'fail');
  }

  // ---------- Cancel order (spec §13, §22) ----------
  /// Hủy đơn: đối trừ công nợ khách, KHÔNG xóa payment cũ. Nếu đã thu tiền thì
  /// ghi một payment hoàn tiền (âm) để giữ dấu vết và trả totalPaid về đúng.
  Future<void> cancelOrder(Order o, String reason, String actorName,
      {String actorId = ''}) async {
    final orderRef = _orders.doc(o.id);
    final custRef = _customers.doc(o.customerId);
    var refunded = 0;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      final cur = Order.fromMap(snap.id, snap.data()!);
      if (cur.orderStatus == OrderStatus.CANCELLED) return;
      final outstanding = cur.total - cur.paidAmount; // còn phải thu
      refunded = cur.paidAmount;
      final ps =
          cur.paidAmount > 0 ? PaymentStatus.REFUNDED : cur.paymentStatus;

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
                  actorName: actorName)
              .toMap()
        ]),
      });

      // Gỡ toàn bộ đóng góp của đơn khỏi tổng hợp khách.
      tx.set(
          custRef,
          {
            'totalPurchased': FieldValue.increment(-cur.total),
            'totalPaid': FieldValue.increment(-cur.paidAmount),
            'debt': FieldValue.increment(-(outstanding > 0 ? outstanding : 0)),
          },
          SetOptions(merge: true));

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
            ).toMap());
      }
    });

    await _audit(
        action: 'cancel_order',
        entityType: 'order',
        entityId: o.id,
        actorId: actorId,
        actorName: actorName,
        before: {
          'orderStatus': o.orderStatus.name,
          'paidAmount': o.paidAmount
        },
        after: {'orderStatus': OrderStatus.CANCELLED.name, 'refunded': refunded},
        note: reason);

    await _notify(
        title: 'Đơn ${o.code} đã hủy',
        body: reason,
        refType: NotifRefType.order,
        refId: o.id,
        roles: {UserRole.owner, UserRole.checker},
        icon: 'fail');
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
      .map((s) => s.docs
          .map((d) => AppNotification.fromMap(d.id, d.data()))
          .where((n) => n.targetRoles.contains(role) || role == UserRole.owner)
          .toList());

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

  // ---------- Xóa toàn bộ dữ liệu nghiệp vụ (giữ tài khoản đăng nhập) ----------
  static const _clearableCollections = [
    'categories',
    'products',
    'customers',
    'orders',
    'payments',
    'vehicles',
    'drivers',
    'trips',
    'notifications',
    'price_history',
    'audit_logs',
    'counters',
    'meta', // gồm cờ seeded → cho phép seed lại
  ];

  Future<void> clearAllData() async {
    for (final name in _clearableCollections) {
      await _deleteCollection(name);
    }
  }

  Future<void> _deleteCollection(String name) async {
    while (true) {
      final snap = await _db.collection(name).limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
    }
  }
}
