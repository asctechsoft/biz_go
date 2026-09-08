import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_text.dart';
import '../../core/file_share.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import '../../models/shop_info.dart';
import '../../services/db.dart';
import '../../services/invoice_pdf.dart';
import '../../widgets/common.dart';

/// Xuất phiếu ra PDF rồi mở hộp chia sẻ để lưu về máy / gửi Zalo.
///
/// Tách khỏi [InvoiceScreen] để màn chi tiết đơn gọi thẳng được, không phải mở
/// phiếu lên trước.
/// [showMoney] false → phiếu chỉ có mặt hàng + số lượng, không cột thành
/// tiền / tổng cộng / cần thu (phiếu cho kho soạn hàng).
Future<void> downloadInvoicePdf(
  BuildContext context,
  Order order,
  ShopInfo shop, {
  bool showMoney = true,
}) async {
  toast(context, 'Đang tạo PDF...');
  try {
    await InvoicePdf.export(order, shop, showMoney: showMoney);
  } catch (e) {
    debugPrint('EXPORT-PDF ERROR: $e');
    if (context.mounted) {
      toast(
        context,
        friendlyError(
          e,
          fallback: 'Tạo PDF không thành công. Thử lại giúp tôi.',
        ),
      );
    }
  }
}

/// Phiếu giao hàng (§8): mẫu hóa đơn xem trước + in. Bluetooth in sau.
///
/// Có in giá hay không quyết định bởi 2 tầng:
/// 1. [canSeeMoney] — quyền của người đang xem (`Perm.viewMoney`). False thì
///    khoá cứng, không nút nào mở lại được.
/// 2. `ShopInfo.hidePrices` — mặc định của cửa hàng, đặt ở Cài đặt phiếu.
///    Chủ lật được cho RIÊNG lần in này bằng nút trên thanh tiêu đề.
class InvoiceScreen extends StatefulWidget {
  final Order order;
  final int copies;

  /// Vai trò có được xem tiền không. False → phiếu luôn không giá.
  final bool canSeeMoney;
  const InvoiceScreen({
    super.key,
    required this.order,
    this.copies = 1,
    this.canSeeMoney = true,
  });

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  /// Lật tay cho riêng lần in này. `null` = theo mặc định trong Cài đặt phiếu.
  bool? _override;

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
    final o = widget.order;
    final copies = widget.copies;
    // Không có quyền xem tiền thì mọi thứ bên dưới vô nghĩa — luôn false.
    final showMoney = widget.canSeeMoney && (_override ?? !shop.hidePrices);
    return Scaffold(
      backgroundColor: const Color(0xFFECECEC),
      appBar: AppBar(
        title: const Text('Phiếu giao hàng'),
        actions: [
          // Lật giá cho riêng lần in này. Chỉ hiện với người được xem tiền.
          if (widget.canSeeMoney)
            IconButton(
              icon: Icon(
                showMoney ? Icons.attach_money : Icons.money_off_csred_outlined,
              ),
              tooltip: showMoney ? 'Đang in kèm giá' : 'Đang in không giá',
              onPressed: () => setState(() => _override = !showMoney),
            ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Tải PDF',
            // PHẢI truyền showMoney: xem bản ẩn tiền rồi bấm tải mà quên cờ
            // này thì PDF ra bản đầy đủ giá — lộ đúng thứ vừa che.
            onPressed: () =>
                downloadInvoicePdf(context, o, shop, showMoney: showMoney),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'In',
            // Web (PC nối máy in): dựng PDF rồi mở hộp thoại in trình duyệt →
            // in thẳng. Android vẫn là preview Bluetooth (chưa làm in thật).
            onPressed: () async {
              if (kIsWeb) {
                try {
                  final bytes = await InvoicePdf.build(
                    o,
                    shop,
                    showMoney: showMoney,
                  );
                  await printPdfBytes(bytes, docName: 'Phieu_${o.code}');
                } catch (e) {
                  if (context.mounted) {
                    toast(
                      context,
                      friendlyError(e, fallback: 'In không thành công.'),
                    );
                  }
                }
              } else {
                toast(
                  context,
                  'Gửi lệnh in ${o.code}${copies > 1 ? ' · $copies bản' : ''} tới máy in Bluetooth (kết nối máy để in thật)',
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        // Chừa chỗ cho thanh điều hướng Android — nút "Tải PDF" nằm cuối trang.
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shop.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (shop.phone.isNotEmpty)
                        Text(
                          'SĐT: ${shop.phone}',
                          style: const TextStyle(fontSize: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'PHIẾU GIAO HÀNG',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                // Gửi qua nhà xe thì đây là thông tin người giao cần nhất.
                if (o.hasCarrier) ...[
                  _line('Nhà xe:', o.deliveryCarrierName, bold: true),
                  if (o.deliveryCarrierPhone.isNotEmpty)
                    _line('SĐT nhà xe:', o.deliveryCarrierPhone),
                ],
                // Dặn dò cố định của địa chỉ ("gọi trước khi tới"...).
                if (o.deliveryAddressNote.isNotEmpty)
                  _line('Lưu ý địa chỉ:', o.deliveryAddressNote),
                const SizedBox(height: 8),
                // Bảng sản phẩm — bỏ `const` vì cột "Thành tiền" có điều kiện.
                Row(
                  children: [
                    const Expanded(
                      flex: 5,
                      child: Text(
                        'Mặt hàng',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const Expanded(
                      flex: 2,
                      child: Text(
                        'SL',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (showMoney)
                      const Expanded(
                        flex: 4,
                        child: Text(
                          'Thành tiền',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
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
                              // Phân loại làm tên mặt hàng, KHÔNG phải tên sản
                              // phẩm: mọi dòng đều là "Cùi Bưởi 1kg" thì phiếu
                              // in ra không phân biệt nổi dòng nào là dòng nào.
                              // Giống hệt màn chi tiết đơn.
                              Text(
                                it.variantLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                showMoney
                                    ? '${it.packagingName} · ${money(it.unitPrice)}'
                                    : it.packagingName,
                                style: const TextStyle(
                                  fontSize: 13,
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
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        if (showMoney)
                          Expanded(
                            flex: 4,
                            child: Text(
                              money(it.lineTotal),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                if (showMoney) ...[
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
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          money(o.remaining > 0 ? o.remaining : 0),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  _line(
                    'Tổng số lượng:',
                    '${o.items.fold<int>(0, (s, i) => s + i.quantity)}',
                    bold: true,
                  ),
                if (o.deliveryNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _line('Ghi chú:', o.deliveryNote),
                ],
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Người giao\n(ký, ghi rõ họ tên)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Người nhận\n(ký, ghi rõ họ tên)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Cảm ơn quý khách!',
                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
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
            onPressed: () =>
                downloadInvoicePdf(context, o, shop, showMoney: showMoney),
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
                fontSize: big ? 17 : 15,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: big ? 17 : 15,
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
      style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
    ),
  );
}
