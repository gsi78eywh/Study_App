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
  static const Color darkBg = Color(0xFF0F172A); // Slate 900
  static const Color darkCard = Color(0xFF1E293B); // Slate 800
  static const Color darkCardBorder = Color(0xFF334155); // Slate 700
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Light Theme
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
}

class AppTheme {
  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.darkCard,
        error: AppColors.danger,
      ),
      textTheme: GoogleFonts.outfitTextTheme(baseTextTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.darkTextPrimary),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: AppColors.darkTextPrimary),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: AppColors.darkTextPrimary),
        bodyLarge: GoogleFonts.inter(fontSize: 16, color: AppColors.darkTextPrimary),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.darkTextSecondary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkCardBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
        hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 2,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBg,
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.darkTextPrimary),
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      ),
    );
  }
}
