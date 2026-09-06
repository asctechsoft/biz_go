import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/enums.dart';
import '../core/theme.dart';
import '../services/image_service.dart';

class StatusChip extends StatelessWidget {
  final StatusUi ui;
  final bool dense;
  const StatusChip(this.ui, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: ui.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ui.label,
        style: TextStyle(
          color: ui.color,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Renders a locally stored (compressed) image, with a graceful placeholder.
class LocalImage extends StatelessWidget {
  final String? path;
  final double size;
  final double radius;
  final IconData placeholder;
  const LocalImage({
    super.key,
    required this.path,
    this.size = 56,
    this.radius = 12,
    this.placeholder = Icons.image_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final ok = ImageService.exists(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: AppColors.primaryLight,
        child: ok
            ? ImageService.imageWidget(path!, fit: BoxFit.cover)
            : Icon(placeholder, color: AppColors.primary, size: size * 0.45),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SectionCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) =>
      Card(child: Padding(padding: padding, child: child));
}

class KVRow extends StatelessWidget {
  final String k;
  final String v;
  final Color? valueColor;
  final bool bold;
  const KVRow(this.k, this.v, {super.key, this.valueColor, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(k,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.text});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(text,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          ],
        ),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imagePath; // ảnh local (nếu có) → hiện ảnh, không thì chữ cái
  const Avatar(this.name, {super.key, this.size = 44, this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (ImageService.exists(imagePath)) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.primaryLight,
        backgroundImage: ImageService.imageProvider(imagePath!),
      );
    }
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primaryLight,
      child: Text(initials,
          style: const TextStyle(
              color: AppColors.primary, fontWeight: FontWeight.w700)),
    );
  }
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirm = 'Xác nhận'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: double.maxFinite, child: Text(message)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false), child: const Text('Hủy')),
        ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm)),
      ],
    ),
  );
  return r ?? false;
}

