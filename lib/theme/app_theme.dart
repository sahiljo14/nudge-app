// lib/theme/app_theme.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand — indigo primary (matches HTML concept) ─────────────
  static const primary          = Color(0xFF4A40E0);
  static const primaryDim       = Color(0xFF3D30D4);
  static const primaryContainer = Color(0xFF9795FF);
  static const onPrimary        = Color(0xFFF4F1FF);

  // ── Secondary — crimson ────────────────────────────────────────
  static const secondary          = Color(0xFFB80438);
  static const secondaryContainer = Color(0xFFFFC2C5);

  // ── Tertiary — amber ───────────────────────────────────────────
  static const tertiary     = Color(0xFFF8A010);
  static const tertiaryDark = Color(0xFF815100);

  // ── Light palette ─────────────────────────────────────────────
  static const lightSurface    = Color(0xFFF6F6FF);
  static const lightCard       = Color(0xFFFFFFFF);
  static const lightSurfaceLow = Color(0xFFEEF0FF);
  static const lightSurfaceMid = Color(0xFFE2E7FF);
  static const lightBorder     = Color(0xFFE2E7FF);
  static const lightText       = Color(0xFF272E42);
  static const lightSubtext    = Color(0xFF535B71);
  static const lightNavBg      = Color(0xFFF6F6FF);

  // ── Dark palette ──────────────────────────────────────────────
  static const darkSurface   = Color(0xFF0F1117);
  static const darkCard      = Color(0xFF1C1F2E);
  static const darkBorder    = Color(0xFF2A2D3E);
  static const darkText      = Color(0xFFEEEEF5);
  static const darkSubtext   = Color(0xFF6B6F84);
  static const darkNavBg     = Color(0xFF12151F);
  static const darkHeaderBg  = Color(0xFF12151F);
  static const darkSurfaceLow = Color(0xFF161926);

  // ── Urgency ────────────────────────────────────────────────────
  static const calm    = Color(0xFF059669); // emerald — done / plenty of time
  static const warning = Color(0xFFF8A010); // amber  — 1-2 days left
  static const alert   = Color(0xFFB80438); // crimson — <24 h
  static const danger  = Color(0xFFB80438); // crimson — overdue

  static Color urgencyColor(DateTime deadline) {
    final diff = deadline.difference(DateTime.now());
    if (diff.isNegative)   return danger;
    if (diff.inHours < 24) return alert;
    if (diff.inDays <= 2)  return warning;
    return calm;
  }

  // ── Subject palette ───────────────────────────────────────────
  static const List<Color> _subjectPalette = [
    Color(0xFF4A40E0), // indigo
    Color(0xFF5B8AF5), // blue
    Color(0xFFB80438), // crimson
    Color(0xFFAB47BC), // purple
    Color(0xFFF8A010), // amber
    Color(0xFFE91E8C), // pink
    Color(0xFF059669), // emerald
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

  // ── Helpers ───────────────────────────────────────────────────
  static Color surface(bool dark)     => dark ? darkSurface     : lightSurface;
  static Color card(bool dark)        => dark ? darkCard        : lightCard;
  static Color border(bool dark)      => dark ? darkBorder      : lightBorder;
  static Color text(bool dark)        => dark ? darkText        : lightText;
  static Color subtext(bool dark)     => dark ? darkSubtext     : lightSubtext;
  static Color navBg(bool dark)       => dark ? darkNavBg       : lightNavBg;
  static Color surfaceLow(bool dark)  => dark ? darkSurfaceLow  : lightSurfaceLow;
  static Color surfaceMid(bool dark)  => dark ? const Color(0xFF1E2236) : lightSurfaceMid;

  // ── Themes ────────────────────────────────────────────────────
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark  = brightness == Brightness.dark;
    final bg      = isDark ? darkSurface  : lightSurface;
    final cardC   = isDark ? darkCard     : lightCard;
    final textC   = isDark ? darkText     : lightText;
    final borderC = isDark ? darkBorder   : lightBorder;

    final base = GoogleFonts.manropeTextTheme().apply(
      bodyColor: textC,
      displayColor: textC,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: bg,
      ),
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? darkHeaderBg : lightCard,
        foregroundColor: textC,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.manrope(
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
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderC, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? darkCard : lightSurfaceLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          color: isDark ? darkSubtext : lightSubtext,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.manrope(
              fontSize: 15, fontWeight: FontWeight.w700),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
