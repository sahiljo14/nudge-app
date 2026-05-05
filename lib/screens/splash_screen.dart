// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../database/db_helper.dart';
import '../services/share_service.dart';
import '../services/user_prefs.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'text_import_screen.dart';
import 'doc_import_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fade = CurvedAnimation(parent: _ctrl,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1500), _route);
  }

  Future<void> _route() async {
    if (!mounted) return;
    final data = await ShareService.getSharedData();
    if (!mounted) return;

    Widget dest;
    if (data.hasText) {
      dest = TextImportScreen(sharedText: data.text!);
    } else if (data.hasFile) {
      // usablePath is the locally copied path (works for content:// from
      // WhatsApp, Gmail, Drive, etc.); falls back to raw URI for file:// URIs.
      final path = data.usablePath ?? data.fileUri!;
      dest = DocImportScreen(
        fileUri:  path,
        mimeType: data.fileMime ?? '',
      );
    } else {
      dest = const HomeScreen();
    }

    // ── Onboarding gate ────────────────────────────────────────────────────
    // Only show onboarding on a true fresh install. Existing users who have
    // tasks in the DB are silently marked as setup-complete so they never see
    // the onboarding flow unexpectedly.
    final setupRaw = await UserPrefs.getSetupCompletedRaw();
    if (!mounted) return;
    if (setupRaw != true) {
      // Auto-skip onboarding only on a true fresh install (key absent) when
      // the user already has tasks — never when the user explicitly reset.
      if (setupRaw == null) {
        final existingTasks = await DBHelper.instance.getAllTasks();
        if (!mounted) return;
        if (existingTasks.isNotEmpty) {
          await UserPrefs.setSetupCompleted(true);
        } else {
          dest = OnboardingScreen(destination: dest);
        }
      } else {
        // Explicit false → user-requested reset. Always show onboarding.
        dest = OnboardingScreen(destination: dest);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, a, __) => dest,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 350),
    ));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'assets/logos/dark_mode.svg'
                        : 'assets/logos/light_mode.svg',
                    width: 88,
                    height: 88,
                  ),
                  const SizedBox(height: 20),
                  const Text('Nudge',
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A2E),
                          letterSpacing: -1.5)),
                  const SizedBox(height: 6),
                  Text('Never miss what matters',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w400)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
