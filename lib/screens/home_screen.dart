// lib/screens/home_screen.dart

import 'dart:io' as import_dart_io;
import 'dart:ui';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../database/db_helper.dart';
import '../main.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/nudge_primitives.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';
import 'calendar_screen.dart';
import 'profile_screen.dart';
import '../services/user_prefs.dart';

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN — bottom nav shell
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  late final PageController _pageController;
  List<Task> _todayTasks = [];
  List<Task> _allTasks   = [];
  Map<String, List<NudgeDocument>> _docsBySubject = {};
  List<NudgeDocument> _allDocs = [];
  bool _loading = true;
  String _userName = '';
  String? _profileImagePath;
  int _totalXp = 0;
  int _cachedStreak = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _navIndex);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Updates the active icon immediately and then animates the page.
  // Using setState before animateToPage ensures the dock highlight
  // switches on tap, not at the end of the 300 ms animation.
  void _goToPage(int i) {
    if (!mounted) return;
    setState(() => _navIndex = i);
    _pageController.animateToPage(i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await DBHelper.instance.deleteExpiredCompletedTasks();
    final userName         = await UserPrefs.getUserName();
    final profileImagePath = await UserPrefs.getProfileImagePath();
    final totalXp          = await UserPrefs.getTotalXp();
    final all     = await DBHelper.instance.getAllTasks();
    final docsMap = await DBHelper.instance.getAllDocumentsGrouped();
    final now = DateTime.now();
    final today = all.where((t) {
      if (t.isDone) return false;
      return t.deadline.isBefore(DateTime(now.year, now.month, now.day + 1));
    }).toList();
    // Compute streak once here so _showCelebration can read it without re-looping.
    bool _sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    DateTime? _completionDay(Task t) {
      if (!t.isDone) return null;
      final dt = t.completedAt ?? t.deadline;
      return DateTime(dt.year, dt.month, dt.day);
    }
    final streakNow = DateTime.now();
    final streakToday = DateTime(streakNow.year, streakNow.month, streakNow.day);
    int computedStreak = 0;
    if (all.any((t) { final d = _completionDay(t); return d != null && _sameDay(d, streakToday); })) computedStreak++;
    for (int i = 1; i < 365; i++) {
      final day = streakToday.subtract(Duration(days: i));
      if (all.any((t) { final d = _completionDay(t); return d != null && _sameDay(d, day); })) {
        computedStreak++;
      } else {
        break;
      }
    }

    if (mounted) setState(() {
      _todayTasks = today; _allTasks = all;
      _docsBySubject = docsMap;
      _allDocs = docsMap.values.expand((list) => list).toList();
      _cachedStreak = computedStreak;
      _loading = false;
      _userName = userName;
      _profileImagePath = profileImagePath;
      _totalXp = totalXp;
    });
  }

  Future<void> _addTask() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, a, __) => const AddTaskScreen(),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ));
    await _load();
  }

  Future<void> _toggleDone(Task task) async {
    HapticFeedback.selectionClick();
    final markingDone = !task.isDone;
    final updated = task.copyWith(
      isDone: markingDone,
      completedAt: markingDone ? DateTime.now() : null,
    );
    await DBHelper.instance.updateTask(updated);
    if (markingDone) await UserPrefs.incrementTotalXp(10);
    if (updated.isDone) await NotificationService.instance.cancelReminders(task);
    else await NotificationService.instance.scheduleReminders(updated);
    await _load();
    if (markingDone && mounted) _showCelebration(updated);
  }

  void _showCelebration(Task task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (_) => _CelebrationSheet(
        taskName: task.name,
        xp: _totalXp,
        streak: _cachedStreak,
        isDark: isDark,
      ),
    );
  }

  Future<void> _deleteTask(Task task) async {
    HapticFeedback.mediumImpact();
    await NotificationService.instance.cancelReminders(task);
    await DBHelper.instance.deleteTask(task.id!);
    await _load();
  }

  Future<bool> _confirmDelete(BuildContext ctx, String name) async =>
      await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete task?',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Text('"$name"'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Color(0xFFE53935)))),
          ],
        ),
      ) ?? false;

  Future<void> _editTask(Task task) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddTaskScreen(initialTask: task),
    ));
    await _load();
  }

  Future<void> _bulkDeleteTasks(List<Task> tasks) async {
    for (final task in tasks) {
      await NotificationService.instance.cancelReminders(task);
    }
    await DBHelper.instance.bulkDeleteTasks(tasks.map((t) => t.id!).toList());
    await _load();
  }

  void _openTaskDetail(Task task) {
    Navigator.of(context)
        .push(MaterialPageRoute(
      builder: (_) => TaskDetailScreen(
        task: task,
        onToggle: () async {
          await _toggleDone(task);
          if (mounted) Navigator.pop(context);
        },
        onDelete: () async {
          final ok = await _confirmDelete(context, task.name);
          if (ok && mounted) {
            await NotificationService.instance.cancelReminders(task);
            await DBHelper.instance.deleteTask(task.id!);
            await _load();
            if (mounted) Navigator.pop(context);
          }
        },
        onEdit: () {
          Navigator.of(context).pop();
          _editTask(task);
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      _TodayTab(
          tasks: _todayTasks, allTasks: _allTasks,
          allDocs: _allDocs,
          onToggle: _toggleDone, onDelete: _deleteTask,
          onTap: _openTaskDetail, onAdd: _addTask,
          isDark: isDark,
          userName: _userName,
          profileImagePath: _profileImagePath,
          totalXp: _totalXp,
          onSearchTap: () => _goToPage(1),
          onProfileTap: () async {
            await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()));
            await _load();
          }),
      _AllTab(
          tasks: _allTasks, onToggle: _toggleDone,
          onDelete: _deleteTask, onTap: _openTaskDetail,
          onBulkDelete: _bulkDeleteTasks,
          isDark: isDark),
      _DocsTab(
          docsBySubject: _docsBySubject,
          onRefresh: _load, isDark: isDark),
      _SettingsTab(
          isDark: isDark, onRefresh: _load,
          userName: _userName, profileImagePath: _profileImagePath),
    ];

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SafeArea(
              top: false,    // each tab handles top padding via MediaQuery.padding.top
              bottom: false, // handled by bottomNavigationBar's SafeArea
              child: PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _navIndex = i),
                children: pages,
              ),
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.navBg(isDark),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home',
                    active: _navIndex == 0,
                    onTap: () => _goToPage(0)),
                _NavItem(icon: Icons.task_alt_rounded, label: 'Tasks',
                    active: _navIndex == 1,
                    onTap: () => _goToPage(1)),
                // Centre + button — round, inline, same height as nav items
                GestureDetector(
                  onTap: _addTask,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
                _NavItem(icon: Icons.folder_rounded, label: 'Docs',
                    active: _navIndex == 2,
                    onTap: () => _goToPage(2)),
                _NavItem(icon: Icons.settings_rounded, label: 'Settings',
                    active: _navIndex == 3,
                    onTap: () => _goToPage(3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Nav item ───────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon, required this.label,
        required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22,
                color: active ? AppTheme.primary : AppTheme.subtext(isDark)),
          ),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppTheme.primary : AppTheme.subtext(isDark),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TODAY / HOME TAB — dashboard
// ══════════════════════════════════════════════════════════════════════════════

class _TodayTab extends StatefulWidget {
  final List<Task> tasks;    // today's pending tasks
  final List<Task> allTasks; // all tasks — for heatmap and energy ring
  final List<NudgeDocument> allDocs; // all documents — for search
  final Function(Task) onToggle, onDelete, onTap;
  final VoidCallback onAdd;
  final bool isDark;
  final String userName;
  final String? profileImagePath;
  final int totalXp;
  final VoidCallback onSearchTap;
  final VoidCallback onProfileTap;
  const _TodayTab({
    required this.tasks, required this.allTasks,
    required this.allDocs,
    required this.onToggle, required this.onDelete,
    required this.onTap, required this.onAdd, required this.isDark,
    this.userName = '',
    this.profileImagePath,
    this.totalXp = 0,
    required this.onSearchTap,
    required this.onProfileTap,
  });
  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  bool _nudgeDismissed = false;

  // ── Search state ──────────────────────────────────────────────────────────────
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  void _openSearch()  => setState(() => _searchOpen = true);
  void _closeSearch() => setState(() {
    _searchOpen = false;
    _searchCtrl.clear();
    _searchQuery = '';
  });

  // ── Cached derived values — recomputed only when task lists change ──────────
  // Avoids re-running O(n) and O(365×n) logic on every build() triggered by
  // unrelated local state changes (e.g. dismissing the nudge card).

  late Map<DateTime, int> _cachedHeatmap;
  late int _cachedTodayDone;
  late int _cachedStreak;
  late int _cachedBest;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime? _completionDay(Task t) {
    if (!t.isDone) return null;
    final dt = t.completedAt ?? t.deadline;
    return DateTime(dt.year, dt.month, dt.day);
  }

  void _recompute() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 28-day heatmap
    final map = <DateTime, int>{};
    for (int i = 27; i >= 0; i--) {
      map[today.subtract(Duration(days: i))] = 0;
    }
    for (final t in widget.allTasks) {
      if (!t.isDone) continue;
      final dt  = t.completedAt ?? t.deadline;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (map.containsKey(day)) map[day] = (map[day]! + 1).clamp(0, 5);
    }
    _cachedHeatmap = map;

    // Today-done count
    _cachedTodayDone = widget.allTasks
        .where((t) {
      final d = _completionDay(t);
      return d != null && _sameDay(d, today);
    })
        .length;

    // Current streak
    int streak = 0;
    if (widget.allTasks.any((t) {
      final d = _completionDay(t);
      return d != null && _sameDay(d, today);
    })) streak++;
    for (int i = 1; i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      if (widget.allTasks.any((t) {
        final d = _completionDay(t);
        return d != null && _sameDay(d, day);
      })) {
        streak++;
      } else {
        break;
      }
    }
    _cachedStreak = streak;

    // Best streak
    final doneDays = <DateTime>{};
    for (final t in widget.allTasks) {
      final d = _completionDay(t);
      if (d != null) doneDays.add(d);
    }
    if (doneDays.isEmpty) {
      _cachedBest = 0;
    } else {
      final sorted = doneDays.toList()..sort();
      int best = 1, cur = 1;
      for (int i = 1; i < sorted.length; i++) {
        if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
          cur++;
          if (cur > best) best = cur;
        } else {
          cur = 1;
        }
      }
      _cachedBest = best;
    }
  }

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TodayTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.allTasks, widget.allTasks) ||
        !identical(old.tasks, widget.tasks)) {
      _recompute();
    }
  }

  String get _nudgeMessage {
    final now     = DateTime.now();
    final overdue = widget.tasks
        .where((t) => t.deadline.isBefore(now)).length;
    final urgent  = widget.tasks
        .where((t) =>
    !t.deadline.isBefore(now) &&
        t.deadline.difference(now).inHours < 24).length;
    if (overdue > 0) {
      return 'You have $overdue overdue task${overdue > 1 ? "s" : ""}. '
          'Tackle ${overdue > 1 ? "them" : "it"} first to protect your streak.';
    }
    if (urgent > 0) {
      return '$urgent task${urgent > 1 ? "s" : ""} due in the next 24 hours. '
          'Stay focused!';
    }
    if (widget.tasks.isEmpty) {
      return 'All clear today! A great time to get ahead on upcoming work.';
    }
    return '${widget.tasks.length} task${widget.tasks.length > 1 ? "s" : ""} '
        'left today. Keep the momentum going!';
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = widget.isDark;
    final now      = DateTime.now();
    final h        = now.hour;
    final greet    = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    final overdue  = widget.tasks.where((t) => t.deadline.isBefore(now)).toList();
    final upcoming = widget.tasks.where((t) => !t.deadline.isBefore(now)).toList();
    final totalToday     = widget.tasks.length + _cachedTodayDone;
    final tasksRingValue =
    totalToday > 0 ? _cachedTodayDone / totalToday : 0.0;
    final topPad  = MediaQuery.of(context).padding.top;

    return Stack(children: [
      CustomScrollView(slivers: [

      // ── 1. Greeting + Smart Nudge + Streak ───────────────────────
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topPad + 24, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Greeting row with top-right actions
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE · d MMM').format(now).toUpperCase(),
                    style: GoogleFonts.manrope(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 0.8, color: AppTheme.subtext(isDark)),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.manrope(
                        fontSize: 32, fontWeight: FontWeight.w800,
                        color: AppTheme.text(isDark),
                        letterSpacing: -0.8, height: 1.1,
                      ),
                      children: [
                        TextSpan(text: widget.userName.isNotEmpty
                            ? 'Hey ${widget.userName.split(' ').first},\n'
                            : '$greet,\n'),
                        TextSpan(
                          text: widget.tasks.isEmpty ? 'all clear! 🎉' : 'let\'s go.',
                          style: const TextStyle(
                              color: AppTheme.primary, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              )),
              const SizedBox(width: 12),
              Row(children: [
                GestureDetector(
                  onTap: _openSearch,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.card(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border(isDark)),
                    ),
                    child: Icon(Icons.search_rounded, size: 20,
                        color: AppTheme.subtext(isDark)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onProfileTap,
                  child: _ProfileAvatar(
                      imagePath: widget.profileImagePath,
                      name: widget.userName, size: 40),
                ),
              ]),
            ]),
            const SizedBox(height: 6),
            Text(
              widget.tasks.isEmpty
                  ? 'No tasks due today.'
                  : '${widget.tasks.length} task${widget.tasks.length == 1 ? "" : "s"}'
                  ' for today${_cachedTodayDone > 0 ? ", $_cachedTodayDone done ✓" : "."}',
              style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: AppTheme.subtext(isDark)),
            ),
            const SizedBox(height: 14),

            // ── Smart Nudge ───────────────────────────────────────
            if (!_nudgeDismissed) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryContainer],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('SMART NUDGE',
                        style: GoogleFonts.manrope(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            letterSpacing: 0.6, color: AppTheme.primary)),
                    const SizedBox(height: 3),
                    Text(_nudgeMessage,
                        style: GoogleFonts.manrope(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppTheme.text(isDark), height: 1.4)),
                  ])),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44, height: 44,
                    child: GestureDetector(
                      onTap: () => setState(() => _nudgeDismissed = true),
                      behavior: HitTestBehavior.opaque,
                      child: Center(child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            color: AppTheme.primary, size: 14),
                      )),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],

            // ── Streak first ──────────────────────────────────────
            RepaintBoundary(
              child: _StreakSummaryCard(
                isDark: isDark,
                streak: _cachedStreak,
                xp: widget.totalXp,
                best: _cachedBest,
              ),
            ),
            const SizedBox(height: 14),

            // ── Tasks section label ───────────────────────────────
            if (widget.tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text("Today's Tasks",
                    style: GoogleFonts.manrope(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: AppTheme.text(isDark))),
              ),
          ]),
        ),
      ),

      // ── 2. Task list ──────────────────────────────────────────────
      if (widget.tasks.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'All clear today!',
              subtitle: 'No tasks due. Tap + to add one.',
              actionLabel: 'Add a task',
              onAction: widget.onAdd,
              isDark: isDark,
            ),
          ),
        )
      else ...[
        if (overdue.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(
              title: 'OVERDUE', color: AppTheme.danger, isDark: isDark)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (_, i) => RepaintBoundary(
                child: GestureDetector(
                  onTap: () => widget.onTap(overdue[i]),
                  child: TaskCard(
                      task: overdue[i],
                      onToggleDone: () => widget.onToggle(overdue[i]),
                      onDelete: () => widget.onDelete(overdue[i])),
                ),
              ),
              childCount: overdue.length,
            )),
          ),
        ],
        if (upcoming.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(
              title: 'COMING UP', color: AppTheme.subtext(isDark), isDark: isDark)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (_, i) => RepaintBoundary(
                child: GestureDetector(
                  onTap: () => widget.onTap(upcoming[i]),
                  child: TaskCard(
                      task: upcoming[i],
                      onToggleDone: () => widget.onToggle(upcoming[i]),
                      onDelete: () => widget.onDelete(upcoming[i])),
                ),
              ),
              childCount: upcoming.length,
            )),
          ),
        ],
      ],

      // ── 3. Heatmap (smaller) + Energy rings ───────────────────────
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(children: [

            // Heatmap card — reduced cell spacing & aspect ratio
            RepaintBoundary(child: NudgeCard(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NudgeLabel('Momentum'),
                    const SizedBox(height: 2),
                    Text('28-day activity',
                        style: GoogleFonts.manrope(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: AppTheme.text(isDark))),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLow(isDark),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('28 days',
                        style: GoogleFonts.manrope(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                ]),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.25,
                  children: _cachedHeatmap.entries.map((e) {
                    final heat = e.value;
                    final isToday = e.key.year == now.year &&
                        e.key.month == now.month && e.key.day == now.day;
                    final Color cellColor = isToday
                        ? AppTheme.primary
                        : heat == 0
                        ? AppTheme.surfaceLow(isDark)
                        : AppTheme.primary.withValues(
                        alpha: (0.2 + heat * 0.16).clamp(0.2, 1.0));
                    return Tooltip(
                      message: '${e.key.day}/${e.key.month}: $heat task${heat == 1 ? "" : "s"}',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(5),
                          border: isToday
                              ? Border.all(color: AppTheme.primary, width: 1.5)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Text('Less', style: GoogleFonts.manrope(
                      fontSize: 10, color: AppTheme.subtext(isDark))),
                  const Spacer(),
                  ...List.generate(5, (i) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? AppTheme.surfaceLow(isDark)
                            : AppTheme.primary.withValues(alpha: 0.2 + i * 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  )),
                  const Spacer(),
                  Text('More', style: GoogleFonts.manrope(
                      fontSize: 10, color: AppTheme.subtext(isDark))),
                ]),
              ]),
            )),  // end RepaintBoundary + NudgeCard (heatmap)
            const SizedBox(height: 12),

            // Energy rings card
            RepaintBoundary(child: NudgeCard(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NudgeLabel('Energy Rings'),
                    const SizedBox(height: 2),
                    Text("Today's progress",
                        style: GoogleFonts.manrope(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: AppTheme.text(isDark))),
                  ]),
                  const Text('⚡', style: TextStyle(fontSize: 22)),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _RingItem(
                    label: 'Tasks',
                    value: tasksRingValue,
                    percent: totalToday > 0
                        ? '${(_cachedTodayDone / totalToday * 100).round()}%'
                        : '—',
                    gradient: [AppTheme.primary, AppTheme.primaryContainer],
                    isDark: isDark,
                  ),
                  _RingItem(
                    label: 'Focus', value: 0, percent: '—',
                    gradient: [AppTheme.secondary, AppTheme.secondaryContainer],
                    isDark: isDark,
                  ),
                  _RingItem(
                    label: 'Habits', value: 0, percent: '—',
                    gradient: [AppTheme.tertiary, const Color(0xFFFFE4A0)],
                    isDark: isDark,
                  ),
                ]),
              ]),
            )),  // end RepaintBoundary + NudgeCard (energy rings)
          ]),
        ),
      ),

      const SliverToBoxAdapter(child: SizedBox(height: 100)),
    ]),  // end CustomScrollView
    // ── Floating search ───────────────────────────────────────────
    if (_searchOpen) ...[
      Positioned.fill(
        child: GestureDetector(
          onTap: _closeSearch,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.28),
          ),
        ),
      ),
      Positioned(
        top: topPad + 8,
        left: 16,
        right: 16,
        child: _HomeSearchFloat(
          ctrl: _searchCtrl,
          query: _searchQuery,
          allTasks: widget.allTasks,
          allDocs: widget.allDocs,
          isDark: isDark,
          onChanged: (q) => setState(() => _searchQuery = q),
          onClose: _closeSearch,
          onTap: widget.onTap,
        ),
      ),
    ],
    ]);  // end Stack
  }
}

