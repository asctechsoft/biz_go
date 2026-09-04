import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/customer.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final db = context.read<Db>();
    return Scaffold(
      appBar: AppBar(title: const Text('Khách hàng')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm khách hàng...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: db.customers(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!
                    .where((c) =>
                        c.name.toLowerCase().contains(_q) || c.phone.contains(_q))
                    .toList();
                if (items.isEmpty) {
                  return const EmptyState(text: 'Chưa có khách hàng');
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Card(
                      child: ListTile(
                        onTap: () => context.push('/customers/${c.id}'),
                        leading: Avatar(c.name, imagePath: c.imagePath),
                        title: Text(c.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone),
                        trailing: Text(
                          c.debt > 0 ? 'Nợ: ${money(c.debt)}' : 'Nợ: 0đ',
                          style: TextStyle(
                            color: c.debt > 0
                                ? AppColors.danger
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ElevatedButton.icon(
                onPressed: () => context.push('/customers/new'),
                icon: const Icon(Icons.add),
                label: const Text('Thêm khách hàng'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
