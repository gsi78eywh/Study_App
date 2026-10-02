import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class AppColors {
  // Brand Primary & Accents
  static const Color primary = Color(0xFF6366F1); // Indigo
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color accent = Color(0xFF10B981); // Emerald
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color danger = Color(0xFFEF4444); // Rose/Red

  // Dark Theme Backgrounds & Surfaces
  static const Color darkBg = Color(0xFF0B1120); // Deep Slate 950
  static const Color darkCard = Color(0xFF1E293B); // Slate 800
  static const Color darkCardBorder = Color(0xFF334155); // Slate 700
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Light Theme Backgrounds & Surfaces
  static const Color lightBg = Color(0xFFF8FAFC); // Slate 50
  static const Color lightCard = Color(0xFFFFFFFF); // Pure White
  static const Color lightCardBorder = Color(0xFFE2E8F0); // Slate 200
  static const Color lightTextPrimary = Color(0xFF0F172A); // Slate 900
  static const Color lightTextSecondary = Color(0xFF64748B); // Slate 500
}

extension ThemeHelper on BuildContext {
  bool get isDarkMode => false;
  Color get surfaceColor => AppColors.lightCard;
  Color get cardBorderColor => AppColors.lightCardBorder;
  Color get textPrimary => AppColors.lightTextPrimary;
  Color get textSecondary => AppColors.lightTextSecondary;
  Color get secondaryBg => const Color(0xFFF1F5F9);
  Color get scaffoldBg => AppColors.lightBg;
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = ThemeData.light().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primaryDark,
        secondary: AppColors.accent,
        surface: AppColors.lightCard,
        error: AppColors.danger,
        onSurface: AppColors.lightTextPrimary,
      ),
      textTheme: GoogleFonts.outfitTextTheme(baseTextTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.lightTextPrimary),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.lightTextPrimary),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.lightTextPrimary),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.lightTextPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: AppColors.lightTextPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.lightTextSecondary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightCardBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryDark, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.lightTextSecondary),
        hintStyle: const TextStyle(color: AppColors.lightTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightCard,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.lightTextPrimary),
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      ),
      dividerColor: AppColors.lightCardBorder,
    );
  }

  // Enforce minimal student light theme without darkmode
  static ThemeData get darkTheme => lightTheme;
}