// ── Ring widget ────────────────────────────────────────────────────────────────

class _RingItem extends StatelessWidget {
  final String label, percent;
  final double value;
  final List<Color> gradient;
  final bool isDark;
  const _RingItem({
    required this.label, required this.value, required this.percent,
    required this.gradient, required this.isDark});
  @override
  Widget build(BuildContext context) => Column(children: [
    NudgeRingProgress(
      value: value,
      size: 80,
      strokeWidth: 10,
      gradient: gradient,
      center: Text(percent,
          style: GoogleFonts.manrope(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: gradient.first)),
    ),
    const SizedBox(height: 6),
    Text(label, style: GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: AppTheme.subtext(isDark))),
  ]);
}

// ── Streak summary card ────────────────────────────────────────────────────────

class _StreakSummaryCard extends StatelessWidget {
  final bool isDark;
  final int streak, xp, best;
  const _StreakSummaryCard({
    required this.isDark,
    required this.streak,
    required this.xp,
    required this.best,
  });

  double get _milestoneProgress {
    if (streak == 0) return 0;
    final mod = streak % 7;
    return mod == 0 ? 1.0 : mod / 7.0;
  }

  String get _milestoneLabel {
    if (streak == 0) return 'Complete a task to start your streak';
    final next = (streak ~/ 7 + 1) * 7;
    final remaining = next - streak;
    const names = {7: 'Week Warrior', 14: 'Fortnight Focus', 21: 'Legendary', 28: 'Champion'};
    final badge = names[next] ?? 'Milestone';
    return '$remaining day${remaining == 1 ? "" : "s"} to $badge badge';
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen())),
    child: NudgeCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Streak Progress',
                style: GoogleFonts.manrope(
                    fontSize: 15, fontWeight: FontWeight.w800,
                    color: AppTheme.text(isDark))),
            Row(children: [
              Text('Tap to view',
                  style: GoogleFonts.manrope(
                      fontSize: 11, color: AppTheme.subtext(isDark))),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 18),
            ]),
          ],
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatMini(
            value: streak.toString(), label: 'Day Streak',
            bg: AppTheme.surfaceLow(isDark), fg: AppTheme.primary,
          )),
          const SizedBox(width: 8),
          Expanded(child: _StatMini(
            value: xp.toString(), label: 'XP',
            bg: isDark
                ? const Color(0xFF1E1A0F)
                : const Color(0xFFFFF8EC),
            fg: AppTheme.tertiaryDark,
          )),
          const SizedBox(width: 8),
          Expanded(child: _StatMini(
            value: best.toString(), label: 'Best',
            bg: isDark
                ? const Color(0xFF0D1F18)
                : const Color(0xFFECFDF5),
            fg: AppTheme.calm,
          )),
        ]),
        const SizedBox(height: 10),
        NudgeProgressBar(value: _milestoneProgress, height: 8),
        const SizedBox(height: 8),
        Text(_milestoneLabel,
            style: GoogleFonts.manrope(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppTheme.primary)),
      ]),
    ),
  );
}

