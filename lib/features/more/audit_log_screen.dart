import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/audit_log.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// §2, §20 — nhật ký kiểm toán: ai làm gì, lúc nào.
class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  static String _entityLabel(String t) => switch (t) {
        'order' => 'Đơn hàng',
        'payment' => 'Thanh toán',
        'customer' => 'Khách hàng',
        'product' => 'Sản phẩm',
        'packaging' => 'Quy cách',
        'category' => 'Danh mục',
        'user' => 'Người dùng',
        // legacy — chuyến xe/xe đã bỏ, nhật ký cũ vẫn cần nhãn để đọc được
        'trip' => 'Chuyến xe',
        'vehicle' => 'Xe',
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký hệ thống')),
      body: StreamBuilder<List<AuditLog>>(
        stream: db.audits(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snap.data!;
          if (logs.isEmpty) return const EmptyState(text: 'Chưa có nhật ký');
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = logs[i];
              return Card(
                child: ListTile(
                  title: Text(a.actionLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (a.note.isNotEmpty) Text(a.note),
                      Text(
                          '${fmtDateTime(a.at)}${a.actorName.isEmpty ? '' : ' · ${a.actorName}'}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  trailing: Text(_entityLabel(a.entityType),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
