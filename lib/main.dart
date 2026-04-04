import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/add_task_screen.dart';
import 'parser/share_handler.dart';

void main() {
  runApp(const StudentTaskApp());
}

class StudentTaskApp extends StatelessWidget {
  const StudentTaskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nudge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        cardColor: Colors.white,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      home: const _StartupRouter(),
    );
  }
}

class _StartupRouter extends StatefulWidget {
  const _StartupRouter();

  @override
  State<_StartupRouter> createState() => _StartupRouterState();
}

class _StartupRouterState extends State<_StartupRouter> {
  @override
  void initState() {
    super.initState();
    _handleSharedText();
  }

  Future<void> _handleSharedText() async {
    final sharedText = await ShareHandler.getSharedText();
    if (sharedText != null && sharedText.isNotEmpty && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AddTaskScreen(initialRawText: sharedText),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}