// ── Floating home search ──────────────────────────────────────────────────────

class _HomeSearchFloat extends StatelessWidget {
  final TextEditingController ctrl;
  final String query;
  final List<Task> allTasks;
  final List<NudgeDocument> allDocs;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final Function(Task) onTap;

  const _HomeSearchFloat({
    required this.ctrl,
    required this.query,
    required this.allTasks,
    required this.allDocs,
    required this.isDark,
    required this.onChanged,
    required this.onClose,
    required this.onTap,
  });

  List<Task> get _taskResults {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return allTasks.where((t) =>
        t.name.toLowerCase().contains(q) ||
        t.subject.toLowerCase().contains(q) ||
        t.description.toLowerCase().contains(q) ||
        t.referenceLink.toLowerCase().contains(q)).toList();
  }

  List<NudgeDocument> get _docResults {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return allDocs.where((d) =>
        d.note.toLowerCase().contains(q) ||
        d.subject.toLowerCase().contains(q) ||
        d.filePath.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final taskResults = _taskResults;
    final docResults  = _docResults;
    final hasResults  = taskResults.isNotEmpty || docResults.isNotEmpty;
    final cardBg      = AppTheme.card(isDark);
    final shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
        blurRadius: 24,
        offset: const Offset(0, 6),
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search bar ───────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: shadow,
            ),
            child: Row(children: [
              const SizedBox(width: 14),
              const Icon(Icons.search_rounded, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  onChanged: onChanged,
                  style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: 'Search tasks, files, subjects…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    isDense: true,
                    hintStyle: GoogleFonts.manrope(
                        fontSize: 14, fontWeight: FontWeight.w500,
                        color: AppTheme.subtext(isDark)),
                  ),
                ),
              ),
              if (query.isNotEmpty)
                GestureDetector(
                  onTap: () { ctrl.clear(); onChanged(''); },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.close_rounded,
                        color: AppTheme.subtext(isDark), size: 18),
                  ),
                )
              else
                const SizedBox(width: 6),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 14, 0),
                  child: Text('Cancel',
                      style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                ),
              ),
            ]),
          ),

          // ── Results panel ────────────────────────────────
          if (query.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: shadow,
              ),
              child: !hasResults
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      child: Text('No results for "$query"',
                          style: GoogleFonts.manrope(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: AppTheme.subtext(isDark))),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tasks section
                            if (taskResults.isNotEmpty) ...[
                              _SearchSectionHeader(
                                  label: 'Tasks',
                                  count: taskResults.length,
                                  isDark: isDark),
                              const SizedBox(height: 8),
                              ...taskResults.map((task) => GestureDetector(
                                onTap: () { onClose(); onTap(task); },
                                child: _SearchTaskRow(task: task, isDark: isDark),
                              )),
                            ],
                            // Docs section
                            if (docResults.isNotEmpty) ...[
                              if (taskResults.isNotEmpty)
                                const SizedBox(height: 12),
                              _SearchSectionHeader(
                                  label: 'Files',
                                  count: docResults.length,
                                  isDark: isDark),
                              const SizedBox(height: 8),
                              ...docResults.map((doc) => _SearchDocRow(
                                doc: doc,
                                isDark: isDark,
                                onTap: () async {
                                  onClose();
                                  await OpenFilex.open(doc.filePath);
                                },
                              )),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final bool isDark;
  const _SearchSectionHeader(
      {required this.label, required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label.toUpperCase(),
        style: GoogleFonts.manrope(
            fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 0.7, color: AppTheme.subtext(isDark))),
    const SizedBox(width: 6),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text('$count',
          style: GoogleFonts.manrope(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppTheme.primary)),
    ),
  ]);
}

