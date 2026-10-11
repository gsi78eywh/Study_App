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
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get surfaceColor => isDarkMode ? AppColors.darkCard : AppColors.lightCard;
  Color get cardBorderColor => isDarkMode ? AppColors.darkCardBorder : AppColors.lightCardBorder;
  Color get textPrimary => isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get secondaryBg => isDarkMode ? const Color(0xFF131D31) : const Color(0xFFF1F5F9);
  Color get scaffoldBg => isDarkMode ? AppColors.darkBg : AppColors.lightBg;
}

class AppTheme {
  static ThemeData get lightTheme => buildTheme(isDark: false);
  static ThemeData get darkTheme => buildTheme(isDark: true);

  static ThemeData buildTheme({required bool isDark, bool useDyslexicFont = false}) {
    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = useDyslexicFont
        ? GoogleFonts.lexendTextTheme(baseTextTheme).copyWith(
            displayLarge: GoogleFonts.lexend(fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            displayMedium: GoogleFonts.lexend(fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            headlineMedium: GoogleFonts.lexend(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            titleLarge: GoogleFonts.lexend(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            bodyLarge: GoogleFonts.lexend(fontSize: 16, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            bodyMedium: GoogleFonts.lexend(fontSize: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          )
        : GoogleFonts.outfitTextTheme(baseTextTheme).copyWith(
            displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            bodyLarge: GoogleFonts.inter(fontSize: 16, color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            bodyMedium: GoogleFonts.inter(fontSize: 14, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          );

    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final primary = isDark ? AppColors.primary : AppColors.primaryDark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: isDark
          ? const ColorScheme.dark(
              primary: AppColors.primary,
              secondary: AppColors.accent,
              surface: AppColors.darkCard,
              error: AppColors.danger,
              onSurface: AppColors.darkTextPrimary,
            )
          : const ColorScheme.light(
              primary: AppColors.primaryDark,
              secondary: AppColors.accent,
              surface: AppColors.lightCard,
              error: AppColors.danger,
              onSurface: AppColors.lightTextPrimary,
            ),
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF475569) : border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? const Color(0xFF475569) : border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.primaryLight : AppColors.primaryDark, width: 2),
        ),
        labelStyle: TextStyle(color: isDark ? const Color(0xFFCBD5E1) : textSecondary, fontSize: 14),
        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: (useDyslexicFont ? GoogleFonts.lexend : GoogleFonts.inter)(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: isDark ? 2 : 1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        elevation: 0,
        titleTextStyle: (useDyslexicFont ? GoogleFonts.lexend : GoogleFonts.outfit)(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      dividerColor: border,
    );
  }
}
