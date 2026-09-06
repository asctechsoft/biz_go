import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'services/db.dart';
import 'services/image_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Thanh điều hướng dưới của hệ thống: cùng tông trắng với bottom nav của app,
  // icon màu tối cho dễ nhìn.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.white,
    ),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('vi_VN');
  runApp(const BizGoApp());
}

/// Bề rộng cột app trên web (px). Cỡ điện thoại lớn để layout không vỡ.
const double _kWebPhoneWidth = 460;

class BizGoApp extends StatefulWidget {
  const BizGoApp({super.key});
  @override
  State<BizGoApp> createState() => _BizGoAppState();
}

class _BizGoAppState extends State<BizGoApp> {
  final AuthProvider _auth = AuthProvider();
  late final GoRouter _router = buildRouter(_auth);

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        Provider(create: (_) => Db()),
        Provider(create: (_) => ImageService()),
      ],
      child: MaterialApp.router(
        title: 'BizGo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        // Khoá tiếng Việt cho mọi widget hệ thống (date/time picker, nút
        // Cancel/OK, menu sao chép-dán...). Thiếu phần này Flutter rơi về
        // tiếng Anh bất kể ngôn ngữ máy.
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final app = MediaQuery(
            // Ép giờ 24h cho time picker: app hiển thị giờ bằng
            // `fmtTime` (DateFormat 'HH:mm') ở mọi nơi, để picker chạy 12h
            // SÁNG/CHIỀU theo cài đặt máy là lệch với chính nó.
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            // Chạm ra ngoài ô nhập → bỏ focus, ẩn bàn phím (toàn app).
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: child,
            ),
          );
          // App thiết kế cho điện thoại. Trên web full màn, giữ UI ở cột rộng
          // cỡ điện thoại, canh giữa, nền xám 2 bên như khung máy — user khỏi
          // phải thu nhỏ cửa sổ. CHỈ web (`kIsWeb`); mobile trả app nguyên vẹn.
          if (!kIsWeb) return app;
          return ColoredBox(
            color: const Color(0xFFE6E7EB),
            child: Center(
              child: SizedBox(
                width: _kWebPhoneWidth,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: app,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