class _SearchTaskRow extends StatelessWidget {
  final Task task;
  final bool isDark;
  const _SearchTaskRow({required this.task, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final subjectColor = AppTheme.subjectColor(task.subject);
    final urgColor = task.isDone
        ? AppTheme.calm : AppTheme.urgencyColor(task.deadline);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLow(isDark),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Container(
            width: 3, height: 32,
            decoration: BoxDecoration(
              color: task.isDone
                  ? AppTheme.subtext(isDark) : subjectColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: task.isDone
                            ? AppTheme.subtext(isDark) : AppTheme.text(isDark),
                        decoration: task.isDone
                            ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 2),
                Row(children: [
                  if (task.subject.isNotEmpty) ...[
                    Text(task.subject,
                        style: GoogleFonts.manrope(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: subjectColor)),
                    const SizedBox(width: 6),
                    Text('·', style: TextStyle(
                        fontSize: 10, color: AppTheme.subtext(isDark))),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    DateFormat('d MMM').format(task.deadline),
                    style: GoogleFonts.manrope(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: urgColor),
                  ),
                ]),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: AppTheme.subtext(isDark)),
        ]),
      ),
    );
  }
}

class _SearchDocRow extends StatelessWidget {
  final NudgeDocument doc;
  final bool isDark;
  final VoidCallback onTap;
  const _SearchDocRow(
      {required this.doc, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.subjectColor(doc.subject);
    final isImg = doc.isImage;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLow(isDark),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isImg
                    ? Icons.image_rounded
                    : doc.isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.insert_drive_file_rounded,
                color: color, size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.note.isNotEmpty ? doc.note : 'Document',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppTheme.text(isDark))),
                  if (doc.subject.isNotEmpty)
                    Text(doc.subject,
                        style: GoogleFonts.manrope(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: color)),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded,
                size: 14, color: AppTheme.subtext(isDark)),
          ]),
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  final String value, label;
  final Color bg, fg;
  const _StatMini({required this.value, required this.label,
    required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: GoogleFonts.manrope(
          fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
      Text(label.toUpperCase(),
          style: GoogleFonts.manrope(
              fontSize: 8, fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: fg.withValues(alpha: 0.75))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ALL TASKS TAB  — search-first, stat cards, filter chips
// ══════════════════════════════════════════════════════════════════════════════

class _AllTab extends StatefulWidget {
  final List<Task> tasks;
  final Function(Task) onToggle, onDelete, onTap;
  final Future<void> Function(List<Task>) onBulkDelete;
  final bool isDark;
  const _AllTab({required this.tasks, required this.onToggle,
    required this.onDelete, required this.onTap,
    required this.onBulkDelete, required this.isDark});
  @override
  State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> {
  // 0=All, 1=Pending, 2=Urgent, 3=Done
  int _filter = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};

  bool get _isSelecting => _selectedIds.isNotEmpty;

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _doBulkDelete(BuildContext ctx) async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete $count task${count == 1 ? "" : "s"}?',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(_, true),
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFE53935)))),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    final toDelete = widget.tasks
        .where((t) => t.id != null && _selectedIds.contains(t.id))
        .toList();
    setState(() => _selectedIds.clear());
    await widget.onBulkDelete(toDelete);
  }

  @override
  void didUpdateWidget(_AllTab old) {
    super.didUpdateWidget(old);
    if (old.tasks != widget.tasks) {
      final ids = widget.tasks.map((t) => t.id).toSet();
      _selectedIds.removeWhere((id) => !ids.contains(id));
    }
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<Task> get _visible {
    List<Task> base;
    switch (_filter) {
      case 1: base = widget.tasks.where((t) => !t.isDone).toList(); break;
      case 2: base = widget.tasks
          .where((t) => !t.isDone && t.priority == 'urgent').toList(); break;
      case 3: base = widget.tasks.where((t) => t.isDone).toList(); break;
      default: base = widget.tasks;
    }
    if (_search.isEmpty) return base;
    final q = _search.toLowerCase();
    return base.where((t) =>
    t.name.toLowerCase().contains(q) ||
        t.subject.toLowerCase().contains(q) ||
        t.taskType.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = widget.isDark;
    final pending = widget.tasks.where((t) => !t.isDone).length;
    final urgent  = widget.tasks
        .where((t) => !t.isDone && t.priority == 'urgent').length;
    final done    = widget.tasks.where((t) => t.isDone).length;
    final topPad  = MediaQuery.of(context).padding.top;

    return Stack(
        children: [
          CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, topPad + 24, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: NudgeSectionHeader(
                            overline: _isSelecting
                                ? '${_selectedIds.length} selected'
                                : 'Task manager',
                            title: _isSelecting ? 'Select tasks' : 'My Tasks')),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CalendarScreen(
                              tasks: widget.tasks,
                              onToggle: widget.onToggle,
                              onDelete: widget.onDelete,
                              onTap: widget.onTap,
                            ),
                          )),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLow(isDark),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.calendar_month_rounded,
                                size: 20, color: AppTheme.primary),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      NudgeSearchBar(
                        controller: _searchCtrl,
                        hint: 'Search tasks, subjects, types…',
                        onChanged: (v) => setState(() => _search = v),
                        onClear: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      ),
                      const SizedBox(height: 20),
                      // Stat cards
                      Row(children: [
                        Expanded(child: NudgeStatCard(
                          icon: Icons.pending_actions_rounded,
                          value: pending.toString(),
                          label: 'Pending',
                          gradient: [AppTheme.primaryContainer, AppTheme.primary],
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: NudgeStatCard(
                          icon: Icons.bolt_rounded,
                          value: urgent.toString(),
                          label: 'Urgent',
                          gradient: [AppTheme.secondaryContainer, AppTheme.secondary],
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: NudgeStatCard(
                          icon: Icons.task_alt_rounded,
                          value: done.toString(),
                          label: 'Done',
                          gradient: [
                            const Color(0xFFB8F7DE),
                            const Color(0xFF34D399),
                          ],
                        )),
                      ]),
                      const SizedBox(height: 16),
                      // Filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          NudgeFilterChip(label: 'All',
                              selected: _filter == 0,
                              onTap: () => setState(() => _filter = 0)),
                          const SizedBox(width: 8),
                          NudgeFilterChip(label: 'Pending',
                              selected: _filter == 1,
                              onTap: () => setState(() => _filter = 1)),
                          const SizedBox(width: 8),
                          NudgeFilterChip(label: 'Urgent',
                              selected: _filter == 2,
                              onTap: () => setState(() => _filter = 2)),
                          const SizedBox(width: 8),
                          NudgeFilterChip(label: 'Done',
                              selected: _filter == 3,
                              onTap: () => setState(() => _filter = 3)),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ]),
              ),
            ),
            if (_visible.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: _search.isNotEmpty ? 'No results' : 'No tasks here',
                  subtitle: _search.isNotEmpty
                      ? 'Try a different search.'
                      : 'Add your first task below.',
                  isDark: isDark,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(delegate: SliverChildBuilderDelegate(
                      (_, i) {
                    final task = _visible[i];
                    final id   = task.id;
                    return RepaintBoundary(
                      child: GestureDetector(
                        onTap: () {
                          if (_isSelecting && id != null) {
                            _toggleSelect(id);
                          } else {
                            widget.onTap(task);
                          }
                        },
                        onLongPress: () {
                          if (id == null) return;
                          HapticFeedback.selectionClick();
                          _toggleSelect(id);
                        },
                        child: TaskCard(
                            task: task,
                            isSelected: _selectedIds.contains(id),
                            onToggleDone: () => widget.onToggle(task),
                            onDelete: () => widget.onDelete(task)),
                      ),
                    );
                  },
                  childCount: _visible.length,
                )),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _NudgeInsightCard(tasks: widget.tasks, isDark: isDark),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ]),  // end CustomScrollView
          // Bulk action bar — floats above the bottom nav when tasks are selected
          if (_isSelecting)
            Positioned(
              left: 16, right: 16, bottom: 80,
              child: _BulkActionBar(
                count: _selectedIds.length,
                onDelete: () => _doBulkDelete(context),
                onCancel: () => setState(() => _selectedIds.clear()),
              ),
            ),
        ]);  // end Stack
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DOCS TAB  — collapsible folders + search
// ══════════════════════════════════════════════════════════════════════════════

