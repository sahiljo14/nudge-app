// lib/screens/onboarding_screen.dart
// First-run onboarding — 3 lightweight steps.
// Never shown to existing users who already have tasks (handled in splash_screen).

import 'dart:io' as import_dart_io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/user_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/photo_source_sheet.dart';

class OnboardingScreen extends StatefulWidget {
  /// The screen to navigate to after setup completes or is skipped.
  final Widget destination;
  const OnboardingScreen({super.key, required this.destination});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;

  // Step 1 — name
  final _nameCtrl = TextEditingController();

  // Step 3 — photo
  String? _selectedPhotoPath;

  // Step 2 — subjects
  static const _predefined = [
    'Maths', 'Physics', 'Chemistry', 'English',
    'Computer Science', 'Data Structures',
    'Operating Systems', 'DBMS', 'Networks', 'Mechanics',
  ];
  final Set<String> _selected = {};
  final List<String> _custom  = [];
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) {
      HapticFeedback.selectionClick();
      setState(() => _step--);
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final name     = _nameCtrl.text.trim();
    final subjects = _selected.toList();
    if (name.isNotEmpty)            await UserPrefs.setUserName(name);
    if (subjects.isNotEmpty)        await UserPrefs.setUserSubjects(subjects);
    if (_selectedPhotoPath != null) await UserPrefs.setProfileImagePath(_selectedPhotoPath);
    await UserPrefs.setSetupCompleted(true);
    _navigate();
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Save whatever has been entered so far, then mark complete.
    final name     = _nameCtrl.text.trim();
    final subjects = _selected.toList();
    if (name.isNotEmpty)     await UserPrefs.setUserName(name);
    if (subjects.isNotEmpty) await UserPrefs.setUserSubjects(subjects);
    await UserPrefs.setSetupCompleted(true);
    _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, a, __) => widget.destination,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    ));
  }

  // ── Subject chip helpers ──────────────────────────────────────────────────

  void _toggleSubject(String s) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(s)) _selected.remove(s); else _selected.add(s);
    });
  }

  void _addCustomSubject() {
    final s = _customCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      _custom.add(s);
      _selected.add(s);
      _customCtrl.clear();
    });
  }

  // ── Photo picker ──────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await PhotoSourceSheet.show(context, isDark: isDark);
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: source, imageQuality: 85);
    if (photo != null && mounted) {
      setState(() => _selectedPhotoPath = photo.path);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final botPad  = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      // Ensure keyboard doesn't squish layout
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ProgressDots(step: _step, total: 4, isDark: isDark),
                TextButton(
                  onPressed: _saving ? null : _skip,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    minimumSize: const Size(44, 44),
                  ),
                  child: Text('Skip for now',
                      style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppTheme.subtext(isDark))),
                ),
              ],
            ),
          ),

          // ── Step content ─────────────────────────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(isDark),
              ),
            ),
          ),

          // ── Bottom buttons ────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, botPad + 16),
            child: _buildButtons(isDark),
          ),
        ]),
      ),
    );
  }

  Widget _buildStep(bool isDark) {
    switch (_step) {
      case 0: return _StepWelcome(isDark: isDark);
      case 1: return _StepName(ctrl: _nameCtrl, isDark: isDark);
      case 2: return _StepSubjects(
        predefined: _predefined,
        custom: _custom,
        selected: _selected,
        customCtrl: _customCtrl,
        onToggle: _toggleSubject,
        onAddCustom: _addCustomSubject,
        isDark: isDark,
      );
      case 3: return _StepPhoto(
        selectedPath: _selectedPhotoPath,
        onPick: _pickPhoto,
        onRemove: () => setState(() => _selectedPhotoPath = null),
        isDark: isDark,
      );
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildButtons(bool isDark) {
    final isLast = _step == 3;
    final isFirst = _step == 0;

    if (isFirst) {
      return SizedBox(
        width: double.infinity,
        child: _PrimaryButton(
          label: 'Get started',
          icon: Icons.arrow_forward_rounded,
          onPressed: _saving ? null : _next,
        ),
      );
    }

    return Row(children: [
      // Back
      SizedBox(
        width: 44, height: 52,
        child: GestureDetector(
          onTap: _back,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: Icon(Icons.arrow_back_rounded,
                color: AppTheme.subtext(isDark), size: 22),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _PrimaryButton(
          label: isLast ? 'Finish setup' : 'Continue',
          icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
          onPressed: _saving ? null : _next,
          loading: _saving && isLast,
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// STEP WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _StepWelcome extends StatelessWidget {
  final bool isDark;
  const _StepWelcome({required this.isDark});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand logo
        SvgPicture.asset(
          isDark
              ? 'assets/logos/dark_mode.svg'
              : 'assets/logos/light_mode.svg',
          width: 80,
          height: 80,
        ),
        const SizedBox(height: 28),
        Text('Welcome to Nudge',
            style: GoogleFonts.manrope(
              fontSize: 30, fontWeight: FontWeight.w800,
              letterSpacing: -0.8, height: 1.1,
              color: AppTheme.text(isDark))),
        const SizedBox(height: 12),
        Text(
          'Paste a WhatsApp message, screenshot caption, or plain text — '
          'Nudge reads the deadline and sets a reminder for you. '
          'Fully offline, no account needed.',
          style: GoogleFonts.manrope(
            fontSize: 15, fontWeight: FontWeight.w500, height: 1.55,
            color: AppTheme.subtext(isDark)),
        ),
        const SizedBox(height: 28),
        // Three value-prop bullets
        ...[
          (Icons.auto_awesome_rounded,  'Understands Hinglish & Marathi'),
          (Icons.notifications_rounded, 'Reminders 1 day, 2 hrs, at deadline'),
          (Icons.folder_rounded,        'Attach docs straight from WhatsApp'),
        ].map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.$1, color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(item.$2,
                style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDark)))),
          ]),
        )),
      ],
    ),
  );
}

