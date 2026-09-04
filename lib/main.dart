import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        // Chạm ra ngoài ô nhập → bỏ focus, ẩn bàn phím (toàn app).
        builder: (context, child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
      ),
    );
  }
}
