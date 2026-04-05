// lib/theme/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const primary   = Color(0xFF6C63FF); // violet accent
  static const surface   = Color(0xFFF7F7FB);
  static const card      = Color(0xFFFFFFFF);
  static const border    = Color(0xFFEAEAF0);

  // ── Urgency colour system ─────────────────────────────────────────────────
  static const calm      = Color(0xFF3B6D11); // 5+ days
  static const warning   = Color(0xFFBA7517); // 2-3 days
  static const alert     = Color(0xFF993C1D); // tomorrow
  static const danger    = Color(0xFFA32D2D); // overdue

  static Color urgencyColor(DateTime deadline) {
    final diff = deadline.difference(DateTime.now());
    if (diff.isNegative)        return danger;
    if (diff.inHours < 24)      return alert;
    if (diff.inDays <= 2)       return warning;
    return calm;
  }

  static Color urgencyBg(DateTime deadline) {
    return urgencyColor(deadline).withValues(alpha: 0.08);
  }

  // ── Subject colour palette ────────────────────────────────────────────────
  static const List<Color> _subjectPalette = [
    Color(0xFFD85A30), // coral
    Color(0xFF1D9E75), // teal
    Color(0xFF378ADD), // blue
    Color(0xFF7F77DD), // purple
    Color(0xFFBA7517), // amber
    Color(0xFFD4537E), // pink
    Color(0xFF639922), // green
    Color(0xFF888780), // gray
  ];

  static Color subjectColor(String subject) {
    if (subject.isEmpty) return const Color(0xFF888780);
    return _subjectPalette[subject.hashCode.abs() % _subjectPalette.length];
  }

  // ── Task type icons ────────────────────────────────────────────────────────
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

  // ── MaterialTheme ─────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: surface,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    ),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: card,
      foregroundColor: Color(0xFF1A1A2E),
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Color(0x12000000),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1A2E),
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(
          color: Color(0xFFAAABB5), fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}