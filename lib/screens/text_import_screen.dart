// lib/screens/text_import_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../parser/task_parser.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/subject_editor_sheet.dart';
import 'home_screen.dart';

class TextImportScreen extends StatefulWidget {
  final String sharedText;
  const TextImportScreen({super.key, required this.sharedText});
  @override
  State<TextImportScreen> createState() => _TextImportScreenState();
}

class _TextImportScreenState extends State<TextImportScreen> {
  late ParsedTask _parsed;
  final _nameCtrl    = TextEditingController();
  final _promptCtrl  = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _linkCtrl    = TextEditingController();
  late DateTime _deadline;
  late String _priority;
  late String _taskType;
  late String _subject;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parsed   = TaskParser.parse(widget.sharedText);
    _deadline = _parsed.deadline;
    _priority = _parsed.priority;
    _taskType = _parsed.taskType;
    _subject  = _parsed.subject;
    _nameCtrl.text = _parsed.taskName.length > 2
        ? _parsed.taskName
        : widget.sharedText.length > 80
        ? widget.sharedText.substring(0, 80)
        : widget.sharedText;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    _descCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  void _refine() {
    if (_promptCtrl.text.trim().isEmpty) return;
    final combined =
        '${widget.sharedText} ${_promptCtrl.text.trim()}';
    final r = TaskParser.parse(combined);
    setState(() {
      _parsed   = r;
      _deadline = r.deadline;
      _priority = r.priority;
      _taskType = r.taskType;
      _subject  = r.subject;
      if (r.taskName.length > 2) _nameCtrl.text = r.taskName;
    });
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(date.year, date.month, date.day,
          time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    if (_parsed.isMultiTask && _parsed.subtasks.isNotEmpty) {
      // Multi-task: persist every detected subtask with its own parsed fields.
      // The shared description/link from this screen apply to every subtask
      // because we cannot infer which note belongs to which task.
      final desc = _descCtrl.text.trim();
      final link = _linkCtrl.text.trim();
      for (final sub in _parsed.subtasks) {
        final task = Task(
          name:          sub.taskName,
          deadline:      sub.deadline,
          priority:      sub.priority,
          taskType:      sub.taskType,
          subject:       sub.subject.isNotEmpty ? sub.subject : _subject,
          description:   desc,
          referenceLink: link,
        );
        final id    = await DBHelper.instance.createTask(task);
        final saved = task.copyWith(id: id);
        await NotificationService.instance.scheduleReminders(saved);
      }
    } else {
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _saving = false);
        return;
      }
      final task = Task(
        name:          _nameCtrl.text.trim(),
        deadline:      _deadline,
        priority:      _priority,
        taskType:      _taskType,
        subject:       _subject,
        description:   _descCtrl.text.trim(),
        referenceLink: _linkCtrl.text.trim(),
      );
      final id    = await DBHelper.instance.createTask(task);
      final saved = task.copyWith(id: id);
      await NotificationService.instance.scheduleReminders(saved);
    }

