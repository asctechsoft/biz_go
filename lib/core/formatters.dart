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

const _accentGroups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final _noAccent = <String, String>{
  for (final g in _accentGroups.entries)
    for (final c in g.value.split('')) c: g.key,
};

/// Chuẩn hoá chuỗi để so khớp khi tìm kiếm: thường hoá + bỏ dấu tiếng Việt.
/// Bàn phím điện thoại hay gõ không dấu nên "bot vien" phải ra "Bột viên".
String searchKey(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    b.write(_noAccent[c] ?? c);
  }
  return b.toString();
}

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

    // Giữ con trỏ đúng chỗ người dùng đang sửa: đếm số CHỮ SỐ đứng trước con
    // trỏ trong text vừa gõ, rồi tìm vị trí có đúng chừng đó chữ số trong chuỗi
    // đã chèn dấu chấm. Đặt cứng về cuối thì xoá/chèn giữa số bị nhảy ra cuối.
    final cursor = newValue.selection.baseOffset;
    var offset = formatted.length;
    if (cursor >= 0 && cursor < newValue.text.length) {
      final digitsBefore = newValue.text
          .substring(0, cursor)
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length;
      var seen = 0;
      offset = 0;
      while (offset < formatted.length && seen < digitsBefore) {
        if (RegExp(r'[0-9]').hasMatch(formatted[offset])) seen++;
        offset++;
      }
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
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

