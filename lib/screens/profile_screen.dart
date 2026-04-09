// lib/screens/profile_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../services/user_prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/nudge_primitives.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Task> _allTasks = [];
  String _userName    = '';
  List<String> _userSubjects = [];
  String? _profileImagePath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      DBHelper.instance.getAllTasks(),
      UserPrefs.getUserName(),
      UserPrefs.getUserSubjects(),
      UserPrefs.getProfileImagePath(),
    ]);
    if (mounted) {
      setState(() {
        _allTasks          = results[0] as List<Task>;
        _userName          = results[1] as String;
        _userSubjects      = results[2] as List<String>;
        _profileImagePath  = results[3] as String?;
        _loading           = false;
      });
    }
  }

  Future<void> _openEditProfile(bool isDark) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialName:      _userName,
        initialSubjects:  _userSubjects,
        initialImagePath: _profileImagePath,
        isDark:           isDark,
      ),
    );
    // Reload in case the user saved changes.
    _loadData();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Returns the calendar day a done task should count toward.
  /// Uses real completedAt when available; falls back to deadline for
  /// pre-migration rows that have isDone=true but completedAt=null.
  DateTime? _completionDay(task) {
    if (!task.isDone) return null;
    final dt = task.completedAt ?? task.deadline;
    return DateTime(dt.year, dt.month, dt.day);
  }

  // ── Computed properties ──────────────────────────────────────────────────

  int get _totalDone => _allTasks.where((t) => t.isDone).length;

  int get _xp => _totalDone * 10;

  int get _level => _xp ~/ 100 + 1;

  double get _xpProgressInLevel => (_xp % 100) / 100.0;

  int get _currentStreak {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int streak = 0;
    final todayHas = _allTasks.any((t) {
      final d = _completionDay(t);
      return d != null && _sameDay(d, today);
    });
    if (todayHas) streak++;
    for (int i = 1; i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      final has = _allTasks.any((t) {
        final d = _completionDay(t);
        return d != null && _sameDay(d, day);
      });
      if (has) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int get _bestStreak {
    if (_allTasks.isEmpty) return 0;
    final doneDays = <DateTime>{};
    for (final t in _allTasks) {
      final d = _completionDay(t);
      if (d != null) doneDays.add(d);
    }
    if (doneDays.isEmpty) return 0;
    final sorted = doneDays.toList()..sort();
    int best = 1, current = 1;
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
        current++;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }

  // [Mon … Sun] — true = has a done task completed on that day
  List<bool> get _weekActivity {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return _allTasks.any((t) {
        final d = _completionDay(t);
        return d != null && _sameDay(d, day);
      });
    });
  }

  double _streakRingValue(int streak) {
    if (streak == 0) return 0;
    final mod = streak % 7;
    return mod == 0 ? 1.0 : mod / 7.0;
  }

  double _milestoneProgress(int streak) => _streakRingValue(streak);

  String _nextMilestoneLabel(int streak) {
    if (streak == 0) return 'Complete a task to start your streak';
    final next = (streak ~/ 7 + 1) * 7;
    final remaining = next - streak;
    const names = {7: 'Week Warrior', 14: 'Fortnight Focus', 21: 'Legendary', 28: 'Champion'};
    final badge = names[next] ?? 'Milestone';
    return '$remaining day${remaining == 1 ? "" : "s"} left • $badge badge unlock';
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final topPad      = MediaQuery.of(context).padding.top;
    final now         = DateTime.now();
    final streak      = _currentStreak;
    final best        = _bestStreak;
    final weekAct     = _weekActivity;
    const dayLabels   = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final todayDow    = now.weekday - 1; // 0=Mon

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : CustomScrollView(slivers: [

              // ── Page header ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 0),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLow(isDark),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Settings',
                          style: GoogleFonts.manrope(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppTheme.subtext(isDark))),
                      Text('Profile & Streaks',
                          style: GoogleFonts.manrope(
                              fontSize: 22, fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: AppTheme.text(isDark))),
                    ]),
                  ]),
                ),
              ),

              // ── Content ──────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([

                    // Profile header row
                    NudgeCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        _ProfileAvatarWidget(
                          imagePath: _profileImagePath,
                          name: _userName,
                          size: 52,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                              _userName.isEmpty ? 'Student' : _userName,
                              style: GoogleFonts.manrope(
                                  fontSize: 15, fontWeight: FontWeight.w800,
                                  color: AppTheme.text(isDark))),
                            Text('Level $_level · Active',
                                style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: AppTheme.subtext(isDark))),
                          ]),
                        ),
                        // XP pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLow(isDark),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$_xp XP',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, fontWeight: FontWeight.w800,
                                  color: AppTheme.primary)),
                        ),
                        const SizedBox(width: 8),
                        // Edit button
                        GestureDetector(
                          onTap: () => _openEditProfile(isDark),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: 44, height: 44,
                            child: Center(
                              child: Icon(Icons.edit_rounded,
                                  color: AppTheme.subtext(isDark), size: 18),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // Streak hero
                    NudgeCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 24),
                      child: Column(children: [
                        NudgeRingProgress(
                          value: _streakRingValue(streak),
                          size: 130,
                          strokeWidth: 11,
                          gradient: [AppTheme.primary, AppTheme.primaryContainer],
                          center: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Text(streak.toString(),
                                style: GoogleFonts.manrope(
                                    fontSize: 36, fontWeight: FontWeight.w800,
                                    color: AppTheme.primary, height: 1)),
                            Text('day streak',
                                style: GoogleFonts.manrope(
                                    fontSize: 11, fontWeight: FontWeight.w600,
                                    color: AppTheme.subtext(isDark))),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          streak > 0
                              ? '🔥 Keep the momentum alive'
                              : '🚀 Start your streak today!',
                          style: GoogleFonts.manrope(
                              fontSize: 18, fontWeight: FontWeight.w800,
                              color: AppTheme.text(isDark)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Personal best: $best days  ·  Total done: $_totalDone',
                          style: GoogleFonts.manrope(
                              fontSize: 13, color: AppTheme.subtext(isDark)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Milestone progress
                    NudgeCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('MILESTONE PROGRESS',
                                style: GoogleFonts.manrope(
                                    fontSize: 11, fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppTheme.subtext(isDark))),
                            Text(
                              streak > 0
                                  ? '${(_milestoneProgress(streak) * 100).round()}% to next'
                                  : 'No streak yet',
                              style: GoogleFonts.manrope(
                                  fontSize: 11, fontWeight: FontWeight.w800,
                                  color: AppTheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NudgeProgressBar(
                            value: _milestoneProgress(streak), height: 8),
                        const SizedBox(height: 8),
                        Text(_nextMilestoneLabel(streak),
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: AppTheme.subtext(isDark))),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // Weekly streak dots
                    NudgeCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('THIS WEEK',
                            style: GoogleFonts.manrope(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: AppTheme.subtext(isDark))),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(7, (i) => _WeekDot(
                            label: dayLabels[i],
                            done: weekAct[i],
                            isToday: i == todayDow,
                            isFuture: i > todayDow,
                            isDark: isDark,
                          )),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // XP progress + badges
                    NudgeCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('XP Progress',
                                style: GoogleFonts.manrope(
                                    fontSize: 14, fontWeight: FontWeight.w800,
                                    color: AppTheme.text(isDark))),
                            Text('Level $_level',
                                style: GoogleFonts.manrope(
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$_xp / ${_level * 100} XP · Level ${_level + 1} in ${100 - (_xp % 100)} XP',
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppTheme.subtext(isDark))),
                        const SizedBox(height: 8),
                        NudgeProgressBar(
                          value: _xpProgressInLevel,
                          height: 8,
                          gradient: [
                            AppTheme.primary, AppTheme.primaryContainer
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Recent badges',
                            style: GoogleFonts.manrope(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppTheme.text(isDark))),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _BadgeTile(
                            emoji: '🔥', label: 'Streak',
                            bg: AppTheme.surfaceLow(isDark),
                            isDark: isDark,
                            unlocked: streak >= 3,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _BadgeTile(
                            emoji: '⚡', label: 'Speed',
                            bg: isDark
                                ? const Color(0xFF0D1F18)
                                : const Color(0xFFECFDF5),
                            isDark: isDark,
                            unlocked: _totalDone >= 5,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _BadgeTile(
                            emoji: '🎯', label: 'Focus',
                            bg: isDark
                                ? const Color(0xFF1E1A0F)
                                : const Color(0xFFFFF8EC),
                            isDark: isDark,
                            unlocked: _totalDone >= 10,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _BadgeTile(
                            emoji: '🏆', label: 'Milestone',
                            bg: isDark
                                ? const Color(0xFF1A0F1E)
                                : const Color(0xFFFFF0F2),
                            isDark: isDark,
                            unlocked: streak >= 7,
                          )),
                        ]),
                      ]),
                    ),

                  ]),
                ),
              ),
            ]),
    );
  }
}

