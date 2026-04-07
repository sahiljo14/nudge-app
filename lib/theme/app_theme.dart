// lib/theme/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand — teal accent matching reference UI ─────────────────
  static const primary     = Color(0xFF2DC9A8); // teal
  static const primaryDark = Color(0xFF25A88E); // darker teal
  static const accent      = Color(0xFF4CAF50); // green accent

  // ── Light palette ─────────────────────────────────────────────
  static const lightSurface  = Color(0xFFF4F6F9);
  static const lightCard     = Color(0xFFFFFFFF);
  static const lightBorder   = Color(0xFFEAECF2);
  static const lightText     = Color(0xFF1A1D2E);
  static const lightSubtext  = Color(0xFF8A8FA8);
  static const lightNavBg    = Color(0xFFFFFFFF);

  // ── Dark palette (reference screenshots) ─────────────────────
  static const darkSurface   = Color(0xFF0F1117);
  static const darkCard      = Color(0xFF1C1F2E);
  static const darkBorder    = Color(0xFF2A2D3E);
  static const darkText      = Color(0xFFEEEEF5);
  static const darkSubtext   = Color(0xFF6B6F84);
  static const darkNavBg     = Color(0xFF12151F);
  static const darkHeaderBg  = Color(0xFF12151F);

  // ── Urgency ────────────────────────────────────────────────────
  static const calm    = Color(0xFF2DC9A8);
  static const warning = Color(0xFFFFB627);
  static const alert   = Color(0xFFFF7043);
  static const danger  = Color(0xFFE53935);

  static Color urgencyColor(DateTime deadline) {
    final diff = deadline.difference(DateTime.now());
    if (diff.isNegative)   return danger;
    if (diff.inHours < 24) return alert;
    if (diff.inDays <= 2)  return warning;
    return calm;
  }

  // ── Subject palette ───────────────────────────────────────────
  static const List<Color> _subjectPalette = [
    Color(0xFF2DC9A8), // teal
    Color(0xFF5B8AF5), // blue
    Color(0xFFFF7043), // orange
    Color(0xFFAB47BC), // purple
    Color(0xFFFFB627), // amber
    Color(0xFFE91E8C), // pink
    Color(0xFF26A69A), // teal-green
    Color(0xFF78909C), // slate
  ];

  static Color subjectColor(String subject) {
    if (subject.isEmpty) return const Color(0xFF78909C);
    return _subjectPalette[subject.hashCode.abs() % _subjectPalette.length];
  }

  static IconData taskTypeIcon(String type) {
    switch (type) {
      case 'exam':       return Icons.school_rounded;
      case 'submission': return Icons.upload_file_rounded;
      case 'reminder':   return Icons.notifications_rounded;
      case 'meeting':    return Icons.groups_rounded;
      case 'assignment': return Icons.assignment_rounded;
      default:           return Icons.task_alt_rounded;
    }
  }

  // ── Helper — surface/card/text based on brightness ────────────
  static Color surface(bool dark)  => dark ? darkSurface  : lightSurface;
  static Color card(bool dark)     => dark ? darkCard      : lightCard;
  static Color border(bool dark)   => dark ? darkBorder    : lightBorder;
  static Color text(bool dark)     => dark ? darkText      : lightText;
  static Color subtext(bool dark)  => dark ? darkSubtext   : lightSubtext;
  static Color navBg(bool dark)    => dark ? darkNavBg     : lightNavBg;

  // ── Light theme ───────────────────────────────────────────────
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg     = isDark ? darkSurface : lightSurface;
    final cardC  = isDark ? darkCard    : lightCard;
    final textC  = isDark ? darkText    : lightText;
    final borderC= isDark ? darkBorder  : lightBorder;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: bg,
      ),
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkHeaderBg : lightCard,
        foregroundColor: textC,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textC,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardC,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderC, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardC,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderC),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: isDark ? darkSubtext : lightSubtext, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? primary : Colors.grey),
        trackColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected)
                ? primary.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.3)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? darkCard : lightText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
