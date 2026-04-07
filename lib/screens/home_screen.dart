// lib/screens/home_screen.dart
// REDESIGNED: teal theme, dark/light mode, bottom nav, collapsible doc folders,
// search in tasks + docs, settings tab with theme toggle + save location

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../database/db_helper.dart';
import '../main.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';

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
  List<Task> _todayTasks = [];
  List<Task> _allTasks   = [];
  Map<String, List<NudgeDocument>> _docsBySubject = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all  = await DBHelper.instance.getAllTasks();
    final subs = await DBHelper.instance.getSubjects();
    final docsMap = <String, List<NudgeDocument>>{};
    for (final s in subs) {
      docsMap[s] = await DBHelper.instance.getDocumentsBySubject(s);
    }
    final allDocs = await DBHelper.instance.getAllDocuments();
    final noSub   = allDocs.where((d) => d.subject.isEmpty).toList();
    if (noSub.isNotEmpty) docsMap['Uncategorised'] = noSub;
    final now = DateTime.now();
    final today = all.where((t) {
      if (t.isDone) return false;
      return t.deadline.isBefore(DateTime(now.year, now.month, now.day + 1));
    }).toList();
    if (mounted) setState(() {
      _todayTasks = today; _allTasks = all;
      _docsBySubject = docsMap; _loading = false;
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
    final updated = task.copyWith(isDone: !task.isDone);
    await DBHelper.instance.updateTask(updated);
    if (updated.isDone) await NotificationService.instance.cancelReminders(task);
    else await NotificationService.instance.scheduleReminders(updated);
    await _load();
  }

  Future<void> _deleteTask(Task task) async {
    HapticFeedback.mediumImpact();
    final ok = await _confirmDelete(context, task.name);
    if (ok) {
      await NotificationService.instance.cancelReminders(task);
      await DBHelper.instance.deleteTask(task.id!);
      await _load();
    }
  }

  Future<bool> _confirmDelete(BuildContext ctx, String name) async =>
      await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      ) ??
          false;

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
      ),
    ))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      _TodayTab(
          tasks: _todayTasks, onToggle: _toggleDone,
          onDelete: _deleteTask, onTap: _openTaskDetail,
          onAdd: _addTask, isDark: isDark),
      _AllTab(
          tasks: _allTasks, onToggle: _toggleDone,
          onDelete: _deleteTask, onTap: _openTaskDetail,
          isDark: isDark),
      _DocsTab(
          docsBySubject: _docsBySubject,
          onRefresh: _load, isDark: isDark),
      _SettingsTab(isDark: isDark, onRefresh: _load),
    ];

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : pages[_navIndex],
      floatingActionButton: _navIndex < 2
          ? FloatingActionButton.extended(
        onPressed: _addTask,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add task',
            style: TextStyle(fontWeight: FontWeight.w700)),
      )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.navBg(isDark),
          border: Border(
              top: BorderSide(
                  color: AppTheme.border(isDark), width: 0.5)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home',
                    active: _navIndex == 0,
                    onTap: () => setState(() => _navIndex = 0)),
                _NavItem(icon: Icons.explore_rounded, label: 'Tasks',
                    active: _navIndex == 1,
                    onTap: () => setState(() => _navIndex = 1)),
                _NavItem(icon: Icons.folder_rounded, label: 'Docs',
                    active: _navIndex == 2,
                    onTap: () => setState(() => _navIndex = 2)),
                _NavItem(icon: Icons.settings_rounded, label: 'Settings',
                    active: _navIndex == 3,
                    onTap: () => setState(() => _navIndex = 3)),
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 26,
            color: active ? AppTheme.primary : AppTheme.subtext(isDark)),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AppTheme.primary : AppTheme.subtext(isDark),
            )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TODAY TAB
// ══════════════════════════════════════════════════════════════════════════════

