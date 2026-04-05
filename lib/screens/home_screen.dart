// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';
import 'doc_import_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Task> _todayTasks = [];
  List<Task> _allTasks   = [];
  List<String> _subjects  = [];
  Map<String, List<NudgeDocument>> _docsBySubject = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final today   = await DBHelper.instance.getTodayTasks();
    final all     = await DBHelper.instance.getAllTasks();
    final subs    = await DBHelper.instance.getSubjects();
    final docsMap = <String, List<NudgeDocument>>{};
    for (final s in subs) {
      docsMap[s] = await DBHelper.instance.getDocumentsBySubject(s);
    }
    // Docs with no subject
    final allDocs = await DBHelper.instance.getAllDocuments();
    final noSub   = allDocs.where((d) => d.subject.isEmpty).toList();
    if (noSub.isNotEmpty) docsMap['Uncategorised'] = noSub;

    setState(() {
      _todayTasks    = today;
      _allTasks      = all;
      _subjects      = subs;
      _docsBySubject = docsMap;
      _loading       = false;
    });
  }

  Future<void> _addTask() async {
    HapticFeedback.lightImpact();
    final task = await Navigator.of(context).push<Task>(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const AddTaskScreen(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
    if (task != null) {
      final id = await DBHelper.instance.createTask(task);
      final saved = task.copyWith(id: id);
      await NotificationService.instance.scheduleReminders(saved);
      await _load();
    }
  }

  Future<void> _toggleDone(Task task) async {
    HapticFeedback.selectionClick();
    final updated = task.copyWith(isDone: !task.isDone);
    await DBHelper.instance.updateTask(updated);
    if (updated.isDone) {
      await NotificationService.instance.cancelReminders(task);
    } else {
      await NotificationService.instance.scheduleReminders(updated);
    }
    await _load();
  }

  Future<void> _deleteTask(Task task) async {
    HapticFeedback.mediumImpact();
    final ok = await _confirmDelete(task.name);
    if (ok) {
      await NotificationService.instance.cancelReminders(task);
      await DBHelper.instance.deleteTask(task.id!);
      await _load();
    }
  }

  Future<bool> _confirmDelete(String name) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete task?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('"$name"',
            style: const TextStyle(color: Color(0xFF666680))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFA32D2D))),
          ),
        ],
      ),
    ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Nudge'),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => NotificationService.instance.showInstant(
              title: 'Nudge is working!',
              body: 'Your reminders are all set.',
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
          labelColor: AppTheme.primary,
          unselectedLabelColor: const Color(0xFFAAAAB5),
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'All tasks'),
            Tab(text: 'Docs'),
          ],
        ),
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
        controller: _tabs,
        children: [
          _TodayTab(
              tasks: _todayTasks,
              onToggle: _toggleDone,
              onDelete: _deleteTask,
              onAdd: _addTask),
          _AllTab(
              tasks: _allTasks,
              onToggle: _toggleDone,
              onDelete: _deleteTask),
          _DocsTab(
              docsBySubject: _docsBySubject,
              onRefresh: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTask,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add task',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Today tab ─────────────────────────────────────────────────────────────

class _TodayTab extends StatelessWidget {
  final List<Task> tasks;
  final Function(Task) onToggle;
  final Function(Task) onDelete;
  final VoidCallback onAdd;

  const _TodayTab({
    required this.tasks,
    required this.onToggle,
    required this.onDelete,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final now   = DateTime.now();
    final h     = now.hour;
    final greet = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    final overdue  = tasks.where((t) => t.deadline.isBefore(now)).toList();
    final upcoming = tasks.where((t) => !t.deadline.isBefore(now)).toList();

    return RefreshIndicator(
      onRefresh: () async {},
      color: AppTheme.primary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greet,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  const Text("Today's tasks",
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A1A2E),
                          letterSpacing: -0.8)),
                ],
              ),
            ),
          ),
          if (tasks.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'All clear today!',
                subtitle: 'No tasks due today. Enjoy your day.',
                actionLabel: 'Add a task',
                onAction: onAdd,
              ),
            )
          else ...[
            if (overdue.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Overdue',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA32D2D),
                          letterSpacing: 0.5)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (_, i) => TaskCard(
                        task: overdue[i],
                        onToggleDone: () => onToggle(overdue[i]),
                        onDelete: () => onDelete(overdue[i])),
                    childCount: overdue.length,
                  ),
                ),
              ),
            ],
            if (upcoming.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Coming up',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF666680),
                          letterSpacing: 0.5)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (_, i) => TaskCard(
                        task: upcoming[i],
                        onToggleDone: () => onToggle(upcoming[i]),
                        onDelete: () => onDelete(upcoming[i])),
                    childCount: upcoming.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ],
      ),
    );
  }
}

