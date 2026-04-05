// lib/screens/add_task_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../parser/task_parser.dart';
import '../theme/app_theme.dart';

class AddTaskScreen extends StatefulWidget {
  final String prefill;
  const AddTaskScreen({super.key, this.prefill = ''});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  ParsedTask? _parsed;
  bool _showReview = false;
  bool _saving = false;

  // Editable review fields
  late DateTime _deadline;
  late String _priority;
  late String _taskType;
  late String _subject;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(const Duration(days: 1, hours: 0));
    _priority = 'normal';
    _taskType = 'assignment';
    _subject  = '';
    if (widget.prefill.isNotEmpty) {
      _ctrl.text = widget.prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    }
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_showReview) setState(() => _showReview = false);
  }

  void _parse() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final r = TaskParser.parse(text);
    setState(() {
      _parsed    = r;
      _deadline  = r.deadline;
      _priority  = r.priority;
      _taskType  = r.taskType;
      _subject   = r.subject;
      _showReview = true;
    });
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(date.year, date.month, date.day,
          time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    if (!_showReview) { _parse(); return; }

    setState(() => _saving = true);
    final taskName = _parsed?.taskName ?? _ctrl.text.trim();

    Navigator.pop(context, Task(
      name:     taskName.isNotEmpty ? taskName : _ctrl.text.trim(),
      deadline: _deadline,
      priority: _priority,
      taskType: _taskType,
      subject:  _subject,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New task'),
        actions: [
          if (_showReview)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Prompt field ────────────────────────────────────────────
              const Text('What do you need to do?',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Type anything — Nudge figures out the rest',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 16),

              // Input box
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showReview
                        ? AppTheme.primary
                        : AppTheme.border,
                    width: _showReview ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    maxLines: 4,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                        height: 1.5),
                    decoration: const InputDecoration(
                      hintText:
                      'e.g. "OS assignment kal tak submit karna hai"\n'
                          'or "Maths exam Monday 9am"\n'
                          'or "Submit form today by 5pm"',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                  // Action row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: AppTheme.border)),
                    ),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () async {
                          final d = await Clipboard.getData(
                              Clipboard.kTextPlain);
                          if (d?.text != null) {
                            _ctrl.text = d!.text!;
                            setState(() => _showReview = false);
                          }
                        },
                        child: Row(children: [
                          Icon(Icons.content_paste_rounded,
                              size: 15, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text('Paste',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400)),
                        ]),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _parse,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Set reminder',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),

              // ── Example chips ───────────────────────────────────────────
              if (!_showReview) ...[
                const SizedBox(height: 16),
                Text('Try an example',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    'OS assignment kal tak urgent',
                    'Maths exam Monday 9am',
                    'Submit form today by 5pm',
                    'DBMS project next week',
                  ].map((ex) => GestureDetector(
                    onTap: () {
                      _ctrl.text = ex;
                      _parse();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(ex,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.w500)),
                    ),
                  )).toList(),
                ),
              ],

              // ── Review card (appears after parse) ───────────────────────
              if (_showReview && _parsed != null) ...[
                const SizedBox(height: 24),
                _ReviewCard(
                  parsed: _parsed!,
                  deadline: _deadline,
                  priority: _priority,
                  taskType: _taskType,
                  subject: _subject,
                  onPickDeadline: _pickDeadline,
                  onPriorityChange: (v) => setState(() => _priority = v),
                  onTypeChange: (v) => setState(() => _taskType = v),
                  onSubjectChange: (v) => setState(() => _subject = v),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : const Text('Save task'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Review card ──────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final ParsedTask parsed;
  final DateTime deadline;
  final String priority;
  final String taskType;
  final String subject;
  final VoidCallback onPickDeadline;
  final ValueChanged<String> onPriorityChange;
  final ValueChanged<String> onTypeChange;
  final ValueChanged<String> onSubjectChange;

  const _ReviewCard({
    required this.parsed,
    required this.deadline,
    required this.priority,
    required this.taskType,
    required this.subject,
    required this.onPickDeadline,
    required this.onPriorityChange,
    required this.onTypeChange,
    required this.onSubjectChange,
  });

  @override
  Widget build(BuildContext context) {
    final subjectColor = AppTheme.subjectColor(
        subject.isNotEmpty ? subject : 'default');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                  bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              const Text('Review your task',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
              const Spacer(),
              Text('Tap any field to edit',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400)),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task name
                Text(parsed.taskName,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: -0.4)),

                const SizedBox(height: 14),

                // Subject + type row
                Row(children: [
                  // Subject
                  GestureDetector(
                    onTap: () => _editSubject(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: subjectColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: subjectColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.folder_rounded,
                            size: 12, color: subjectColor),
                        const SizedBox(width: 4),
                        Text(
                          subject.isEmpty ? 'Add subject' : subject,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: subject.isEmpty
                                  ? Colors.grey.shade400
                                  : subjectColor),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Task type
                  GestureDetector(
                    onTap: () => _editType(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(AppTheme.taskTypeIcon(taskType),
                            size: 12,
                            color: const Color(0xFF888899)),
                        const SizedBox(width: 4),
                        Text(
                          taskType[0].toUpperCase() + taskType.substring(1),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF888899)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Priority
                  GestureDetector(
                    onTap: () => onPriorityChange(
                        priority == 'urgent' ? 'normal' : 'urgent'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: priority == 'urgent'
                            ? const Color(0xFFFFF0EE)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: priority == 'urgent'
                              ? const Color(0xFFFFCCBB)
                              : AppTheme.border,
                        ),
                      ),
                      child: Text(
                        priority == 'urgent' ? 'Urgent' : 'Normal',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: priority == 'urgent'
                                ? const Color(0xFF993C1D)
                                : const Color(0xFF888899)),
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 14),

                // Deadline row
                GestureDetector(
                  onTap: onPickDeadline,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 16,
                          color: AppTheme.urgencyColor(deadline)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE, d MMMM yyyy')
                                  .format(deadline),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E)),
                            ),
                            Text(
                              DateFormat('h:mm a').format(deadline),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      if (parsed.deadlineLabel != 'Unknown')
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            parsed.deadlineLabel,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_rounded,
                          size: 14, color: Colors.grey.shade400),
                    ]),
                  ),
                ),

                // Notification preview
                const SizedBox(height: 12),
                _NotifPreview(deadline: deadline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editSubject(BuildContext context) {
    final ctrl = TextEditingController(text: subject);
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
              hintText: 'e.g. Operating Systems, Maths…',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                onSubjectChange(ctrl.text.trim());
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ),
        ]),
      ),
    );
  }

  void _editType(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Task type',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...['assignment', 'exam', 'submission', 'reminder', 'meeting']
                .map((t) => ListTile(
              leading: Icon(AppTheme.taskTypeIcon(t),
                  color: AppTheme.primary),
              title: Text(t[0].toUpperCase() + t.substring(1)),
              selected: taskType == t,
              selectedTileColor:
              AppTheme.primary.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onTap: () {
                onTypeChange(t);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }
}

class _NotifPreview extends StatelessWidget {
  final DateTime deadline;
  const _NotifPreview({required this.deadline});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final chips = [
      ('1 day before',
      deadline.subtract(const Duration(days: 1)).isAfter(now)),
      ('2 hrs before',
      deadline.subtract(const Duration(hours: 2)).isAfter(now)),
      ('At deadline', deadline.isAfter(now)),
    ];
    return Row(children: [
      Icon(Icons.notifications_active_outlined,
          size: 12, color: Colors.grey.shade400),
      const SizedBox(width: 5),
      Text('Reminders:',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      const SizedBox(width: 6),
      ...chips.map((c) => Padding(
        padding: const EdgeInsets.only(right: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: c.$2
                ? AppTheme.primary.withValues(alpha: 0.08)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: c.$2
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : AppTheme.border,
            ),
          ),
          child: Text(c.$1,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.$2
                      ? AppTheme.primary
                      : Colors.grey.shade400)),
        ),
      )),
    ]);
  }
}