class _DocsTab extends StatefulWidget {
  final Map<String, List<NudgeDocument>> docsBySubject;
  final VoidCallback onRefresh;
  final bool isDark;
  const _DocsTab(
      {required this.docsBySubject, required this.onRefresh, required this.isDark});
  @override
  State<_DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<_DocsTab> {
  final Set<String> _expanded = {};
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _expanded.addAll(widget.docsBySubject.keys);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Map<String, List<NudgeDocument>> get _filtered {
    if (_search.isEmpty) return widget.docsBySubject;
    final q = _search.toLowerCase();
    final result = <String, List<NudgeDocument>>{};
    for (final e in widget.docsBySubject.entries) {
      if (e.key.toLowerCase().contains(q)) {
        result[e.key] = e.value;
      } else {
        final match = e.value.where((d) =>
        d.note.toLowerCase().contains(q) ||
            d.subject.toLowerCase().contains(q)).toList();
        if (match.isNotEmpty) result[e.key] = match;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = widget.isDark;
    final filtered = _filtered;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.of(context).padding.top + 24, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            NudgeSectionHeader(overline: 'Document hub', title: 'Subject Folders'),
            const SizedBox(height: 16),
            NudgeSearchBar(
              controller: _searchCtrl,
              hint: 'Search folders, files…',
              onChanged: (v) => setState(() => _search = v),
              onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      if (filtered.isEmpty)
        SliverToBoxAdapter(child: _EmptyState(
          icon: Icons.folder_open_rounded,
          title: _search.isNotEmpty ? 'No results' : 'No documents yet',
          subtitle: _search.isNotEmpty
              ? 'Try a different search.'
              : 'Share a PDF or image from any app.',
          isDark: isDark,
        ))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) {
              final entry   = filtered.entries.elementAt(i);
              final subject = entry.key;
              final docs    = entry.value;
              final color   = AppTheme.subjectColor(subject);
              final isOpen  = _expanded.contains(subject);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card(isDark),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: Column(children: [
                    InkWell(
                      onTap: () => setState(() {
                        if (isOpen) _expanded.remove(subject);
                        else _expanded.add(subject);
                      }),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.folder_rounded,
                                color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(subject, style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700,
                                  color: AppTheme.text(isDark))),
                              Text(
                                  '${docs.length} file${docs.length == 1 ? "" : "s"}',
                                  style: TextStyle(fontSize: 12,
                                      color: AppTheme.subtext(isDark))),
                            ],
                          )),
                          AnimatedRotation(
                            turns: isOpen ? 0.25 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.chevron_right_rounded,
                                color: AppTheme.subtext(isDark), size: 22),
                          ),
                        ]),
                      ),
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Column(children: [
                        Divider(color: AppTheme.border(isDark), height: 1),
                        ...List.generate(docs.length, (j) => _DocCardTile(
                          doc: docs[j], isDark: isDark,
                          isLast: j == docs.length - 1,
                        )),
                      ]),
                      crossFadeState: isOpen
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 220),
                    ),
                  ]),
                ),
              );
            },
            childCount: filtered.length,
          )),
        ),
    ]);
  }
}

