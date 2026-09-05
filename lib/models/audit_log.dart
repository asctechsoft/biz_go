/// Audit trail entry (spec §2, §20): who did what, when, before/after.
class AuditLog {
  final String id;
  final String action; // create_order, record_payment, cancel_order, ...
  final String entityType; // order / payment / packaging / customer / user
  final String entityId;
  final String actorId;
  final String actorName;
  final String note;
  final DateTime at;

  AuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.actorId = '',
    this.actorName = '',
    this.note = '',
    required this.at,
  });

  factory AuditLog.fromMap(String id, Map<String, dynamic> m) => AuditLog(
        id: id,
        action: m['action'] ?? '',
        entityType: m['entityType'] ?? '',
        entityId: m['entityId'] ?? '',
        actorId: m['actorId'] ?? '',
        actorName: m['actorName'] ?? '',
        note: m['note'] ?? '',
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] ?? 0) as int),
      );

  /// Vietnamese label for the action verb.
  String get actionLabel => switch (action) {
        'create_order' => 'Tạo đơn',
        'record_payment' => 'Thu tiền',
        'cancel_order' => 'Hủy đơn',
        'warehouse_step' => 'Cập nhật kho',
        'pack_order' => 'Đóng hàng',
        'depart_order' => 'Xuất phát',
        'deliver_order' => 'Giao hàng',
        'delivery_failed' => 'Giao không thành công',
        'mark_priority' => 'Đánh dấu GẤP',
        'unmark_priority' => 'Bỏ đánh dấu GẤP',
        'price_change' => 'Đổi giá',
        // `Db.deleteUser`/`deleteCustomer` ghi action IN HOA — giữ nguyên chuỗi
        // đã lưu trong Firestore, chỉ thêm nhãn cho khỏi hiện mã trần.
        'DELETE_USER' => 'Xoá người dùng',
        'DELETE_CUSTOMER' => 'Xoá khách hàng',
        // legacy — phân hệ chuyến xe/tài xế đã bỏ, nhật ký cũ vẫn cần nhãn
        'depart_trip' => 'Xe xuất phát',
        'assign_trip' => 'Xếp chuyến',
        _ => action,
      };
}
