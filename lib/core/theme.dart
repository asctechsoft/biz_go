import 'package:flutter/material.dart';

/// BizGo brand palette — dark green per the mockups.
class AppColors {
  static const Color primary = Color(0xFF1B7A43); // header/CTA green
  static const Color primaryDark = Color(0xFF0F5A30);
  static const Color primaryLight = Color(0xFFE7F3EC);
  static const Color danger = Color(0xFFD64545);
  static const Color warning = Color(0xFFE8A13A);
  static const Color info = Color(0xFF3A7BD6);
  static const Color success = Color(0xFF2E9E5B);
  static const Color bg = Color(0xFFF4F6F5);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1C2620);
  static const Color textSecondary = Color(0xFF6B7A72);
  static const Color border = Color(0xFFE2E8E4);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
        // Card bo góc 14 nhưng mặc định KHÔNG cắt nội dung, nên hiệu ứng chạm
        // của ListTile bên trong vẽ theo hình chữ nhật và đè ra 4 góc bo.
        clipBehavior: Clip.antiAlias,
      ),
      // Bo góc trên + CẮT nội dung theo đúng khung đó. Thiếu `clipBehavior`
      // thì hiệu ứng chạm của ListTile vẽ theo hình chữ nhật, tràn ra ngoài
      // hai góc bo — nhìn như bấm lem ra mép sheet.
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        insetPadding: const EdgeInsets.all(16), // cách mép màn hình 16px
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
