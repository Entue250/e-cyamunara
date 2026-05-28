// lib/presentation/theme/app_theme.dart
//
// ─── CENTRALIZED THEME ────────────────────────────────────────────────────────
// All colors, text styles, and spacing used across every screen.
// Import this file in any screen: import '../theme/app_theme.dart';
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ── BRAND COLORS ──────────────────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Primary palette — RNP Blue & Gold
  static const Color primaryBlue = Color(0xFF003087); // Main blue
  static const Color darkBlue = Color(0xFF001F5B); // Darker blue for headers
  static const Color gold = Color(0xFFFFD700); // Gold accent
  static const Color darkGold = Color(
    0xFFB8860B,
  ); // Darker gold for text on light

  // Status colors
  static const Color success = Color(0xFF2E7D32); // Green — WINNING / ACTIVE
  static const Color warning = Color(0xFFE65100); // Orange — ENDING SOON
  static const Color error = Color(0xFFC62828); // Red — OUTBID / SUSPENDED
  static const Color info = Color(0xFF1565C0); // Blue — general info

  // Background
  static const Color background = Color(0xFFF5F7FA); // Light grey page bg
  static const Color surface = Color(0xFFFFFFFF); // White cards
  static const Color surfaceGrey = Color(0xFFF0F2F5); // Input field background

  // Text
  static const Color textPrimary = Color(0xFF0D1B3E); // Dark navy text
  static const Color textSecondary = Color(0xFF6B7280); // Grey subtitle text
  static const Color textHint = Color(0xFFADB5BD); // Placeholder text

  // Border
  static const Color border = Color(0xFFE5E7EB); // Card/field borders
  static const Color divider = Color(0xFFEEEFF1); // Dividers
}

// ── TEXT STYLES ───────────────────────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  // Display — big headings
  static const TextStyle displayLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  // Labels — ALL CAPS labels above input fields
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: 1.0,
  );
  static const TextStyle labelGold = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.darkGold,
    letterSpacing: 1.0,
  );

  // Price / money
  static const TextStyle price = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.darkGold,
  );
  static const TextStyle priceLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: AppColors.darkGold,
  );

  // Button text
  static const TextStyle button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 1.2,
  );
}

// ── SPACING ───────────────────────────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
}

// ── BORDER RADIUS ─────────────────────────────────────────────────────────────
class AppRadius {
  AppRadius._();
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 100.0;
}

// ── THEME DATA ────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily:
        'Poppins', // Uses system fallback if Poppins not added to pubspec
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
      secondary: AppColors.gold,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),

    // Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: AppTextStyles.button,
      ),
    ),

    // Outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryBlue,
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),

    // Text fields
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceGrey,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
    ),

    // Cards
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),

    // Bottom navigation
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.primaryBlue,
      unselectedItemColor: AppColors.textSecondary,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}

// ── LOADING WIDGET ─────────────────────────────────────────────────────────────
// Pulsing RNP logo used on every loading state (replaces CircularProgressIndicator).
class RnpLoadingWidget extends StatefulWidget {
  const RnpLoadingWidget({super.key, this.size = 72.0});
  final double size;

  @override
  State<RnpLoadingWidget> createState() => _RnpLoadingWidgetState();
}

class _RnpLoadingWidgetState extends State<RnpLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: FadeTransition(
          opacity: _fade,
          child: Image.asset(
            'assets/images/RNP_logo.png',
            width: widget.size,
            height: widget.size,
            errorBuilder: (_, _, _) => Icon(
              Icons.shield,
              size: widget.size,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
}
