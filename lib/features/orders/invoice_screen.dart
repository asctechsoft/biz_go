import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/shop_info.dart';
import '../../services/db.dart';
import '../../services/invoice_pdf.dart';
import '../../widgets/common.dart';

/// Tên app in ở dòng đầu phiếu. Không sửa được trong Cài đặt — phần sửa được
/// (tiêu đề cửa hàng + SĐT) nằm ở `meta/shop`, xem [ShopInfo].
const _brand = 'BizGo';

/// Xuất phiếu ra PDF rồi mở hộp chia sẻ để lưu về máy / gửi Zalo.
///
/// Tách khỏi [InvoiceScreen] để màn chi tiết đơn gọi thẳng được, không phải mở
/// phiếu lên trước.
Future<void> downloadInvoicePdf(
    BuildContext context, Order order, ShopInfo shop) async {
  toast(context, 'Đang tạo PDF...');
  try {
    await InvoicePdf.export(order, shop);
  } catch (e) {
    debugPrint('EXPORT-PDF ERROR: $e');
    if (context.mounted) {
      toast(context,
          friendlyError(e, fallback: 'Tạo PDF không thành công. Thử lại giúp tôi.'));
    }
  }
}

/// Phiếu giao hàng (§8): mẫu hóa đơn xem trước + in. Bluetooth in sau.
class InvoiceScreen extends StatelessWidget {
  final Order order;
  final int copies;
  const InvoiceScreen({super.key, required this.order, this.copies = 1});

  @override
  Widget build(BuildContext context) {
    // Tiêu đề + SĐT lấy từ Cài đặt phiếu; chưa đặt SĐT thì Db trả về số của
    // tài khoản Chủ. Dựng tạm bằng giá trị mặc định trong lúc chờ stream để
    // phiếu không nháy trắng.
    return StreamBuilder<ShopInfo>(
      stream: context.read<Db>().shopInfo(),
      builder: (context, snap) => _paper(
        context,
        snap.data ?? const ShopInfo(title: ShopInfo.defaultTitle, phone: ''),
      ),
    );
  }

  Widget _paper(BuildContext context, ShopInfo shop) {
    final o = order;
    return Scaffold(
      backgroundColor: const Color(0xFFECECEC),
      appBar: AppBar(
        title: const Text('Phiếu giao hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Tải PDF',
            onPressed: () => downloadInvoicePdf(context, o, shop),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'In',
            onPressed: () => toast(
              context,
              'Gửi lệnh in ${o.code}${copies > 1 ? ' · $copies bản' : ''} tới máy in Bluetooth (kết nối máy để in thật)',
            ),
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
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header cửa hàng
                Center(
                  child: Column(
                    children: [
                      const Text(
                        _brand,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shop.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (shop.phone.isNotEmpty)
                        Text(
                          'SĐT: ${shop.phone}',
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'PHIẾU GIAO HÀNG',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // Mã kiện đặt ngay dưới tiêu đề để nhìn thấy đầu tiên.
                if (o.packageCode != null) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Mã kiện hàng: ${o.packageCode}${o.weightKg != null ? ' - ${fmtWeight(o.weightKg, o.weightUnit)}' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ]
                // Đơn đóng trước khi đổi sang mã kiện tự động.
                else if (o.packageCount != null) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Số kiện: ${o.packageCount}${o.weightKg != null ? ' - ${fmtWeight(o.weightKg, o.weightUnit)}' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _dashed(),
                // Mã đơn + ngày
                _line('Số phiếu:', o.code, bold: true),
                _line('Ngày:', fmtDateTime(o.createdAt)),
                const SizedBox(height: 6),
                // Khách hàng
                _line('Khách hàng:', o.customerName, bold: true),
                _line('Điện thoại:', o.customerPhone),
                _line(
                  'Địa chỉ:',
                  o.deliveryAddress.isEmpty ? '--' : o.deliveryAddress,
                ),
                if (o.deliveryReceiver.isNotEmpty)
                  _line('Người nhận:', o.deliveryReceiver),
                const SizedBox(height: 8),
                _dashed(),
                // Bảng sản phẩm
                const Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        'Mặt hàng',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'SL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Text(
                        'Thành tiền',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
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
                              Text(
                                it.displayName,
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                '  ${money(it.unitPrice)}/${it.packagingName}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${it.quantity}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            money(it.lineTotal),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                _dashed(),
                _line('Tạm tính:', money(o.subtotal)),
                if (o.shippingFee != 0)
                  _line('Phí giao:', money(o.shippingFee)),
                if (o.discount != 0)
                  _line('Giảm giá:', '- ${money(o.discount)}'),
                _line('TỔNG CỘNG:', money(o.total), bold: true, big: true),
                if (o.paidAmount != 0)
                  _line('Đã thanh toán:', money(o.paidAmount)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 10,
                  ),
                  color: const Color(0xFFFFF3E0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CẦN THU:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        money(o.remaining > 0 ? o.remaining : 0),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
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
                      child: Text(
                        'Người giao\n(ký, ghi rõ họ tên)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Người nhận\n(ký, ghi rõ họ tên)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Cảm ơn quý khách!',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => toast(
              context,
              'Gửi lệnh in tới máy in Bluetooth (kết nối máy để in thật)',
            ),
            icon: const Icon(Icons.print),
            label: Text('In phiếu${copies > 1 ? ' · $copies bản' : ''}'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => downloadInvoicePdf(context, o, shop),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Tải PDF'),
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
            Text(
              k,
              style: TextStyle(
                fontSize: big ? 15 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: big ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
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
