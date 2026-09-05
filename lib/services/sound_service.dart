import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Âm thanh phản hồi thao tác. Dùng CHUNG một tiếng "cash" cho mọi sự kiện
/// đáng mừng: tạo đơn thành công, giao hàng thành công, có thông báo bắn về.
///
/// Static + 1 [AudioPlayer] dùng lại — không tạo player mới mỗi lần phát để
/// tránh rò tài nguyên khi bắn liên tục.
///
/// Mọi lỗi đều nuốt: âm thanh chỉ là phụ, KHÔNG được làm hỏng luồng nghiệp vụ
/// (máy tắt tiếng, thiếu codec, đang có cuộc gọi... đều không được ném lên UI).
class SoundService {
  SoundService._();

  static final AudioPlayer _player = AudioPlayer()
    // Phát xong thì nhả, không giữ loop.
    ..setReleaseMode(ReleaseMode.stop);

  static const _cashAsset = 'audio/cash_sound_effect.mp3';

  /// Tiếng "ting" tiền về. Không await được cũng không sao — gọi rồi quên.
  static Future<void> cash() async {
    try {
      // stop trước để bấm liên tục vẫn kêu lại từ đầu, không bị nuốt tiếng.
      await _player.stop();
      await _player.play(AssetSource(_cashAsset));
    } catch (e) {
      debugPrint('SoundService.cash error: $e');
    }
  }
}