class _DocCardTile extends StatelessWidget {
  final NudgeDocument doc;
  final bool isDark, isLast;
  const _DocCardTile(
      {required this.doc, required this.isDark, required this.isLast});

  IconData get _icon {
    if (doc.isPdf)   return Icons.picture_as_pdf_rounded;
    if (doc.isImage) return Icons.image_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.subjectColor(doc.subject);
    return InkWell(
      onTap: () async {
        final result = await OpenFilex.open(doc.filePath);
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cannot open: ${result.message}'),
            backgroundColor: AppTheme.danger,
          ));
        }
      },
      borderRadius: isLast
          ? const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.note.isNotEmpty ? doc.note : 'Document',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppTheme.text(isDark)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(doc.isPdf ? 'PDF · tap to open' : 'Image · tap to open',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.subtext(isDark))),
              ])),
          Icon(Icons.open_in_new_rounded,
              color: AppTheme.subtext(isDark), size: 16),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SETTINGS TAB
// ══════════════════════════════════════════════════════════════════════════════

class _SettingsTab extends StatefulWidget {
  final bool isDark;
  final VoidCallback onRefresh;
  final String userName;
  final String? profileImagePath;
  const _SettingsTab({
    required this.isDark,
    required this.onRefresh,
    this.userName = '',
    this.profileImagePath,
  });
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  String _saveLocation = 'Default (app folder)';

  Future<void> _pickSaveLocation() async {
    final isDark = widget.isDark;
    final options = ['Default (app folder)', 'Downloads', 'Documents'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border(isDark),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('File save location',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppTheme.text(isDark))),
          const SizedBox(height: 8),
          ...options.map((o) => ListTile(
            title: Text(o,
                style: TextStyle(color: AppTheme.text(isDark))),
            leading: Icon(
              o == _saveLocation
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: o == _saveLocation
                  ? AppTheme.primary : AppTheme.subtext(isDark),
            ),
            onTap: () => Navigator.pop(ctx, o),
          )),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) setState(() => _saveLocation = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = widget.isDark;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, MediaQuery.of(context).padding.top + 24, 20, 0),
          child: NudgeSectionHeader(
              overline: 'Preferences', title: 'Settings'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(delegate: SliverChildListDelegate([
          // Profile card
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
              widget.onRefresh();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                _ProfileAvatar(
                  imagePath: widget.profileImagePath,
                  name: widget.userName,
                  size: 52,
                  onGradient: true,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          widget.userName.isEmpty ? 'Student' : widget.userName,
                          style: GoogleFonts.manrope(
                              fontSize: 16, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      Text('View profile, streaks & XP',
                          style: GoogleFonts.manrope(
                              fontSize: 12, fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8))),
                    ])),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.8), size: 22),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsSection(isDark: isDark, children: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => _SettingsRow(
                icon: Icons.dark_mode_rounded,
                iconColor: const Color(0xFFAB47BC),
                title: 'Dark mode',
                isDark: isDark,
                trailing: Switch(
                  value: mode == ThemeMode.dark,
                  onChanged: (v) {
                    themeNotifier.value =
                    v ? ThemeMode.dark : ThemeMode.light;
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _SettingsSection(isDark: isDark, children: [
            _SettingsRow(
              icon: Icons.folder_rounded,
              iconColor: AppTheme.warning,
              title: 'File save location',
              subtitle: _saveLocation,
              isDark: isDark,
              onTap: _pickSaveLocation,
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 20),
            ),
          ]),
          const SizedBox(height: 16),
          _SettingsSection(isDark: isDark, children: [
            _SettingsRow(
              icon: Icons.notifications_rounded,
              iconColor: AppTheme.alert,
              title: 'Test notification',
              isDark: isDark,
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 20),
              onTap: () => NotificationService.instance.showInstant(
                title: 'Nudge is working!',
                body: 'Your reminders are all set.',
              ),
            ),
            Divider(color: AppTheme.border(isDark), height: 1, indent: 56),
            _SettingsRow(
              icon: Icons.info_outline_rounded,
              iconColor: AppTheme.primary,
              title: 'About Nudge',
              subtitle: 'Version 1.0.0',
              isDark: isDark,
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 20),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Nudge',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2026 Nudge Team',
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _SettingsSection(isDark: isDark, children: [
            _SettingsRow(
              icon: Icons.replay_rounded,
              iconColor: AppTheme.subtext(isDark),
              title: 'Reset onboarding',
              subtitle: 'Show setup again on next launch',
              isDark: isDark,
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 20),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await UserPrefs.resetOnboarding();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Onboarding will show on next launch'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 100),
        ])),
      ),
    ]);
  }
}

