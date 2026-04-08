// lib/services/user_prefs.dart
// Local-only storage for user preferences and onboarding state.
// All methods are static; no singleton needed.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class UserPrefs {
  static const _keySetupCompleted = 'setup_completed';
  static const _keyUserName       = 'user_name';
  static const _keyUserSubjects   = 'user_subjects';

  // ── Onboarding gate ───────────────────────────────────────────────────────

  static Future<bool> getSetupCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keySetupCompleted) ?? false;
  }

  static Future<void> setSetupCompleted(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keySetupCompleted, value);
  }

  /// Clears the setup flag so onboarding will show again on next launch.
  static Future<void> resetOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keySetupCompleted);
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
}
