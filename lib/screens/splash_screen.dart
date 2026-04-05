// lib/screens/splash_screen.dart

import 'package:flutter/material.dart';
import '../services/share_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
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
      backgroundColor: AppTheme.surface,
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
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white, size: 48,
                    ),
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