/// Chọn **ngày + giờ** trong MỘT bottom sheet.
///
/// Không dùng `showDatePicker` + `showTimePicker` mặc định: hai hộp thoại nối
/// nhau, mặt đồng hồ kim khó bấm đúng phút, và chọn "8h sáng mai" phải qua 6
/// thao tác. Ở đây ngày là dải chip 14 ngày tới, giờ là 2 bánh xe lăn — việc
/// hay gặp nhất chỉ tốn 2 chạm.
///
/// Phút bước **5** (0, 5, 10...) vì giờ xuất phát không ai hẹn lẻ từng phút;
/// giá trị cũ lẻ sẽ được làm tròn về mốc 5 phút gần nhất.
///
/// Trả `null` khi người dùng đóng sheet mà không xác nhận.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  String helpText = 'Chọn thời gian',
}) async {
  final now = DateTime.now();
  final base = initial ?? now.add(const Duration(hours: 1));

  // 14 ngày kể từ hôm nay — đủ cho lịch giao hàng, khỏi cần hộp thoại lịch.
  final today = DateTime(now.year, now.month, now.day);
  final days = List.generate(14, (i) => today.add(Duration(days: i)));

  var day = DateTime(base.year, base.month, base.day);
  // Ngày cũ đã qua thì kéo về hôm nay; ngày xa trong tương lai GIỮ NGUYÊN —
  // đặt lịch cho tháng sau là chuyện có thật.
  if (day.isBefore(today)) day = today;

  // Mở sẵn lịch tháng khi ngày đang chọn nằm ngoài dải chip 14 ngày.
  var showCalendar = day.isAfter(days.last);
  // Nới trần nếu đơn cũ có giờ đặt xa hơn 1 năm — `CalendarDatePicker` assert
  // khi `initialDate` vượt `lastDate`.
  final yearAhead = today.add(const Duration(days: 365));
  final lastPickable = day.isAfter(yearAhead) ? day : yearAhead;

  var hour = base.hour;
  var minuteIndex = (base.minute / 5).round().clamp(0, 11);

  final hourCtrl = FixedExtentScrollController(initialItem: hour);
  final minCtrl = FixedExtentScrollController(initialItem: minuteIndex);
  final dayCtrl = ScrollController();
  var didInitialScroll = false;

  /// Kéo dải chip tới ngày đang chọn. Chọn 25/09 từ lịch mà dải vẫn đứng ở
  /// "Hôm nay" thì nhìn như chưa chọn gì.
  void scrollToDay() {
    if (!dayCtrl.hasClients) return;
    final list = days.contains(day) ? days : [...days, day];
    final i = list.indexOf(day);
    if (i < 0) return;
    const extent = 70.0; // 62 bề ngang chip + 8 khoảng cách
    final target =
        (i * extent - 24).clamp(0.0, dayCtrl.position.maxScrollExtent);
    dayCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  try {
    return await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final picked = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minuteIndex * 5,
          );
          // Ngày đang chọn nằm ngoài 14 ngày đầu thì chèn thêm chip cho nó,
          // không thì chuyển sang chế độ chip là mất dấu ngày vừa chọn.
          final chips = days.contains(day) ? days : [...days, day];
          // Mở sheet mà ngày đang chọn nằm giữa dải thì cũng phải kéo tới.
          if (!didInitialScroll) {
            didInitialScroll = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => scrollToDay());
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              // Cuộn được: máy màn ngắn thì cụm ngày + chip + bánh xe cao hơn
              // chiều cao sheet cho phép.
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SheetHeader(helpText),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                    child: Row(
                      children: [
                        const Text(
                          'Ngày',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        // Dải chip chỉ phủ 2 tuần; đặt lịch tháng sau thì mở
                        // lịch tháng ra chọn.
                        TextButton.icon(
                          onPressed: () =>
                              setSheet(() => showCalendar = !showCalendar),
                          icon: Icon(
                            showCalendar
                                ? Icons.view_week_outlined
                                : Icons.calendar_month_outlined,
                            size: 18,
                          ),
                          label: Text(
                            showCalendar ? 'Chọn nhanh' : 'Ngày khác',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showCalendar)
                    SizedBox(
                      height: 320,
                      child: CalendarDatePicker(
                        initialDate: day,
                        firstDate: today,
                        lastDate: lastPickable,
                        onDateChanged: (d) => setSheet(() {
                          day = DateTime(d.year, d.month, d.day);
                          // Chọn xong thì thu lịch lại để thấy ngay phần giờ.
                          showCalendar = false;
                          // Dải chip vừa dựng lại ở khung sau — phải đợi nó
                          // gắn vào controller rồi mới cuộn được.
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => scrollToDay());
                        }),
                      ),
                    )
                  else
                    SizedBox(
                    height: 62,
                    child: ListView.separated(
                      controller: dayCtrl,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: chips.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final d = chips[i];
                        final on = d == day;
                        return InkWell(
                          onTap: () => setSheet(() => day = d),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 62,
                            decoration: BoxDecoration(
                              color: on ? AppColors.primary : AppColors.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: on ? AppColors.primary : AppColors.border,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _dayTag(d, today),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: on
                                        ? Colors.white70
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${d.day}/${d.month}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: on
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const _PickerLabel('Giờ hay dùng'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 3 khung giờ chốt theo lịch chạy hàng thực tế.
                        for (final h in const [10, 13, 17])
                          ChoiceChip(
                            label: Text('$h:00'.padLeft(5, '0')),
                            selected: hour == h && minuteIndex == 0,
                            onSelected: (_) => setSheet(() {
                              hour = h;
                              minuteIndex = 0;
                              hourCtrl.jumpToItem(h);
                              minCtrl.jumpToItem(0);
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Hai bánh xe lăn: chọn giờ/phút bằng vuốt, không phải nhắm
                  // vào kim đồng hồ.
                  SizedBox(
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 46,
                          margin: const EdgeInsets.symmetric(horizontal: 60),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _wheel(
                              controller: hourCtrl,
                              count: 24,
                              selected: hour,
                              label: (i) => i.toString().padLeft(2, '0'),
                              onChanged: (i) => setSheet(() => hour = i),
                            ),
                            const Text(
                              ':',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            _wheel(
                              controller: minCtrl,
                              count: 12,
                              selected: minuteIndex,
                              label: (i) => (i * 5).toString().padLeft(2, '0'),
                              onChanged: (i) =>
                                  setSheet(() => minuteIndex = i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Nhắc lại nguyên câu để khỏi chọn nhầm ngày mà không biết.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _fullLabel(picked, today),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Huỷ'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, picked),
                            child: const Text('Xong'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
  } finally {
    hourCtrl.dispose();
    minCtrl.dispose();
    dayCtrl.dispose();
  }
}

/// Một bánh xe số cho giờ hoặc phút.
Widget _wheel({
  required FixedExtentScrollController controller,
  required int count,
  required int selected,
  required String Function(int) label,
  required ValueChanged<int> onChanged,
}) {
  return SizedBox(
    width: 76,
    height: 150,
    child: ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 46,
      diameterRatio: 1.5,
      perspective: 0.003,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (ctx, i) => Center(
          child: Text(
            label(i),
            style: TextStyle(
              fontSize: 26,
              fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500,
              color:
                  i == selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Nhãn nhỏ phía trên từng nhóm trong sheet chọn thời gian.
class _PickerLabel extends StatelessWidget {
  final String text;
  const _PickerLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      );
}

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Nhãn ngắn trên chip ngày: "Hôm nay" / "Mai" / thứ trong tuần.
String _dayTag(DateTime d, DateTime today) {
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Mai';
  return _weekdays[d.weekday - 1];
}

/// Câu xác nhận đầy đủ: "Mai (T2) · 08:30".
String _fullLabel(DateTime d, DateTime today) {
  final tag = _dayTag(d, today);
  final wd = _weekdays[d.weekday - 1];
  final hm = '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  final date = '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}';
  return tag == wd ? '$wd $date · $hm' : '$tag ($wd $date) · $hm';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Mở Google Maps ngoài app (không cần API key/quyền).
/// Ưu tiên [mapUrl] đã lưu; nếu trống thì tìm theo [address].
Future<void> openMap(
  BuildContext context, {
  String mapUrl = '',
  String address = '',
}) async {
  final link = mapUrl.trim();
  final raw = link.isNotEmpty
      ? link
      : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address.trim())}';
  try {
    final ok = await launchUrl(
      Uri.parse(raw),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) toast(context, 'Không mở được Google Maps');
  } catch (_) {
    if (context.mounted) toast(context, 'Link bản đồ không hợp lệ');
  }
}

/// Đầu bottom sheet: thanh kéo + tiêu đề CĂN GIỮA. Dùng chung cho mọi sheet
/// để tiêu đề không chỗ trái chỗ giữa.
class SheetHeader extends StatelessWidget {
  final String title;
  const SheetHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}

/// Chọn nguồn ảnh (chụp / thư viện) rồi nén, trả về đường dẫn local.
Future<String?> pickImage(BuildContext context, ImageService svc) async {
  // Bản web không lưu ảnh local (không có filesystem như máy) → báo rõ, khỏi
  // mở sheet chọn nguồn cho hụt.
  if (kIsWeb) {
    toast(context, 'Bản web chưa hỗ trợ tải ảnh — dùng app điện thoại để thêm ảnh.');
    return null;
  }
  final fromCamera = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader('Chọn ảnh'),
          ListTile(
            leading: const Icon(Icons.photo_camera, color: AppColors.primary),
            title: const Text('Chụp ảnh'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('Chọn từ thư viện'),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    ),
  );
  if (fromCamera == null) return null;
  return svc.pickAndCompress(fromCamera: fromCamera);
}

/// Ô chọn ảnh có gợi ý (icon máy ảnh + chữ) — dùng ở form thêm/sửa.
class ImagePickerBox extends StatelessWidget {
  final String? path;
  final VoidCallback onTap;
  final double size;
  const ImagePickerBox(
      {super.key, required this.path, required this.onTap, this.size = 100});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          LocalImage(path: path, size: size, radius: 16),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}
