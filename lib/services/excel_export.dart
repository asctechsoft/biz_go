import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/enums.dart';
import '../models/customer.dart';
import '../models/order.dart';

/// Xuất báo cáo ra file Excel (.xlsx) rồi mở hộp chia sẻ.
/// Không cần backend / billing — file tạo tại máy, chia sẻ qua share_plus.
class ExcelExport {
  static final _d = DateFormat('dd/MM/yyyy');

  static Future<void> exportReport({
    required List<Order> orders,
    required List<Customer> customers,
    required DateTime from,
    required DateTime to,
  }) async {
    // Lọc đơn trong khoảng [from, to] (theo ngày tạo).
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    final inRange = orders
        .where((o) =>
            !o.createdAt.isBefore(start) && !o.createdAt.isAfter(end))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final excel = Excel.createExcel();

    _sheetOrders(excel, inRange);
    _sheetRevenueByDay(excel, inRange);
    _sheetBestSellers(excel, inRange);
    _sheetCustomerDebt(excel, customers);

    // Bỏ sheet mặc định.
    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final stamp = '${_d.format(from)}_${_d.format(to)}'.replaceAll('/', '-');
    final path = '${dir.path}/BaoCao_$stamp.xlsx';
    final file = File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      text: 'Báo cáo BizGo ${_d.format(from)} - ${_d.format(to)}',
    );
  }

  static void _header(Sheet s, List<String> cols) {
    s.appendRow(cols.map<CellValue?>((c) => TextCellValue(c)).toList());
  }

  static void _sheetOrders(Excel excel, List<Order> orders) {
    final s = excel['Đơn hàng'];
    _header(s, [
      'Mã đơn',
      'Ngày',
      'Khách hàng',
      'SĐT',
      'Tổng tiền',
      'Đã thu',
      'Còn nợ',
      'Trạng thái',
    ]);
    for (final o in orders) {
      s.appendRow(<CellValue?>[
        TextCellValue(o.code),
        TextCellValue(_d.format(o.createdAt)),
        TextCellValue(o.customerName),
        TextCellValue(o.customerPhone),
        IntCellValue(o.total),
        IntCellValue(o.paidAmount),
        IntCellValue(o.remaining),
        TextCellValue(orderStatusUi(o.orderStatus).label),
      ]);
    }
  }

  static void _sheetRevenueByDay(Excel excel, List<Order> orders) {
    final s = excel['Doanh thu theo ngày'];
    _header(s, ['Ngày', 'Số đơn', 'Doanh thu']);
    final byDay = <String, (int count, int total)>{};
    for (final o in orders) {
      if (o.orderStatus == OrderStatus.CANCELLED) continue;
      final key = _d.format(o.createdAt);
      final cur = byDay[key] ?? (0, 0);
      byDay[key] = (cur.$1 + 1, cur.$2 + o.total);
    }
    for (final e in byDay.entries) {
      s.appendRow(<CellValue?>[
        TextCellValue(e.key),
        IntCellValue(e.value.$1),
        IntCellValue(e.value.$2),
      ]);
    }
  }

  static void _sheetBestSellers(Excel excel, List<Order> orders) {
    final s = excel['Sản phẩm bán chạy'];
    _header(s, ['Mặt hàng', 'Số lượng', 'Doanh thu']);
    final agg = <String, (int qty, int total)>{};
    for (final o in orders) {
      if (o.orderStatus == OrderStatus.CANCELLED) continue;
      for (final it in o.items) {
        final cur = agg[it.reportLabel] ?? (0, 0);
        agg[it.reportLabel] = (cur.$1 + it.quantity, cur.$2 + it.lineTotal);
      }
    }
    final rows = agg.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    for (final e in rows) {
      s.appendRow(<CellValue?>[
        TextCellValue(e.key),
        IntCellValue(e.value.$1),
        IntCellValue(e.value.$2),
      ]);
    }
  }

  static void _sheetCustomerDebt(Excel excel, List<Customer> customers) {
    final s = excel['Công nợ khách'];
    _header(s, ['Khách hàng', 'SĐT', 'Công nợ']);
    final debtors = customers.where((c) => c.debt > 0).toList()
      ..sort((a, b) => b.debt.compareTo(a.debt));
    for (final c in debtors) {
      s.appendRow(<CellValue?>[
        TextCellValue(c.name),
        TextCellValue(c.phone),
        IntCellValue(c.debt),
      ]);
    }
  }
}
