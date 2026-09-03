import '../core/enums.dart';

/// Notification targets (spec §15). `refType`/`refId` deep-link to the object.
enum NotifRefType { order, trip, customer, debt }

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotifRefType refType;
  final String refId;
  final Set<UserRole> targetRoles;
  final DateTime at;
  final bool read;
  final String icon; // material icon key

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.refType,
    required this.refId,
    required this.targetRoles,
    required this.at,
    this.read = false,
    this.icon = 'bell',
  });

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) =>
      AppNotification(
        id: id,
        title: m['title'] ?? '',
        body: m['body'] ?? '',
        refType: enumFromName(NotifRefType.values, m['refType'], NotifRefType.order),
        refId: m['refId'] ?? '',
        targetRoles: ((m['targetRoles'] as List?) ?? [])
            .map((e) => roleFromName(e as String))
            .toSet(),
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] ?? 0) as int),
        read: m['read'] ?? false,
        icon: m['icon'] ?? 'bell',
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'body': body,
        'refType': refType.name,
        'refId': refId,
        'targetRoles': targetRoles.map((e) => e.name).toList(),
        'at': at.millisecondsSinceEpoch,
        'read': read,
        'icon': icon,
      };
}
