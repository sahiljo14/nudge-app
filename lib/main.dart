// lib/main.dart

import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/user_prefs.dart';
import 'theme/app_theme.dart';

// ── Global theme notifier ─────────────────────────────────────────────────────
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore persisted theme preference before first frame.
  final savedTheme = await UserPrefs.getThemeMode();
  if (savedTheme == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  }
  // Start notification init in background — does not block first frame.
  // The splash screen provides a 1500ms buffer before any task can be created,
  // and every schedule path guards with `if (!_ready) await init()`.
  NotificationService.instance.init();
  runApp(const NudgeApp());
}

class NudgeApp extends StatelessWidget {
  const NudgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'Nudge',
        debugShowCheckedModeBanner: false,
        theme:      AppTheme.light,
        darkTheme:  AppTheme.dark,
        themeMode:  mode,
        home: const SplashScreen(),
      ),
    );
  }
}
