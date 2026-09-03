import 'package:intl/intl.dart';

/// Money is stored as integer đồng (spec §20: no float).
final _currency = NumberFormat.decimalPattern('vi_VN');

String money(num v) => '${_currency.format(v)}đ';

String moneySigned(num v) => v < 0 ? '- ${money(-v)}' : money(v);

final _dateFmt = DateFormat('dd/MM/yyyy');
final _dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm');
final _timeFmt = DateFormat('HH:mm');

String fmtDate(DateTime? d) => d == null ? '--' : _dateFmt.format(d);
String fmtDateTime(DateTime? d) => d == null ? '--' : _dateTimeFmt.format(d);
String fmtTime(DateTime? d) => d == null ? '--' : _timeFmt.format(d);

/// Order code: DHyyMMdd-NNN. Trip code: CXyyMMdd-NN.
String orderCode(DateTime d, int seq) =>
    'DH${DateFormat('yyMMdd').format(d)}-${seq.toString().padLeft(3, '0')}';

String tripCode(DateTime d, int seq) =>
    'CX${DateFormat('yyMMdd').format(d)}-${seq.toString().padLeft(2, '0')}';