    setState(() => _saving = false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = AppTheme.subjectColor(
        _subject.isNotEmpty ? _subject : 'default');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Shared message'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Original message ──────────────────────────────────────
            const Text('Message',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAAAAB5),
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border(Theme.of(context).brightness == Brightness.dark)),
              ),
              child: Text(widget.sharedText,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.text(isDark),
                      height: 1.55)),
            ),

            // ── Extra prompt ──────────────────────────────────────────
            const SizedBox(height: 16),
            const Text('Add context (optional)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAAAAB5),
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. "this is due Friday 11pm"',
                  ),
                  onSubmitted: (_) => _refine(),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _refine,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_fix_high_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ]),

            const SizedBox(height: 24),
            Divider(color: AppTheme.border(Theme.of(context).brightness == Brightness.dark)),
            const SizedBox(height: 16),

            // ── Multi-task banner + list (replaces single-task fields) ──
            if (_parsed.isMultiTask && _parsed.subtasks.isNotEmpty) ...[
              _MultiTaskBanner(count: _parsed.subtasks.length),
              const SizedBox(height: 12),
              ..._parsed.subtasks.map(
                  (s) => _MultiTaskTile(parsed: s, isDark: isDark)),
              const SizedBox(height: 16),
            ] else ...[
            // ── Task name ─────────────────────────────────────────────
            const Text('Task name',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAAAAB5),
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text(isDark)),
              decoration: const InputDecoration(
                  hintText: 'Task name'),
            ),

            const SizedBox(height: 16),

            // ── Subject + Type + Priority ─────────────────────────────
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _editSubject(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _subject.isEmpty
                          ? AppTheme.lightCard
                          : subColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _subject.isEmpty
                            ? AppTheme.border(isDark)
                            : subColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Subject',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          _subject.isEmpty ? 'Tap to add' : _subject,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _subject.isEmpty
                                  ? Colors.grey.shade400
                                  : subColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() =>
                _priority = _priority == 'urgent' ? 'normal' : 'urgent'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _priority == 'urgent'
                        ? const Color(0xFFFFF0EE)
                        : AppTheme.lightCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _priority == 'urgent'
                          ? const Color(0xFFFFCCBB)
                          : AppTheme.border(isDark),
                    ),
                  ),
                  child: Text(
                    _priority == 'urgent' ? 'Urgent' : 'Normal',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _priority == 'urgent'
                            ? const Color(0xFF993C1D)
                            : const Color(0xFF888899)),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            // ── Deadline ──────────────────────────────────────────────
            GestureDetector(
              onTap: _pickDeadline,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border(Theme.of(context).brightness == Brightness.dark)),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 18,
                      color: AppTheme.urgencyColor(_deadline)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, d MMMM yyyy')
                              .format(_deadline),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.text(isDark)),
                        ),
                        Text(
                          DateFormat('h:mm a').format(_deadline),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  if (_parsed.deadlineLabel != 'Unknown')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_parsed.deadlineLabel,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_rounded,
                      size: 14, color: Colors.grey.shade400),
                ]),
              ),
            ),
            ],

            const SizedBox(height: 16),

            // ── Description + Link ────────────────────────────────────
            TextField(
              controller: _descCtrl,
              maxLines: 2, minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Notes or description (optional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'Reference link (optional)',
              ),
            ),

            const SizedBox(height: 32),

            // ── Save ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : Text(_parsed.isMultiTask && _parsed.subtasks.isNotEmpty
                        ? 'Save ${_parsed.subtasks.length} tasks'
                        : 'Save as task'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (_) => false,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF888899),
                  side: BorderSide(color: AppTheme.border(Theme.of(context).brightness == Brightness.dark)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Discard'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSubject(BuildContext context) async {
    final result = await showSubjectEditor(context, initial: _subject);
    if (result == null || !mounted) return;
    setState(() => _subject = result);
  }
}

class _MultiTaskBanner extends StatelessWidget {
  final int count;
  const _MultiTaskBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.layers_rounded, size: 18, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$count tasks detected — saved separately with their own deadlines',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary),
          ),
        ),
      ]),
    );
  }
}

class _MultiTaskTile extends StatelessWidget {
  final ParsedTask parsed;
  final bool isDark;
  const _MultiTaskTile({required this.parsed, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final subColor = AppTheme.subjectColor(
        parsed.subject.isNotEmpty ? parsed.subject : 'default');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: subColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(AppTheme.taskTypeIcon(parsed.taskType),
              size: 18, color: subColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parsed.taskName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text(isDark))),
              const SizedBox(height: 2),
              Text(
                  '${DateFormat('EEE, d MMM').format(parsed.deadline)} · '
                  '${DateFormat('h:mm a').format(parsed.deadline)}'
                  '${parsed.subject.isNotEmpty ? ' · ${parsed.subject}' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.subtext(isDark))),
            ],
          ),
        ),
        if (parsed.priority == 'urgent')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.alert.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Urgent',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.alert)),
          ),
      ]),
    );
  }
}