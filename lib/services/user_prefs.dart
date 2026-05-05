// lib/services/user_prefs.dart
// Local-only storage for user preferences and onboarding state.
// All methods are static; no singleton needed.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserPrefs {
  static const _keySetupCompleted   = 'setup_completed';
  static const _keyUserName         = 'user_name';
  static const _keyUserSubjects     = 'user_subjects';
  static const _keyProfileImagePath = 'profile_image_path';
  static const _keyTotalXp          = 'total_xp';
  static const _keyThemeMode        = 'theme_mode';

  // ── Onboarding gate ───────────────────────────────────────────────────────

  static Future<bool> getSetupCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keySetupCompleted) ?? false;
  }

  /// Tri-state: null = never set (fresh install), true = done, false = user reset.
  static Future<bool?> getSetupCompletedRaw() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keySetupCompleted);
  }

  static Future<void> setSetupCompleted(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keySetupCompleted, value);
  }

  /// Marks the flag false so onboarding re-runs on next launch — even if the
  /// user already has tasks (the splash gate's "existing user" auto-skip only
  /// fires when the flag is absent).
  static Future<void> resetOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keySetupCompleted, false);
  }

  // ── User profile ──────────────────────────────────────────────────────────

  static Future<String> getUserName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyUserName) ?? '';
  }

  static Future<void> setUserName(String value) async {
    final p = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await p.remove(_keyUserName);
    } else {
      await p.setString(_keyUserName, value);
    }
  }

  static Future<String?> getProfileImagePath() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyProfileImagePath);
  }

  static Future<void> setProfileImagePath(String? path) async {
    final p = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await p.remove(_keyProfileImagePath);
    } else {
      await p.setString(_keyProfileImagePath, path);
    }
  }

  static Future<List<String>> getUserSubjects() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_keyUserSubjects);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setUserSubjects(List<String> subjects) async {
    final p = await SharedPreferences.getInstance();
    if (subjects.isEmpty) {
      await p.remove(_keyUserSubjects);
    } else {
      await p.setString(_keyUserSubjects, jsonEncode(subjects));
    }
  }

  // ── XP (permanent, never decreases) ──────────────────────────────────────

  static Future<int> getTotalXp() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyTotalXp) ?? 0;
  }

  static Future<void> incrementTotalXp(int amount) async {
    final p = await SharedPreferences.getInstance();
    final current = p.getInt(_keyTotalXp) ?? 0;
    await p.setInt(_keyTotalXp, current + amount);
  }

  // ── Theme mode persistence ────────────────────────────────────────────────────

  /// Returns 'dark', 'light', or null (system default).
  static Future<String?> getThemeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_keyThemeMode);
  }

  static Future<void> setThemeMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyThemeMode, mode);
  }
}
