import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_text.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/shop_info.dart';
import '../../services/db.dart';
import '../../widgets/common.dart';

/// Cài đặt phiếu giao hàng (§8): sửa tiêu đề cửa hàng + SĐT in trên phiếu.
///
/// Chỉ 2 trường — mọi thứ còn lại trên phiếu lấy từ đơn hàng nên không sửa tay
/// được. Lưu ở `meta/shop`, xem [Db.shopInfo].
class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});
  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  final _phone = TextEditingController();

  /// Tiêu đề cũ — không in trên phiếu nữa nên không hiện ô sửa, chỉ giữ để
  /// resave, tránh `saveShopInfo` ghi đè mất giá trị đang lưu.
  String _title = ShopInfo.defaultTitle;

  bool _loading = true;
  bool _saving = false;

  /// Ẩn giá trên phiếu in — xem [ShopInfo.hidePrices].
  bool _hidePrices = true;

  /// SĐT của Chủ mà Db đang dùng làm mặc định — hiện ở gợi ý dưới ô nhập để
  /// người dùng biết bỏ trống thì phiếu in số nào.
  String _ownerPhone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<Db>();
    // Đọc bản THÔ: ô nhập phải phản ánh đúng thứ đã lưu. Dùng `shopInfo()` thì
    // SĐT trống đã bị thay bằng số của Chủ, bấm Lưu là chép cứng số đó vào —
    // Chủ đổi số sau này phiếu vẫn in số cũ.
    final shop = await db.shopInfoRaw();
    final owner = await db.ownerPhone();
    if (!mounted) return;
    setState(() {
      _title = shop.title;
      _phone.text = shop.phone;
      _hidePrices = shop.hidePrices;
      _ownerPhone = owner;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<Db>().saveShopInfo(ShopInfo(
            title: _title,
            phone: _phone.text.trim(),
            hidePrices: _hidePrices,
          ));
      if (!mounted) return;
      toast(context, 'Đã lưu cài đặt phiếu');
      Navigator.pop(context);
    } catch (e) {
      debugPrint('SAVE-SHOP-INFO ERROR: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context,
          friendlyError(e, fallback: 'Lưu không thành công. Thử lại giúp tôi.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Cài đặt phiếu')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Chừa chỗ cho thanh điều hướng Android — nút "Lưu" nằm cuối trang.
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Thông tin in trên phiếu',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      _label('Số điện thoại'),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: phoneInputFormatters,
                        decoration: InputDecoration(
                          hintText: _ownerPhone.isEmpty
                              ? 'Nhập số điện thoại'
                              : _ownerPhone,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _ownerPhone.isEmpty
                            ? 'Bỏ trống thì phiếu lấy SĐT của tài khoản Chủ.'
                            : 'Bỏ trống thì phiếu in $_ownerPhone (SĐT tài khoản Chủ).',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Giá trên phiếu',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _hidePrices,
                        onChanged: (v) => setState(() => _hidePrices = v),
                        title: const Text('Ẩn giá trên phiếu in',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          _hidePrices
                              ? 'Phiếu chỉ có mặt hàng + số lượng. Không in đơn '
                                  'giá, thành tiền, tổng cộng, cần thu.'
                              : 'Phiếu in đầy đủ đơn giá, thành tiền, tổng '
                                  'cộng và số cần thu.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      const Divider(height: 20),
                      const Text(
                        'Đây chỉ là mặc định. Lúc mở phiếu vẫn bật/tắt được '
                        'cho riêng lần in đó. Nhân viên không có quyền xem '
                        'tiền thì luôn in phiếu không giá, không mở lại được.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Lưu'),
                ),
              ],
            ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
