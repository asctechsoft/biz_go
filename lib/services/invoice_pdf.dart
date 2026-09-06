import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/file_share.dart';
import '../core/formatters.dart';
import '../models/order.dart';
import '../models/shop_info.dart';

/// Xuất phiếu giao hàng ra PDF rồi mở hộp chia sẻ (giống [ExcelExport]).
///
/// Font Roboto bundle trong `assets/fonts/` — font mặc định của thư viện `pdf`
/// (Helvetica) KHÔNG có glyph tiếng Việt, để nguyên thì phiếu in ra mất dấu.
class InvoicePdf {
  static const _brand = 'BizGo';

  // Nạp 1 lần rồi dùng lại — mỗi file font ~170KB, đọc lại mỗi lần xuất phiếu
  // là phí.
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    _regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    _bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  }

  /// Dựng file PDF (A5 dọc). Nhiều mặt hàng thì `MultiPage` tự sang trang.
  ///
  /// [showMoney] false → phiếu chỉ có mặt hàng + số lượng: bỏ cột thành tiền,
  /// bỏ khối tổng cộng và ô CẦN THU. Dùng cho người không phải Chủ, đủ để soạn
  /// và giao hàng mà không lộ giá bán.
  static Future<Uint8List> build(Order o, ShopInfo shop,
      {bool showMoney = true}) async {
    await _loadFonts();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          _header(o, shop),
          pw.SizedBox(height: 8),
          _dashed(),
          _kv('Số phiếu:', o.code, bold: true),
          _kv('Ngày:', fmtDateTime(o.createdAt)),
          pw.SizedBox(height: 6),
          _kv('Khách hàng:', o.customerName, bold: true),
          _kv('Điện thoại:', o.customerPhone),
          _kv('Địa chỉ:', o.deliveryAddress.isEmpty ? '--' : o.deliveryAddress),
          if (o.deliveryReceiver.isNotEmpty)
            _kv('Người nhận:', o.deliveryReceiver),
          // Gửi qua nhà xe thì đây là thông tin người giao cần nhất.
          if (o.hasCarrier) ...[
            _kv('Nhà xe:', o.deliveryCarrierName, bold: true),
            if (o.deliveryCarrierPhone.isNotEmpty)
              _kv('SĐT nhà xe:', o.deliveryCarrierPhone),
          ],
          // Dặn dò cố định của địa chỉ ("gọi trước khi tới"...).
          if (o.deliveryAddressNote.isNotEmpty)
            _kv('Lưu ý địa chỉ:', o.deliveryAddressNote),
          pw.SizedBox(height: 8),
          _dashed(),
          _items(o, showMoney),
          pw.SizedBox(height: 6),
          _dashed(),
          if (showMoney) ...[
            _kv('Tạm tính:', money(o.subtotal)),
            if (o.shippingFee != 0) _kv('Phí giao:', money(o.shippingFee)),
            if (o.discount != 0) _kv('Giảm giá:', '- ${money(o.discount)}'),
            _kv('TỔNG CỘNG:', money(o.total), bold: true, size: 16),
            if (o.paidAmount != 0) _kv('Đã thanh toán:', money(o.paidAmount)),
            pw.SizedBox(height: 8),
            _due(o),
          ] else
            _kv('Tổng số lượng:',
                '${o.items.fold<int>(0, (s, i) => s + i.quantity)}',
                bold: true),
          if (o.deliveryNote.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _kv('Ghi chú:', o.deliveryNote),
          ],
          pw.SizedBox(height: 10),
          _dashed(),
          pw.SizedBox(height: 24),
          _signatures(),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Text('Cảm ơn quý khách!',
                style: pw.TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Dựng PDF rồi lưu/chia sẻ: Android ghi file tạm + mở hộp chia sẻ (Zalo/
  /// Drive/lưu máy), web tải file về qua trình duyệt. Tách nền tảng ở
  /// [saveAndShareBytes] để file này không phải đụng `dart:io`.
  static Future<void> export(Order o, ShopInfo shop,
      {bool showMoney = true}) async {
    final bytes = await build(o, shop, showMoney: showMoney);
    await saveAndShareBytes(
      bytes,
      filename: 'Phieu_${o.code}.pdf',
      mime: 'application/pdf',
      text: 'Phiếu giao hàng ${o.code} - ${o.customerName}',
    );
  }

  // ---------- Các mảnh dựng phiếu ----------

  /// Khối đầu phiếu — căn giữa.
  ///
  /// `SizedBox(width: double.infinity)` + `stretch` là bắt buộc: trong
  /// `MultiPage`, `pw.Column` co lại vừa nội dung, nên `CrossAxisAlignment
  /// .center` chỉ căn giữa BÊN TRONG bề rộng của chính nó — mà cái Column đó
  /// nằm sát mép trái, thành ra nhìn như căn trái. Ép rộng hết trang rồi cho
  /// mỗi dòng `textAlign: center` mới ra giữa thật.
  static pw.Widget _header(Order o, ShopInfo shop) => pw.SizedBox(
        width: double.infinity,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(_brand,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(shop.title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (shop.phone.isNotEmpty)
            pw.Text('SĐT: ${shop.phone}',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 13)),
          pw.SizedBox(height: 10),
          pw.Text('PHIẾU GIAO HÀNG',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 19,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1)),
          if (o.packageCode != null) ...[
            pw.SizedBox(height: 5),
            pw.Text(
                'Mã kiện hàng: ${o.packageCode}${o.weightKg != null ? ' - ${fmtWeight(o.weightKg, o.weightUnit)}' : ''}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ]
          // Đơn đóng trước khi đổi sang mã kiện tự động.
          else if (o.packageCount != null) ...[
            pw.SizedBox(height: 5),
            pw.Text(
                'Số kiện: ${o.packageCount}${o.weightKg != null ? ' - ${fmtWeight(o.weightKg, o.weightUnit)}' : ''}',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ],
        ],
        ),
      );

  static pw.Widget _items(Order o, bool showMoney) => pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(flex: 5, child: _th('Mặt hàng')),
              pw.Expanded(
                  flex: 2, child: _th('SL', align: pw.TextAlign.center)),
              if (showMoney)
                pw.Expanded(
                    flex: 4,
                    child: _th('Thành tiền', align: pw.TextAlign.right)),
            ],
          ),
          pw.SizedBox(height: 4),
          for (final it in o.items)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Phân loại làm tên mặt hàng — xem ghi chú ở
                        // `InvoiceScreen`, phải khớp với bản xem trước.
                        pw.Text(it.variantLabel,
                            style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold)),
                        pw.Text(
                            showMoney
                                ? '${it.packagingName} · ${money(it.unitPrice)}'
                                : it.packagingName,
                            style: const pw.TextStyle(
                                fontSize: 12, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('${it.quantity}',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 14)),
                  ),
                  if (showMoney)
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(money(it.lineTotal),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    ),
                ],
              ),
            ),
        ],
      );

  static pw.Widget _due(Order o) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        color: PdfColors.orange50,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('CẦN THU:',
                style: pw.TextStyle(
                    fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(money(o.remaining > 0 ? o.remaining : 0),
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)),
          ],
        ),
      );

  static pw.Widget _signatures() => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text('Người giao\n(ký, ghi rõ họ tên)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 13)),
          ),
          pw.Expanded(
            child: pw.Text('Người nhận\n(ký, ghi rõ họ tên)',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 13)),
          ),
        ],
      );

  static pw.Widget _th(String t, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Text(t,
          textAlign: align,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold));

  static pw.Widget _kv(String k, String v,
          {bool bold = false, double size = 14}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(k,
                style: pw.TextStyle(
                    fontSize: size,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(v,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: size,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
          ],
        ),
      );

  static pw.Widget _dashed() => pw.Container(
        height: 1,
        margin: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
                color: PdfColors.grey500, style: pw.BorderStyle.dashed),
          ),
        ),
      );
}
