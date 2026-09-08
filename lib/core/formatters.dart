import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Money is stored as integer đồng (spec §20: no float).
final _currency = NumberFormat.decimalPattern('vi_VN');

String money(num v) => '${_currency.format(v)}đ';

String moneySigned(num v) => v < 0 ? '- ${money(-v)}' : money(v);

/// Số có phân cách nghìn, không hậu tố "đ" — dùng để đổ vào ô nhập.
String moneyPlain(num v) => _currency.format(v);

/// Lấy số nguyên đồng từ chuỗi đã format (bỏ mọi ký tự không phải số).
int parseMoney(String s) =>
    int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Formatter cho ô nhập SĐT: chỉ cho số, tối đa 11 chữ số (SĐT VN).
final phoneInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(11),
];

/// Formatter cho ô nhập tiền: gõ 125000 → hiển thị 125.000 (kiểu vi_VN).
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final formatted = _currency.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final _timeFmt = DateFormat('HH:mm');

String fmtDate(DateTime? d) => d == null ? '--' : _dateFmt.format(d);
String fmtDateTime(DateTime? d) => d == null ? '--' : _dateTimeFmt.format(d);
String fmtTime(DateTime? d) => d == null ? '--' : _timeFmt.format(d);

final _dayTimeFmt = DateFormat('dd/MM HH:mm');

/// Giờ xuất phát dự kiến hiện trên thẻ đơn: trong ngày hôm nay thì chỉ cần
/// `HH:mm` cho gọn, khác ngày mới kèm `dd/MM` — để người xem hàng đợi nhận ra
/// ngay đơn nào là của hôm khác.
String fmtDepartAt(DateTime? d) {
  if (d == null) return '--';
  final now = DateTime.now();
  final sameDay =
      d.year == now.year && d.month == now.month && d.day == now.day;
  return sameDay ? _timeFmt.format(d) : _dayTimeFmt.format(d);
}

/// Order code: DHyyMMdd-NNN.
String orderCode(DateTime d, int seq) =>
    'DH${DateFormat('yyMMdd').format(d)}-${seq.toString().padLeft(3, '0')}';