class _SettingsSection extends StatelessWidget {
  final List<Widget> children;
  final bool isDark;
  const _SettingsSection({required this.children, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.card(isDark),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border(isDark)),
    ),
    child: Column(children: children),
  );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isDark;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsRow(
      {required this.icon, required this.iconColor, required this.title,
        required this.isDark, this.subtitle, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w600, color: AppTheme.text(isDark))),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(
                    fontSize: 12, color: AppTheme.subtext(isDark))),
            ])),
        if (trailing != null) trailing!,
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// TASK DETAIL SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class TaskDetailScreen extends StatefulWidget {
  final Task task;
  final VoidCallback onToggle, onDelete, onEdit;
  const TaskDetailScreen(
      {super.key, required this.task,
        required this.onToggle, required this.onDelete,
        required this.onEdit});
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  List<NudgeDocument> _docs = [];
  bool _loadingDoc = false;

  @override
  void initState() { super.initState(); _loadDocs(); }

  Future<void> _loadDocs() async {
    final taskId = widget.task.id;
    if (taskId == null) return;
    setState(() => _loadingDoc = true);
    final results = <NudgeDocument>[];
    if (widget.task.docId != null) {
      final d = await DBHelper.instance.getDocumentById(widget.task.docId!);
      if (d != null) results.add(d);
    }
    final byTaskId = await DBHelper.instance.getDocumentsByTaskId(taskId);
    for (final d in byTaskId) {
      if (!results.any((r) => r.id == d.id)) results.add(d);
    }
    if (mounted) setState(() { _docs = results; _loadingDoc = false; });
  }

  String get _timeLabel {
    final task = widget.task;
    if (task.isDone) return 'Completed ✓';
    final diff = task.deadline.difference(DateTime.now());
    if (diff.isNegative) {
      final h = -diff.inHours;
      return h < 24 ? 'Overdue by ${h}h' : 'Overdue by ${-diff.inDays}d';
    }
    if (diff.inMinutes < 60) return 'Due in ${diff.inMinutes}m';
    if (diff.inHours < 24)   return 'Due in ${diff.inHours}h';
    if (diff.inDays == 1)    return 'Due tomorrow';
    return 'Due in ${diff.inDays} days';
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final task         = widget.task;
    final subjectColor = AppTheme.subjectColor(task.subject);
    final urgColor     = task.isDone
        ? AppTheme.calm : AppTheme.urgencyColor(task.deadline);
    final headerBg     = isDark ? AppTheme.darkHeaderBg : AppTheme.primary;

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      appBar: AppBar(
        backgroundColor: headerBg,
        foregroundColor: Colors.white,
        title: const Text('Task details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            onPressed: widget.onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            onPressed: widget.onDelete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.card(isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (task.priority == 'urgent' && !task.isDone)
                          _Badge(
                              label: 'URGENT',
                              bg: AppTheme.alert.withValues(alpha: 0.12),
                              fg: AppTheme.alert),
                        if (task.isDone)
                          _Badge(
                              label: 'DONE',
                              bg: AppTheme.calm.withValues(alpha: 0.12),
                              fg: AppTheme.calm),
                        const Spacer(),
                        Icon(AppTheme.taskTypeIcon(task.taskType),
                            size: 18, color: subjectColor),
                      ]),
                      const SizedBox(height: 12),
                      Text(task.name,
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: task.isDone
                                ? AppTheme.subtext(isDark) : AppTheme.text(isDark),
                            decoration:
                            task.isDone ? TextDecoration.lineThrough : null,
                          )),
                      const SizedBox(height: 16),
                      if (task.subject.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: subjectColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(task.subject,
                              style: TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: subjectColor)),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _DetailRow(
                          icon: Icons.calendar_today_rounded,
                          iconColor: urgColor,
                          label: 'Deadline',
                          value: DateFormat('EEEE, d MMMM yyyy · h:mm a')
                              .format(task.deadline),
                          valueColor: AppTheme.text(isDark)),
                      const SizedBox(height: 10),
                      _DetailRow(
                          icon: Icons.timer_outlined,
                          iconColor: urgColor,
                          label: 'Status',
                          value: _timeLabel,
                          valueColor: urgColor),
                      const SizedBox(height: 10),
                      _DetailRow(
                          icon: AppTheme.taskTypeIcon(task.taskType),
                          iconColor: AppTheme.subtext(isDark),
                          label: 'Type',
                          value: task.taskType[0].toUpperCase() +
                              task.taskType.substring(1),
                          valueColor: AppTheme.text(isDark)),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notes_rounded, size: 16,
                                color: AppTheme.subtext(isDark)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Notes', style: TextStyle(
                                    fontSize: 11, color: Color(0xFFAAAAB5),
                                    fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                _LinkifiedText(
                                  text: task.description,
                                  baseStyle: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600,
                                      color: AppTheme.text(isDark)),
                                ),
                              ],
                            )),
                          ],
                        ),
                      ],
                      if (task.referenceLinks.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...task.referenceLinks.asMap().entries.map((entry) {
                          final url = entry.value;
                          final displayUrl = url.length > 50
                              ? '${url.substring(0, 47)}…'
                              : url;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () async {
                                final uri = Uri.tryParse(url);
                                if (uri != null) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: _DetailRow(
                                icon: Icons.link_rounded,
                                iconColor: AppTheme.primary,
                                label: task.referenceLinks.length > 1
                                    ? 'Link ${entry.key + 1}'
                                    : 'Link',
                                value: displayUrl,
                                valueColor: AppTheme.primary,
                                textDecoration: TextDecoration.underline,
                              ),
                            ),
                          );
                        }),
                      ],
                    ]),
              ),
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: subjectColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_loadingDoc)
            Center(child: CircularProgressIndicator(color: AppTheme.primary))
          else if (_docs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                  'Attached document${_docs.length == 1 ? "" : "s"} (${_docs.length})',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppTheme.subtext(isDark), letterSpacing: 0.3)),
            ),
            ..._docs.map((doc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LinkedDocCard(doc: doc, isDark: isDark),
            )),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onToggle,
              icon: Icon(task.isDone
                  ? Icons.replay_rounded
                  : Icons.check_circle_outline_rounded),
              label: Text(task.isDone ? 'Mark as pending' : 'Mark as done'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                task.isDone ? AppTheme.subtext(isDark) : AppTheme.calm,
              ),
            ),
          ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED SMALL WIDGETS
// ══════════════════════════════════════════════════════════════════════════════


// ── Bulk action bar ───────────────────────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  const _BulkActionBar(
      {required this.count, required this.onDelete, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFF1A1A2E),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text('$count task${count == 1 ? "" : "s"} selected',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600,
                  fontSize: 14)),
          const Spacer(),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFFAAAAAA))),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Profile avatar ────────────────────────────────────────────────────────────

