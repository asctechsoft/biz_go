import '../core/enums.dart';

/// Every collection of money is an independent payment record (spec §12, §22).
class Payment {
  final String id;
  final String orderId;
  final String orderCode;
  final String customerId;
  final String customerName;
  final int amount;
  final PaymentMethod method;
  final DateTime at;
  final String actorId;
  final String actorName;
  final String note;

  Payment({
    required this.id,
    required this.orderId,
    required this.orderCode,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.method,
    required this.at,
    this.actorId = '',
    this.actorName = '',
    this.note = '',
  });

  factory Payment.fromMap(String id, Map<String, dynamic> m) => Payment(
        id: id,
        orderId: m['orderId'] ?? '',
        orderCode: m['orderCode'] ?? '',
        customerId: m['customerId'] ?? '',
        customerName: m['customerName'] ?? '',
        amount: (m['amount'] ?? 0) as int,
        method: enumFromName(PaymentMethod.values, m['method'], PaymentMethod.cash),
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] ?? 0) as int),
        actorId: m['actorId'] ?? '',
        actorName: m['actorName'] ?? '',
        note: m['note'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'orderId': orderId,
        'orderCode': orderCode,
        'customerId': customerId,
        'customerName': customerName,
        'amount': amount,
        'method': method.name,
        'at': at.millisecondsSinceEpoch,
        'actorId': actorId,
        'actorName': actorName,
        'note': note,
      };
}
