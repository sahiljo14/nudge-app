// lib/screens/text_import_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../parser/task_parser.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
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
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final task = Task(
      name:     _nameCtrl.text.trim(),
      deadline: _deadline,
      priority: _priority,
      taskType: _taskType,
      subject:  _subject,
    );
    final id    = await DBHelper.instance.createTask(task);
    final saved = task.copyWith(id: id);
    await NotificationService.instance.scheduleReminders(saved);
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
                  style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1A1A2E),
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
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E)),
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
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E)),
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
                    : const Text('Save as task'),
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

  void _editSubject(BuildContext context) {
    final ctrl = TextEditingController(text: _subject);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Subject',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'e.g. Operating Systems, Maths…'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => _subject = ctrl.text.trim());
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ),
        ]),
      ),
    );
  }
}