class _TodayTab extends StatelessWidget {
  final List<Task> tasks;
  final Function(Task) onToggle, onDelete, onTap;
  final VoidCallback onAdd;
  final bool isDark;
  const _TodayTab(
      {required this.tasks, required this.onToggle, required this.onDelete,
        required this.onTap, required this.onAdd, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final now      = DateTime.now();
    final h        = now.hour;
    final greet    = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    final overdue  = tasks.where((t) => t.deadline.isBefore(now)).toList();
    final upcoming = tasks.where((t) => !t.deadline.isBefore(now)).toList();
    final headerBg = isDark ? AppTheme.darkHeaderBg : AppTheme.primary;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Container(
          color: headerBg,
          padding: EdgeInsets.only(
            left: 20, right: 20,
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 28,
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greet,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                const Text("Today's Tasks",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('${tasks.length} task${tasks.length == 1 ? "" : "s"} for today',
                    style: TextStyle(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.60))),
              ]),
            ),
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(alignment: Alignment.center, children: [
                const Icon(Icons.notifications_none_rounded,
                    color: Colors.white, size: 22),
                if (tasks.isNotEmpty)
                  Positioned(top: 8, right: 8,
                      child: Container(width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFFFFB627), shape: BoxShape.circle))),
              ]),
            ),
          ]),
        ),
      ),
      if (tasks.isEmpty)
        SliverFillRemaining(child: _EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'All clear today!',
          subtitle: 'No tasks due. Enjoy your day.',
          actionLabel: 'Add a task',
          onAction: onAdd, isDark: isDark,
        ))
      else ...[
        if (overdue.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(
              title: 'OVERDUE', color: AppTheme.danger, isDark: isDark)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(delegate: SliverChildBuilderDelegate(
                  (_, i) => GestureDetector(
                onTap: () => onTap(overdue[i]),
                child: TaskCard(task: overdue[i],
                    onToggleDone: () => onToggle(overdue[i]),
                    onDelete: () => onDelete(overdue[i])),
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
                  (_, i) => GestureDetector(
                onTap: () => onTap(upcoming[i]),
                child: TaskCard(task: upcoming[i],
                    onToggleDone: () => onToggle(upcoming[i]),
                    onDelete: () => onDelete(upcoming[i])),
              ),
              childCount: upcoming.length,
            )),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ALL TASKS TAB  — with search
// ══════════════════════════════════════════════════════════════════════════════

class _AllTab extends StatefulWidget {
  final List<Task> tasks;
  final Function(Task) onToggle, onDelete, onTap;
  final bool isDark;
  const _AllTab(
      {required this.tasks, required this.onToggle, required this.onDelete,
        required this.onTap, required this.isDark});
  @override
  State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> {
  int _filter = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<Task> get _visible {
    List<Task> base;
    switch (_filter) {
      case 1: base = widget.tasks.where((t) => !t.isDone).toList(); break;
      case 2: base = widget.tasks.where((t) =>  t.isDone).toList(); break;
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
    final urgent  = widget.tasks.where((t) => !t.isDone && t.priority == 'urgent').length;
    final done    = widget.tasks.where((t) =>  t.isDone).length;
    final headerBg = isDark ? AppTheme.darkHeaderBg : AppTheme.primary;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Container(
          color: headerBg,
          padding: EdgeInsets.only(
            left: 20, right: 20,
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 24,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('My Tasks',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: -0.5)),
            const SizedBox(height: 16),
            _SearchBar(
              controller: _searchCtrl,
              hint: 'Search tasks, subjects…',
              onChanged: (v) => setState(() => _search = v),
              onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            _StatChip(label: 'Pending', value: pending, color: AppTheme.primary, isDark: isDark),
            const SizedBox(width: 8),
            _StatChip(label: 'Urgent',  value: urgent,  color: AppTheme.alert,   isDark: isDark),
            const SizedBox(width: 8),
            _StatChip(label: 'Done',    value: done,    color: AppTheme.calm,    isDark: isDark),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            _FilterChipWidget(label: 'All',     selected: _filter == 0, isDark: isDark,
                onTap: () => setState(() => _filter = 0)),
            const SizedBox(width: 8),
            _FilterChipWidget(label: 'Pending', selected: _filter == 1, isDark: isDark,
                onTap: () => setState(() => _filter = 1)),
            const SizedBox(width: 8),
            _FilterChipWidget(label: 'Done',    selected: _filter == 2, isDark: isDark,
                onTap: () => setState(() => _filter = 2)),
          ]),
        ),
      ),
      if (_visible.isEmpty)
        SliverFillRemaining(child: _EmptyState(
          icon: Icons.task_alt_rounded,
          title: _search.isNotEmpty ? 'No results' : 'No tasks here',
          subtitle: _search.isNotEmpty ? 'Try a different search.' : 'Add your first task below.',
          isDark: isDark,
        ))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => GestureDetector(
              onTap: () => widget.onTap(_visible[i]),
              child: TaskCard(task: _visible[i],
                  onToggleDone: () => widget.onToggle(_visible[i]),
                  onDelete: () => widget.onDelete(_visible[i])),
            ),
            childCount: _visible.length,
          )),
        ),
    ]);
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
    _expanded.addAll(widget.docsBySubject.keys); // open all by default
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
    final headerBg = isDark ? AppTheme.darkHeaderBg : AppTheme.primary;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Container(
          color: headerBg,
          padding: EdgeInsets.only(
            left: 20, right: 20,
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 24,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Documents',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                    color: Colors.white, letterSpacing: -0.5)),
            const SizedBox(height: 16),
            _SearchBar(
              controller: _searchCtrl,
              hint: 'Search folders, files…',
              onChanged: (v) => setState(() => _search = v),
              onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
            ),
          ]),
        ),
      ),
      if (filtered.isEmpty)
        SliverFillRemaining(child: _EmptyState(
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
                    // Folder header
                    InkWell(
                      onTap: () => setState(() {
                        if (isOpen) _expanded.remove(subject);
                        else _expanded.add(subject);
                      }),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.folder_rounded, color: color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(subject, style: TextStyle(fontSize: 14,
                                  fontWeight: FontWeight.w700, color: AppTheme.text(isDark))),
                              Text('${docs.length} file${docs.length == 1 ? "" : "s"}',
                                  style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark))),
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
                    // Expandable file list
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
  const _DocCardTile({required this.doc, required this.isDark, required this.isLast});

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
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doc.note.isNotEmpty ? doc.note : 'Document',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppTheme.text(isDark)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(doc.isPdf ? 'PDF · tap to open' : 'Image · tap to open',
                style: TextStyle(fontSize: 11, color: AppTheme.subtext(isDark))),
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
  const _SettingsTab({required this.isDark, required this.onRefresh});
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
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.border(isDark),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('File save location',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppTheme.text(isDark))),
          const SizedBox(height: 8),
          ...options.map((o) => ListTile(
            title: Text(o, style: TextStyle(color: AppTheme.text(isDark))),
            leading: Icon(
              o == _saveLocation
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: o == _saveLocation ? AppTheme.primary : AppTheme.subtext(isDark),
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
    final headerBg = isDark ? AppTheme.darkHeaderBg : AppTheme.primary;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Container(
          color: headerBg,
          padding: EdgeInsets.only(
            left: 20, right: 20,
            top: MediaQuery.of(context).padding.top + 20,
            bottom: 28,
          ),
          child: const Text('Settings',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: -0.5)),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(delegate: SliverChildListDelegate([
          const SizedBox(height: 8),
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
                  activeColor: AppTheme.primary,
                  onChanged: (v) {
                    themeNotifier.value = v ? ThemeMode.dark : ThemeMode.light;
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
              subtitle: 'Version 2.0.0',
              isDark: isDark,
              trailing: Icon(Icons.chevron_right_rounded,
                  color: AppTheme.subtext(isDark), size: 20),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Nudge',
                applicationVersion: '2.0.0',
                applicationLegalese: '© 2026 Nudge Team',
              ),
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
        Container(width: 36, height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: AppTheme.text(isDark))),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark))),
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
  final VoidCallback onToggle, onDelete;
  const TaskDetailScreen(
      {super.key, required this.task, required this.onToggle, required this.onDelete});
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (task.priority == 'urgent' && !task.isDone)
                      _Badge(label: 'URGENT',
                          bg: AppTheme.alert.withValues(alpha: 0.12),
                          fg: AppTheme.alert),
                    if (task.isDone)
                      _Badge(label: 'DONE',
                          bg: AppTheme.calm.withValues(alpha: 0.12),
                          fg: AppTheme.calm),
                    const Spacer(),
                    Icon(AppTheme.taskTypeIcon(task.taskType),
                        size: 18, color: subjectColor),
                  ]),
                  const SizedBox(height: 12),
                  Text(task.name, style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4,
                    color: task.isDone ? AppTheme.subtext(isDark) : AppTheme.text(isDark),
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                  )),
                  const SizedBox(height: 16),
                  if (task.subject.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: subjectColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(task.subject, style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w600, color: subjectColor)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _DetailRow(icon: Icons.calendar_today_rounded, iconColor: urgColor,
                      label: 'Deadline',
                      value: DateFormat('EEEE, d MMMM yyyy · h:mm a').format(task.deadline),
                      valueColor: AppTheme.text(isDark)),
                  const SizedBox(height: 10),
                  _DetailRow(icon: Icons.timer_outlined, iconColor: urgColor,
                      label: 'Status', value: _timeLabel, valueColor: urgColor),
                  const SizedBox(height: 10),
                  _DetailRow(icon: AppTheme.taskTypeIcon(task.taskType),
                      iconColor: AppTheme.subtext(isDark),
                      label: 'Type',
                      value: task.taskType[0].toUpperCase() + task.taskType.substring(1),
                      valueColor: AppTheme.text(isDark)),
                ]),
              ),
              Positioned(left: 0, top: 0, bottom: 0,
                child: Container(width: 4,
                  decoration: BoxDecoration(color: subjectColor,
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
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
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
                  ? Icons.replay_rounded : Icons.check_circle_outline_rounded),
              label: Text(task.isDone ? 'Mark as pending' : 'Mark as done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: task.isDone
                    ? AppTheme.subtext(isDark) : AppTheme.calm,
              ),
            ),
          ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar({required this.controller, required this.hint,
    required this.onChanged, required this.onClear});
  @override
  Widget build(BuildContext context) => Container(
    height: 46,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.7), size: 20),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
            icon: Icon(Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.7), size: 18),
            onPressed: onClear)
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
      ),
    ),
  );
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
    child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 1.0)),
  );
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool isDark;
  const _StatChip({required this.label, required this.value,
    required this.color, required this.isDark});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value.toString(), style: TextStyle(fontSize: 22,
            fontWeight: FontWeight.w900, color: color)),
        Text(label, style: TextStyle(fontSize: 11,
            color: color.withValues(alpha: 0.75), fontWeight: FontWeight.w500)),
      ]),
    ),
  );
}