// ── Weekly dot ────────────────────────────────────────────────────────────────

class _WeekDot extends StatelessWidget {
  final String label;
  final bool done, isToday, isFuture, isDark;
  const _WeekDot({
    required this.label, required this.done,
    required this.isToday, required this.isFuture, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (isFuture) {
      bg = AppTheme.surfaceLow(isDark);
      fg = AppTheme.subtext(isDark).withValues(alpha: 0.5);
    } else if (done) {
      bg = AppTheme.primary;
      fg = Colors.white;
    } else if (isToday) {
      bg = AppTheme.primary.withValues(alpha: 0.12);
      fg = AppTheme.primary;
    } else {
      bg = AppTheme.surfaceLow(isDark);
      fg = AppTheme.subtext(isDark);
    }

    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: isToday && !done
            ? Border.all(color: AppTheme.primary, width: 2)
            : null,
      ),
      child: Center(
        child: Text(label, style: GoogleFonts.manrope(
            fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

// ── Badge tile ────────────────────────────────────────────────────────────────

class _BadgeTile extends StatelessWidget {
  final String emoji, label;
  final Color bg;
  final bool unlocked, isDark;
  const _BadgeTile({
    required this.emoji, required this.label,
    required this.bg, required this.unlocked, required this.isDark});

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: unlocked ? 1.0 : 0.35,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.manrope(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: AppTheme.text(isDark))),
      ]),
    ),
  );
}

