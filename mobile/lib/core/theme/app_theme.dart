import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

class AppColors {
  // Natural, Eye-Friendly Botanical & Paper Palette (Reduced Blue-Light Glare)
  static const Color primary = Color(0xFF2E7D5B); // Natural Sage Emerald
  static const Color primaryDark = Color(0xFF216346); // Deep Botanical Green
  static const Color primaryLight = Color(0xFF52A37E); // Soft Mint Sage
  static const Color accent = Color(0xFF0D9488); // Calm Teal
  static const Color warning = Color(0xFFD97706); // Warm Ochre Amber
  static const Color danger = Color(0xFFDC2626); // Soft Crimson

  // Dark Theme Backgrounds & Surfaces (Comfort Forest-Slate)
  static const Color darkBg = Color(0xFF111916); // Deep Botanical Slate
  static const Color darkCard = Color(0xFF182420); // Elevated Moss Slate
  static const Color darkCardBorder = Color(0xFF2A3D36); // Muted Sage Border
  static const Color darkTextPrimary = Color(0xFFECF3EE); // Soft Warm White
  static const Color darkTextSecondary = Color(0xFF9BB0A5); // Muted Sage Grey

  // Light Theme Backgrounds & Surfaces (Warm Eye-Care Alabaster Paper)
  static const Color lightBg = Color(0xFFF3F6F2); // Soft Sage Alabaster
  static const Color lightCard = Color(0xFFFAFAF7); // Warm Book Paper (No harsh white glare)
  static const Color lightCardBorder = Color(0xFFD8E2DC); // Subtle Botanical Border
  static const Color lightTextPrimary = Color(0xFF182620); // Deep Charcoal Forest
  static const Color lightTextSecondary = Color(0xFF52665B); // Earthy Slate
}

extension ThemeHelper on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  Color get surfaceColor => isDarkMode ? AppColors.darkCard : AppColors.lightCard;
  Color get cardBorderColor => isDarkMode ? AppColors.darkCardBorder : AppColors.lightCardBorder;
  Color get textPrimary => isDarkMode ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary => isDarkMode ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get secondaryBg => isDarkMode ? const Color(0xFF15201C) : const Color(0xFFE9EFEA);
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
