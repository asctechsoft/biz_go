import 'dart:io';
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
            ? Image.file(File(path!), fit: BoxFit.cover)
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
        backgroundImage: FileImage(File(imagePath!)),
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

/// Chọn **ngày + giờ** trong một lượt (date picker rồi time picker).
///
/// Trả `null` nếu người dùng huỷ ở bất kỳ bước nào — huỷ giữa chừng KHÔNG
/// được coi là đã chọn, kẻo bấm nhầm là ghi đè mất giờ cũ.
///
/// Tiếng Việt + khung 24h do `MaterialApp` khoá sẵn (`locale: vi` +
/// `alwaysUse24HourFormat`), ở đây không cần cấu hình lại.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  String helpText = 'Chọn ngày',
}) async {
  final now = DateTime.now();
  final base = initial ?? now;
  final day = await showDatePicker(
    context: context,
    initialDate: base,
    // Cho lùi 1 ngày phòng khi nhập bù đơn hôm qua; xa hơn thì vô nghĩa.
    firstDate: DateTime(now.year, now.month, now.day - 1),
    lastDate: DateTime(now.year + 1, now.month, now.day),
    helpText: helpText,
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
    helpText: 'Chọn giờ',
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
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