// ── Edit profile bottom sheet ─────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final List<String> initialSubjects;
  final String? initialImagePath;
  final bool isDark;
  const _EditProfileSheet({
    required this.initialName,
    required this.initialSubjects,
    this.initialImagePath,
    required this.isDark,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _customCtrl;
  late final Set<String> _selected;
  final List<String> _custom = [];
  bool _saving = false;
  String? _imagePath;

  static const _predefined = [
    'Maths', 'Physics', 'Chemistry', 'English',
    'Computer Science', 'Data Structures',
    'Operating Systems', 'DBMS', 'Networks', 'Mechanics',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl   = TextEditingController(text: widget.initialName);
    _customCtrl = TextEditingController();
    _selected   = Set.from(widget.initialSubjects);
    _imagePath  = widget.initialImagePath;
    // Any subject not in predefined is custom.
    for (final s in widget.initialSubjects) {
      if (!_predefined.contains(s)) _custom.add(s);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  void _toggleSubject(String s) =>
      setState(() => _selected.contains(s) ? _selected.remove(s) : _selected.add(s));

  void _addCustom() {
    final s = _customCtrl.text.trim();
    if (s.isEmpty) return;
    setState(() {
      _custom.add(s);
      _selected.add(s);
      _customCtrl.clear();
    });
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() => _imagePath = result.files.single.path);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await UserPrefs.setUserName(_nameCtrl.text.trim());
    await UserPrefs.setUserSubjects(_selected.toList());
    await UserPrefs.setProfileImagePath(_imagePath);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.border(isDark),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Edit profile',
                  style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppTheme.text(isDark))),
              const SizedBox(height: 20),
              // Profile photo picker
              Center(
                child: Column(children: [
                  _ProfileAvatarWidget(imagePath: _imagePath, name: _nameCtrl.text, size: 72),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera_rounded, size: 16),
                      label: Text(_imagePath != null ? 'Change photo' : 'Add photo',
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    if (_imagePath != null)
                      TextButton(
                        onPressed: () => setState(() => _imagePath = null),
                        child: Text('Remove',
                            style: GoogleFonts.manrope(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: const Color(0xFFE53935))),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              // Name field
              Text('Name',
                  style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: AppTheme.subtext(isDark))),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLow(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: GoogleFonts.manrope(
                    fontSize: 15, color: AppTheme.text(isDark)),
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    hintStyle: GoogleFonts.manrope(
                        fontSize: 15, color: AppTheme.subtext(isDark)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Subjects
              Text('Subjects',
                  style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    letterSpacing: 0.6, color: AppTheme.subtext(isDark))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [..._predefined, ..._custom].map((s) {
                  final isOn = _selected.contains(s);
                  return GestureDetector(
                    onTap: () => _toggleSubject(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                            fontSize: 12, fontWeight: FontWeight.w600,
                            color: isOn ? Colors.white : AppTheme.subtext(isDark))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // Custom add
              Row(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLow(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border(isDark)),
                    ),
                    child: TextField(
                      controller: _customCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: GoogleFonts.manrope(
                          fontSize: 13, color: AppTheme.text(isDark)),
                      decoration: InputDecoration(
                        hintText: 'Add a subject…',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        hintStyle: GoogleFonts.manrope(
                            fontSize: 13, color: AppTheme.subtext(isDark)),
                      ),
                      onSubmitted: (_) => _addCustom(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addCustom,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Save changes',
                          style: GoogleFonts.manrope(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Profile avatar widget ─────────────────────────────────────────────────────

class _ProfileAvatarWidget extends StatelessWidget {
  final String? imagePath;
  final String name;
  final double size;
  const _ProfileAvatarWidget({this.imagePath, this.name = '', this.size = 52});

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty
        && File(imagePath!).existsSync();
    final initials = name.isNotEmpty
        ? name.trim().split(RegExp(r'\s+')).take(2)
              .map((w) => w[0].toUpperCase()).join()
        : '?';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasImage ? null : const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        image: hasImage
            ? DecorationImage(image: FileImage(File(imagePath!)), fit: BoxFit.cover)
            : null,
      ),
      child: hasImage ? null : Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}