class _StepName extends StatelessWidget {
  final TextEditingController ctrl;
  final bool isDark;
  const _StepName({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What should we\ncall you?',
          style: GoogleFonts.manrope(
            fontSize: 28, fontWeight: FontWeight.w800,
            letterSpacing: -0.6, height: 1.15,
            color: AppTheme.text(isDark))),
      const SizedBox(height: 8),
      Text('Optional — you can always set this later.',
          style: GoogleFonts.manrope(
            fontSize: 13, color: AppTheme.subtext(isDark))),
      const SizedBox(height: 24),
      Container(
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.manrope(
            fontSize: 16, fontWeight: FontWeight.w600,
            color: AppTheme.text(isDark)),
          decoration: InputDecoration(
            hintText: 'Alex, Priya, Rohan…',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16),
            hintStyle: GoogleFonts.manrope(
              fontSize: 16, color: AppTheme.subtext(isDark)),
          ),
        ),
      ),
    ]),
  );
}

class _StepSubjects extends StatelessWidget {
  final List<String> predefined, custom;
  final Set<String> selected;
  final TextEditingController customCtrl;
  final void Function(String) onToggle;
  final VoidCallback onAddCustom;
  final bool isDark;

  const _StepSubjects({
    required this.predefined, required this.custom, required this.selected,
    required this.customCtrl, required this.onToggle, required this.onAddCustom,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What are you\nstudying?',
          style: GoogleFonts.manrope(
            fontSize: 28, fontWeight: FontWeight.w800,
            letterSpacing: -0.6, height: 1.15,
            color: AppTheme.text(isDark))),
      const SizedBox(height: 8),
      Text('Select subjects to help Nudge tag your tasks.',
          style: GoogleFonts.manrope(
            fontSize: 13, color: AppTheme.subtext(isDark))),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: [...predefined, ...custom].map((s) {
          final isOn = selected.contains(s);
          return GestureDetector(
            onTap: () => onToggle(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isOn
                    ? AppTheme.primary
                    : AppTheme.surfaceLow(isDark),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isOn
                      ? AppTheme.primary
                      : AppTheme.border(isDark),
                ),
              ),
              child: Text(s,
                  style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: isOn
                        ? Colors.white
                        : AppTheme.subtext(isDark))),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      // Custom subject add row
      Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.card(isDark),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border(isDark)),
            ),
            child: TextField(
              controller: customCtrl,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.manrope(
                fontSize: 14, color: AppTheme.text(isDark)),
              decoration: InputDecoration(
                hintText: 'Add a subject…',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                hintStyle: GoogleFonts.manrope(
                  fontSize: 14, color: AppTheme.subtext(isDark)),
              ),
              onSubmitted: (_) => onAddCustom(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onAddCustom,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_rounded,
                color: Colors.white, size: 22),
          ),
        ),
      ]),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _ProgressDots extends StatelessWidget {
  final int step, total;
  final bool isDark;
  const _ProgressDots(
      {required this.step, required this.total, required this.isDark});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(total, (i) {
      final active = i == step;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(right: 6),
        width: active ? 20 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primary
              : AppTheme.surfaceLow(isDark),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }),
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: loading
          ? const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label,
                  style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Icon(icon, size: 18),
            ]),
    ),
  );
}

// ── Step 3: Profile photo ─────────────────────────────────────────────────────

class _StepPhoto extends StatelessWidget {
  final String? selectedPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool isDark;
  const _StepPhoto({
    required this.selectedPath,
    required this.onPick,
    required this.onRemove,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = selectedPath != null && selectedPath!.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add a\nprofile photo',
            style: GoogleFonts.manrope(
              fontSize: 28, fontWeight: FontWeight.w800,
              letterSpacing: -0.6, height: 1.15,
              color: AppTheme.text(isDark))),
        const SizedBox(height: 8),
        Text('Optional — you can always change this later.',
            style: GoogleFonts.manrope(
              fontSize: 13, color: AppTheme.subtext(isDark))),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: onPick,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.10),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                image: hasPhoto
                    ? DecorationImage(
                        image: FileImage(import_dart_io.File(selectedPath!)),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: hasPhoto
                  ? null
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_a_photo_rounded,
                          size: 32, color: AppTheme.primary),
                      const SizedBox(height: 6),
                      Text('Tap to add',
                          style: GoogleFonts.manrope(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ]),
            ),
          ),
        ),
        if (hasPhoto) ...[
          const SizedBox(height: 16),
          Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_camera_rounded, size: 16),
                label: Text('Change',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: onRemove,
                child: Text('Remove',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: const Color(0xFFE53935))),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