class _ProfileAvatar extends StatelessWidget {
  final String? imagePath;
  final String name;
  final double size;
  // When true the avatar sits on a dark/coloured background — use white tones.
  final bool onGradient;
  const _ProfileAvatar({
    this.imagePath, this.name = '', this.size = 40, this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final initials = name.isNotEmpty
        ? name.trim().split(RegExp(r'\s+')).take(2)
        .map((w) => w[0].toUpperCase()).join()
        : '?';
    final bgColor = onGradient
        ? Colors.white.withValues(alpha: 0.25)
        : AppTheme.primary.withValues(alpha: 0.15);
    final borderColor = onGradient
        ? Colors.white.withValues(alpha: 0.5)
        : AppTheme.primary.withValues(alpha: 0.3);
    final textColor = onGradient ? Colors.white : AppTheme.primary;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.5),
        image: hasImage
            ? DecorationImage(
            image: FileImage(import_dart_io.File(imagePath!)),
            fit: BoxFit.cover)
            : null,
      ),
      child: hasImage ? null : Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w700,
                color: textColor)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final bool isDark;
  const _SectionHeader(
      {required this.title, required this.color, required this.isDark});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(title,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: color, letterSpacing: 1.0)),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Badge({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
            color: fg, letterSpacing: 0.8)),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor, valueColor;
  final String label, value;
  final TextDecoration? textDecoration;
  const _DetailRow({required this.icon, required this.iconColor,
    required this.label, required this.value, required this.valueColor,
    this.textDecoration});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 10),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
                fontSize: 11, color: Color(0xFFAAAAB5),
                fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: valueColor,
                decoration: textDecoration,
                decorationColor: valueColor)),
          ])),
    ],
  );
}

/// Renders [text] with any http/https URLs highlighted as tappable indigo links.
class _LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _LinkifiedText({required this.text, required this.baseStyle});

  static final _urlRegex = RegExp(r'https?://\S+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: baseStyle);

    final spans = <InlineSpan>[];
    int last = 0;
    final linkStyle = baseStyle.copyWith(
      color: AppTheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppTheme.primary,
    );
    for (final match in matches) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start),
            style: baseStyle));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url.length > 50 ? '${url.substring(0, 47)}…' : url,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _LinkedDocCard extends StatelessWidget {
  final NudgeDocument doc;
  final bool isDark;
  const _LinkedDocCard({required this.doc, required this.isDark});

  bool get _fileExists => import_dart_io.File(doc.filePath).existsSync();

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.subjectColor(doc.subject);
    final isImg = doc.isImage && _fileExists;
    return GestureDetector(
      onTap: () {
        if (isImg) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _FullScreenImageViewer(
              filePath: doc.filePath,
              title: doc.note.isNotEmpty ? doc.note : 'Image',
            ),
          ));
        } else {
          OpenFilex.open(doc.filePath).then((result) {
            if (result.type != ResultType.done && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Cannot open: ${result.message}'),
                backgroundColor: AppTheme.danger,
              ));
            }
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: ListTile(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: isImg
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    import_dart_io.File(doc.filePath),
                    width: 44, height: 44,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.image_rounded, color: color, size: 24),
                    ),
                  ),
                )
              : Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                      doc.isPdf
                          ? Icons.picture_as_pdf_rounded
                          : Icons.image_rounded,
                      color: color, size: 24),
                ),
          title: Text(doc.note.isNotEmpty ? doc.note : 'Document',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDark)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              doc.isPdf ? 'PDF · tap to open'
              : isImg   ? 'Image · tap to view'
              : 'Image · tap to open',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.subtext(isDark))),
          trailing: Icon(
              isImg ? Icons.fullscreen_rounded : Icons.open_in_new_rounded,
              color: AppTheme.subtext(isDark), size: 18),
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String filePath;
  final String title;
  const _FullScreenImageViewer({required this.filePath, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(
            import_dart_io.File(filePath),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_rounded, color: Colors.white54, size: 64),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isDark;
  const _EmptyState({required this.icon, required this.title,
    required this.subtitle, required this.isDark,
    this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 40,
            color: AppTheme.subtext(isDark).withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: AppTheme.text(isDark))),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14,
                color: AppTheme.subtext(isDark))),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          TextButton(
              onPressed: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700))),
        ],
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// NUDGE INSIGHT CARD — contextual tip at bottom of Tasks tab
// ══════════════════════════════════════════════════════════════════════════════

class _NudgeInsightCard extends StatelessWidget {
  final List<Task> tasks;
  final bool isDark;
  const _NudgeInsightCard({required this.tasks, required this.isDark});

  String get _headline {
    final now = DateTime.now();
    final urgentSoon = tasks.where((t) =>
    !t.isDone &&
        !t.deadline.isBefore(now) &&
        t.deadline.difference(now).inHours < 24).length;
    final overdue = tasks.where((t) =>
    !t.isDone && t.deadline.isBefore(now)).length;
    if (overdue > 0) {
      return '$overdue overdue task${overdue == 1 ? "" : "s"} — tackle ${overdue == 1 ? "it" : "them"} first to protect your streak.';
    }
    if (urgentSoon > 0) {
      return '$urgentSoon urgent task${urgentSoon == 1 ? "" : "s"} due in the next 24 hours.';
    }
    final allDone = tasks.every((t) => t.isDone);
    if (allDone && tasks.isNotEmpty) return 'All tasks done! Great work — your streak is safe.';
    return 'Check off today\'s tasks to keep your streak going.';
  }

  String get _tip {
    final overdue = tasks.where((t) => !t.isDone && t.deadline.isBefore(DateTime.now())).length;
    if (overdue > 0) return 'Tip: complete overdue items first to keep your streak active.';
    return 'Tip: urgent tasks protect your streak — tackle them early.';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.primaryContainer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_headline,
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppTheme.primary)),
        ),
      ]),
      const SizedBox(height: 8),
      Text(_tip,
          style: GoogleFonts.manrope(
              fontSize: 12, color: AppTheme.subtext(isDark))),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// CELEBRATION SHEET — shown when a task is marked done
// ══════════════════════════════════════════════════════════════════════════════

class _CelebrationSheet extends StatelessWidget {
  final String taskName;
  final int xp, streak;
  final bool isDark;
  const _CelebrationSheet({
    required this.taskName,
    required this.xp,
    required this.streak,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.card(isDark),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      // drag handle
      Container(
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: AppTheme.border(isDark),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: 24),
      // checkmark
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.calm, Color(0xFF34D399)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
      ),
      const SizedBox(height: 16),
      Text('Task crushed!',
          style: GoogleFonts.manrope(
              fontSize: 22, fontWeight: FontWeight.w800,
              color: AppTheme.text(isDark))),
      const SizedBox(height: 6),
      Text(taskName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
              fontSize: 14, color: AppTheme.subtext(isDark))),
      const SizedBox(height: 16),
      // XP + streak pills
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLow(isDark),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('+10 XP  ·  $xp total',
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: AppTheme.primary)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLow(isDark),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(streak > 0 ? '🔥 $streak day streak' : '🚀 Start streak',
              style: GoogleFonts.manrope(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: AppTheme.calm)),
        ),
      ]),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: Text('Keep going!',
              style: GoogleFonts.manrope(
                  fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      ),
    ]),
  );
}
