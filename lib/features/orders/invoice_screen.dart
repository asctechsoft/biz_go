import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../widgets/common.dart';

/// Thông tin cửa hàng in trên phiếu (§8). Sửa tại đây khi đổi shop.
class ShopInfo {
  static const name = 'BizGo';
  static const phone = '0900 000 000';
  static const address = 'Xưởng sấy dẻo — Giao hàng toàn quốc';
}

/// Phiếu giao hàng (§8): mẫu hóa đơn xem trước + in. Bluetooth in sau.
class InvoiceScreen extends StatelessWidget {
  final Order order;
  final int copies;
  const InvoiceScreen({super.key, required this.order, this.copies = 1});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Scaffold(
      backgroundColor: const Color(0xFFECECEC),
      appBar: AppBar(
        title: const Text('Phiếu giao hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'In',
            onPressed: () => toast(context,
                'Gửi lệnh in ${o.code}${copies > 1 ? ' · $copies bản' : ''} tới máy in Bluetooth (kết nối máy để in thật)'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tờ phiếu — nền trắng, khổ giấy in.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header cửa hàng
                Center(
                  child: Column(
                    children: [
                      const Text(ShopInfo.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text('ĐT: ${ShopInfo.phone}',
                          style: const TextStyle(fontSize: 12)),
                      const Text(ShopInfo.address,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text('PHIẾU GIAO HÀNG',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
                const SizedBox(height: 8),
                _dashed(),
                // Mã đơn + ngày
                _line('Số phiếu:', o.code, bold: true),
                _line('Ngày:', fmtDateTime(o.createdAt)),
                const SizedBox(height: 6),
                // Khách hàng
                _line('Khách hàng:', o.customerName, bold: true),
                _line('Điện thoại:', o.customerPhone),
                _line('Địa chỉ:',
                    o.deliveryAddress.isEmpty ? '--' : o.deliveryAddress),
                if (o.deliveryReceiver.isNotEmpty)
                  _line('Người nhận:', o.deliveryReceiver),
                const SizedBox(height: 8),
                _dashed(),
                // Bảng sản phẩm
                const Row(
                  children: [
                    Expanded(
                        flex: 5,
                        child: Text('Mặt hàng',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12))),
                    Expanded(
                        flex: 2,
                        child: Text('SL',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12))),
                    Expanded(
                        flex: 4,
                        child: Text('Thành tiền',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12))),
                  ],
                ),
                const SizedBox(height: 4),
                for (final it in o.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it.displayName,
                                    style: const TextStyle(fontSize: 13)),
                                Text('  ${money(it.unitPrice)}/${it.packagingName}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary)),
                              ],
                            )),
                        Expanded(
                            flex: 2,
                            child: Text('${it.quantity}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13))),
                        Expanded(
                            flex: 4,
                            child: Text(money(it.lineTotal),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                _dashed(),
                _line('Tạm tính:', money(o.subtotal)),
                if (o.shippingFee != 0) _line('Phí giao:', money(o.shippingFee)),
                if (o.discount != 0) _line('Giảm giá:', '- ${money(o.discount)}'),
                _line('TỔNG CỘNG:', money(o.total), bold: true, big: true),
                if (o.paidAmount != 0) _line('Đã thanh toán:', money(o.paidAmount)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  color: const Color(0xFFFFF3E0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('CẦN THU:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(money(o.remaining > 0 ? o.remaining : 0),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.danger)),
                    ],
                  ),
                ),
                if (o.packageCount != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _line('Số kiện:',
                        '${o.packageCount}${o.weightKg != null ? ' · ${o.weightKg}kg' : ''}'),
                  ),
                if (o.deliveryNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _line('Ghi chú:', o.deliveryNote),
                ],
                const SizedBox(height: 10),
                _dashed(),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(
                        child: Text('Người giao\n(ký, ghi rõ họ tên)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11))),
                    Expanded(
                        child: Text('Người nhận\n(ký, ghi rõ họ tên)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11))),
                  ],
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text('Cảm ơn quý khách!',
                      style: TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => toast(context,
                'Gửi lệnh in tới máy in Bluetooth (kết nối máy để in thật)'),
            icon: const Icon(Icons.print),
            label: Text('In phiếu${copies > 1 ? ' · $copies bản' : ''}'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _line(String k, String v, {bool bold = false, bool big = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: big ? 15 : 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: big ? 15 : 13,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            ),
          ],
        ),
      );

  Widget _dashed() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '- - - - - - - - - - - - - - - - - - - - - - - - -',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
}