class _FilterChipWidget extends StatelessWidget {
  final String label;
  final bool selected, isDark;
  final VoidCallback onTap;
  const _FilterChipWidget({required this.label, required this.selected,
    required this.onTap, required this.isDark});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border(isDark)),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.subtext(isDark))),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Badge({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
        color: fg, letterSpacing: 0.8)),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor, valueColor;
  final String label, value;
  const _DetailRow({required this.icon, required this.iconColor,
    required this.label, required this.value, required this.valueColor});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: iconColor),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 11, color: Color(0xFFAAAAB5), fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: valueColor)),
      ])),
    ],
  );
}

class _LinkedDocCard extends StatelessWidget {
  final NudgeDocument doc;
  final bool isDark;
  const _LinkedDocCard({required this.doc, required this.isDark});
  @override
  Widget build(BuildContext context) {
    final color = AppTheme.subjectColor(doc.subject);
    return GestureDetector(
      onTap: () async {
        final result = await OpenFilex.open(doc.filePath);
        if (result.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cannot open: ${result.message}'),
            backgroundColor: AppTheme.danger,
          ));
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border(isDark)),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(doc.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                color: color, size: 24),
          ),
          title: Text(doc.note.isNotEmpty ? doc.note : 'Document',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDark)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(doc.isPdf ? 'PDF · tap to open' : 'Image · tap to open',
              style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark))),
          trailing: Icon(Icons.open_in_new_rounded,
              color: AppTheme.subtext(isDark), size: 18),
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
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 56,
            color: AppTheme.subtext(isDark).withValues(alpha: 0.4)),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: AppTheme.text(isDark))),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.subtext(isDark))),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          TextButton(onPressed: onAction,
              child: Text(actionLabel!, style: const TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.w700))),
        ],
      ]),
    ),
  );
}