// ── All tasks tab ─────────────────────────────────────────────────────────

class _AllTab extends StatefulWidget {
  final List<Task> tasks;
  final Function(Task) onToggle;
  final Function(Task) onDelete;
  const _AllTab(
      {required this.tasks, required this.onToggle, required this.onDelete});
  @override
  State<_AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<_AllTab> {
  int _filter = 0; // 0=All 1=Pending 2=Done

  List<Task> get _visible {
    switch (_filter) {
      case 1: return widget.tasks.where((t) => !t.isDone).toList();
      case 2: return widget.tasks.where((t) => t.isDone).toList();
      default: return widget.tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.tasks.where((t) => !t.isDone).length;
    final urgent  = widget.tasks
        .where((t) => !t.isDone && t.priority == 'urgent').length;
    final done    = widget.tasks.where((t) => t.isDone).length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              _StatChip(label: 'Pending', value: pending,
                  color: AppTheme.primary),
              const SizedBox(width: 8),
              _StatChip(label: 'Urgent', value: urgent,
                  color: const Color(0xFF993C1D)),
              const SizedBox(width: 8),
              _StatChip(label: 'Done', value: done,
                  color: const Color(0xFF3B6D11)),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              _FilterChip(label: 'All', selected: _filter == 0,
                  onTap: () => setState(() => _filter = 0)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Pending', selected: _filter == 1,
                  onTap: () => setState(() => _filter = 1)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Done', selected: _filter == 2,
                  onTap: () => setState(() => _filter = 2)),
            ]),
          ),
        ),
        if (_visible.isEmpty)
          SliverFillRemaining(
            child: _EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No tasks here',
              subtitle: 'Add your first task using the button below.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) => TaskCard(
                    task: _visible[i],
                    onToggleDone: () => widget.onToggle(_visible[i]),
                    onDelete: () => widget.onDelete(_visible[i])),
                childCount: _visible.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Docs tab ──────────────────────────────────────────────────────────────

class _DocsTab extends StatelessWidget {
  final Map<String, List<NudgeDocument>> docsBySubject;
  final VoidCallback onRefresh;
  const _DocsTab(
      {required this.docsBySubject, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (docsBySubject.isEmpty) {
      return _EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'No documents yet',
        subtitle:
        'Share a PDF or image from any app and it will appear here.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: docsBySubject.entries.map((entry) {
        final subject = entry.key;
        final docs    = entry.value;
        final color   = AppTheme.subjectColor(subject);

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(subject,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(width: 6),
                Text('${docs.length}',
                    style: TextStyle(
                        fontSize: 12,
                        color: color.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500)),
              ]),
              const SizedBox(height: 8),
              ...docs.map((doc) => _DocCard(doc: doc, onRefresh: onRefresh)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DocCard extends StatelessWidget {
  final NudgeDocument doc;
  final VoidCallback onRefresh;
  const _DocCard({required this.doc, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.subjectColor(doc.subject);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            doc.isPdf
                ? Icons.picture_as_pdf_rounded
                : Icons.image_rounded,
            color: color, size: 22,
          ),
        ),
        title: Text(
          doc.note.isNotEmpty ? doc.note : 'Document',
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A2E)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          doc.isPdf ? 'PDF' : 'Image',
          style: const TextStyle(
              fontSize: 12, color: Color(0xFFAAAAB5)),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Color(0xFFCCCCD8)),
        onTap: () async {
          // Linked task info
          if (doc.taskId != null) {
            final task =
            await DBHelper.instance.getTaskById(doc.taskId!);
            if (task != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Linked task: ${task.name}'),
                backgroundColor: color,
              ));
            }
          }
        },
      ),
    );
  }
}

// ── Reusable small widgets ────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value.toString(),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? AppTheme.primary
              : AppTheme.border,
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : const Color(0xFF888899))),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: const Color(0xFFDDDDE8)),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFFAAAAB5))),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    ),
  );
}