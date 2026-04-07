// lib/screens/add_task_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../parser/task_parser.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';

// ── Reminder model ────────────────────────────────────────────────────────────

class _Reminder {
  final String label;
  final Duration offset;
  bool enabled;
  _Reminder({required this.label, required this.offset, this.enabled = true});
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AddTaskScreen extends StatefulWidget {
  final String prefill;
  const AddTaskScreen({super.key, this.prefill = ''});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  ParsedTask? _parsed;
  bool _showReview = false;
  bool _saving     = false;

  late DateTime _deadline;
  late String   _priority;
  late String   _taskType;
  late String   _subject;

  final List<_Reminder> _reminders = [
    _Reminder(label: '1 day before', offset: const Duration(days: 1)),
    _Reminder(label: '2 hrs before', offset: const Duration(hours: 2)),
    _Reminder(label: 'At deadline',  offset: Duration.zero),
  ];

  // ── Attached files (multiple) ──────────────────────────────────────────────
  final List<({String path, String mime, String name})> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(const Duration(days: 1));
    _priority = 'normal';
    _taskType = 'assignment';
    _subject  = '';
    if (widget.prefill.isNotEmpty) {
      _ctrl.text = widget.prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
      _parsed     = r;
      _deadline   = r.deadline;
      _priority   = r.priority;
      _taskType   = r.taskType;
      _subject    = r.subject;
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
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,                          // ← allow multiple
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final f in result.files) {
        if (f.path == null) continue;
        // Avoid duplicates
        if (_attachedFiles.any((a) => a.path == f.path)) continue;
        _attachedFiles.add((
        path: f.path!,
        name: f.name,
        mime: _mimeFromExt(f.extension ?? ''),
        ));
      }
    });
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':  return 'application/pdf';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'doc':  return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:     return 'application/octet-stream';
    }
  }

  // ── Fixed custom reminder dialog — uses BottomSheet instead of AlertDialog
  // to avoid pixel overflow on small screens
  void _addCustomReminder() {
    int days = 0, hours = 0, minutes = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle bar
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFDDDDE8),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text('Custom reminder',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 6),
              Text('How long before the deadline?',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 28),

              // Three steppers side by side — each in an Expanded
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: _StepperColumn(
                      label: 'Days',
                      value: days,
                      onChanged: (v) => setSheet(() => days = v),
                    )),
                    VerticalDivider(color: Colors.grey.shade100, width: 24),
                    Expanded(child: _StepperColumn(
                      label: 'Hours',
                      value: hours,
                      onChanged: (v) => setSheet(() => hours = v),
                    )),
                    VerticalDivider(color: Colors.grey.shade100, width: 24),
                    Expanded(child: _StepperColumn(
                      label: 'Mins',
                      value: minutes,
                      onChanged: (v) => setSheet(() => minutes = v),
                    )),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final total = Duration(days: days, hours: hours, minutes: minutes);
                    if (total.inMinutes > 0) {
                      setState(() => _reminders.add(
                          _Reminder(label: _durationLabel(total), offset: total, enabled: true)));
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add reminder'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF888899))),
              ),
            ]),
          );
        },
      ),
    );
  }

  String _durationLabel(Duration d) {
    if (d.inDays >= 1)  return '${d.inDays}d before';
    if (d.inHours >= 1) return '${d.inHours}h before';
    return '${d.inMinutes}m before';
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    if (!_showReview) { _parse(); return; }
    setState(() => _saving = true);

    final taskName = _parsed?.taskName ?? _ctrl.text.trim();
    final task = Task(
      name:     taskName.isNotEmpty ? taskName : _ctrl.text.trim(),
      deadline: _deadline,
      priority: _priority,
      taskType: _taskType,
      subject:  _subject,
    );

    final id    = await DBHelper.instance.createTask(task);
    final saved = task.copyWith(id: id);

    await _scheduleSelected(saved);

    // Save all attached documents
    for (final f in _attachedFiles) {
      await DBHelper.instance.createDocument(NudgeDocument(
        filePath: f.path,
        mimeType: f.mime,
        subject:  _subject,
        note:     f.name,
        savedAt:  DateTime.now(),
        taskId:   id,
      ));
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
    );
  }

  Future<void> _scheduleSelected(Task task) async {
    await NotificationService.instance.cancelReminders(task);
    final now = DateTime.now();
    for (int i = 0; i < _reminders.length; i++) {
      final r = _reminders[i];
      if (!r.enabled) continue;
      final when = task.deadline.subtract(r.offset);
      if (when.isAfter(now)) {
        await NotificationService.instance.scheduleCustomReminder(
          id: task.id! * 100 + i,
          task: task,
          when: when,
          label: r.label,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
          ),
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
              const Text('What do you need to do?',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E), letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Type anything — Nudge figures out the rest',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 16),

              // Input box
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showReview ? AppTheme.primary : AppTheme.lightBorder,
                    width: _showReview ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    maxLines: 4, minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E), height: 1.5),
                    decoration: const InputDecoration(
                      hintText:
                      'e.g. "OS assignment kal tak submit karna hai"\n'
                          'or "Maths exam Monday 9am"\n'
                          'or "Submit form today by 5pm"',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: AppTheme.lightBorder))),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () async {
                          final d = await Clipboard.getData(Clipboard.kTextPlain);
                          if (d?.text != null) {
                            _ctrl.text = d!.text!;
                            setState(() => _showReview = false);
                          }
                        },
                        child: Row(children: [
                          Icon(Icons.content_paste_rounded, size: 15, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text('Paste', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                        ]),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _parse,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Set reminder',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),

              // Example chips
              if (!_showReview) ...[
                const SizedBox(height: 16),
                Text('Try an example',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8,
                  children: ['OS assignment kal tak urgent', 'Maths exam Monday 9am',
                    'Submit form today by 5pm', 'DBMS project next week']
                      .map((ex) => GestureDetector(
                    onTap: () { _ctrl.text = ex; _parse(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppTheme.lightCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.lightBorder)),
                      child: Text(ex, style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6C63FF), fontWeight: FontWeight.w500)),
                    ),
                  )).toList(),
                ),
              ],

              // Review card + extras
              if (_showReview && _parsed != null) ...[
                const SizedBox(height: 24),
                _ReviewCard(
                  parsed: _parsed!, deadline: _deadline,
                  priority: _priority, taskType: _taskType, subject: _subject,
                  onPickDeadline:   _pickDeadline,
                  onPriorityChange: (v) => setState(() => _priority = v),
                  onTypeChange:     (v) => setState(() => _taskType = v),
                  onSubjectChange:  (v) => setState(() => _subject = v),
                ),
                const SizedBox(height: 16),
                _RemindersSection(
                  reminders:      _reminders,
                  deadline:       _deadline,
                  onToggle:       (i) => setState(() => _reminders[i].enabled = !_reminders[i].enabled),
                  onAddCustom:    _addCustomReminder,
                  onRemoveCustom: (i) => setState(() => _reminders.removeAt(i)),
                ),
                const SizedBox(height: 16),
                _AttachmentSection(
                  files:     _attachedFiles,
                  onPick:    _pickFile,
                  onRemove:  (i) => setState(() => _attachedFiles.removeAt(i)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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

// ── Stepper column widget (replaces _NumField — no overflow) ──────────────────

class _StepperColumn extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _StepperColumn({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF888899))),
        const SizedBox(height: 12),
        // Up button
        _StepBtn(
          icon: Icons.add_rounded,
          filled: true,
          onTap: () => onChanged(value + 1),
        ),
        const SizedBox(height: 10),
        Text('$value',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 10),
        // Down button
        _StepBtn(
          icon: Icons.remove_rounded,
          filled: false,
          onTap: value > 0 ? () => onChanged(value - 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.filled, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: onTap == null
            ? const Color(0xFFF5F5F5)
            : filled
            ? AppTheme.primary
            : const Color(0xFFF0F0F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTap == null
              ? const Color(0xFFE8E8EE)
              : filled
              ? AppTheme.primary
              : const Color(0xFFDDDDE8),
        ),
      ),
      child: Icon(icon,
          size: 20,
          color: onTap == null
              ? Colors.grey.shade300
              : filled
              ? Colors.white
              : const Color(0xFF555566)),
    ),
  );
}

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final ParsedTask parsed;
  final DateTime deadline;
  final String priority, taskType, subject;
  final VoidCallback onPickDeadline;
  final ValueChanged<String> onPriorityChange, onTypeChange, onSubjectChange;

  const _ReviewCard({
    required this.parsed, required this.deadline,
    required this.priority, required this.taskType, required this.subject,
    required this.onPickDeadline, required this.onPriorityChange,
    required this.onTypeChange, required this.onSubjectChange,
  });

  @override
  Widget build(BuildContext context) {
    final sc = AppTheme.subjectColor(subject.isNotEmpty ? subject : 'default');
    return Container(
      decoration: BoxDecoration(color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppTheme.lightBorder))),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Review your task',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            Text('Tap any field to edit',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(parsed.taskName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E), letterSpacing: -0.4)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              GestureDetector(
                onTap: () => _editSubject(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sc.withValues(alpha: 0.25))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.folder_rounded, size: 12, color: sc),
                    const SizedBox(width: 4),
                    Text(subject.isEmpty ? 'Add subject' : subject,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: subject.isEmpty ? Colors.grey.shade400 : sc)),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => _editType(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.lightBorder)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppTheme.taskTypeIcon(taskType), size: 12, color: const Color(0xFF888899)),
                    const SizedBox(width: 4),
                    Text(taskType[0].toUpperCase() + taskType.substring(1),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF888899))),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => onPriorityChange(priority == 'urgent' ? 'normal' : 'urgent'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: priority == 'urgent' ? const Color(0xFFFFF0EE) : AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: priority == 'urgent' ? const Color(0xFFFFCCBB) : AppTheme.lightBorder)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(priority == 'urgent' ? Icons.bolt_rounded : Icons.flag_outlined,
                        size: 12,
                        color: priority == 'urgent' ? const Color(0xFF993C1D) : const Color(0xFF888899)),
                    const SizedBox(width: 4),
                    Text(priority == 'urgent' ? 'Urgent' : 'Normal',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: priority == 'urgent' ? const Color(0xFF993C1D) : const Color(0xFF888899))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onPickDeadline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppTheme.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lightBorder)),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.urgencyColor(deadline)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('EEEE, d MMMM yyyy').format(deadline),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                    Text(DateFormat('h:mm a').format(deadline),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ])),
                  if (parsed.deadlineLabel != 'Unknown')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(parsed.deadlineLabel,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded, size: 14, color: Colors.grey.shade400),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _editSubject(BuildContext context) {
    final ctrl = TextEditingController(text: subject);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Subject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. Operating Systems, Maths…')),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: () { onSubjectChange(ctrl.text.trim()); Navigator.pop(sheetCtx); },
                child: const Text('Done'),
              )),
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Task type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...['assignment', 'exam', 'submission', 'reminder', 'meeting'].map((t) => ListTile(
            leading: Icon(AppTheme.taskTypeIcon(t), color: AppTheme.primary),
            title: Text(t[0].toUpperCase() + t.substring(1)),
            selected: taskType == t,
            selectedTileColor: AppTheme.primary.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: () { onTypeChange(t); Navigator.pop(context); },
          )),
        ]),
      ),
    );
  }
}

// ── Reminders section ─────────────────────────────────────────────────────────

class _RemindersSection extends StatelessWidget {
  final List<_Reminder> reminders;
  final DateTime deadline;
  final ValueChanged<int> onToggle, onRemoveCustom;
  final VoidCallback onAddCustom;

  const _RemindersSection({
    required this.reminders, required this.deadline,
    required this.onToggle, required this.onAddCustom, required this.onRemoveCustom,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(color: AppTheme.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.lightBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppTheme.lightBorder))),
          child: Row(children: [
            const Icon(Icons.notifications_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Reminders',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            Text('Tap to toggle',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ...List.generate(reminders.length, (i) {
                final r = reminders[i];
                final when = deadline.subtract(r.offset);
                final possible = when.isAfter(now);
                final active = r.enabled && possible;
                final isCustom = i >= 3;
                return GestureDetector(
                  onTap:      possible ? () => onToggle(i) : null,
                  onLongPress: isCustom ? () => onRemoveCustom(i) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: !possible ? const Color(0xFFF5F5F5)
                          : active ? AppTheme.primary.withValues(alpha: 0.12)
                          : const Color(0xFFF0F0F5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !possible ? const Color(0xFFE0E0E0)
                            : active ? AppTheme.primary.withValues(alpha: 0.4)
                            : const Color(0xFFDDDDE8),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        active ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                        size: 12,
                        color: !possible ? Colors.grey.shade300
                            : active ? AppTheme.primary : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 5),
                      Text(r.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: !possible ? Colors.grey.shade300
                                : active ? AppTheme.primary : Colors.grey.shade400,
                          )),
                      if (isCustom && possible) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.close_rounded, size: 10,
                            color: active ? AppTheme.primary : Colors.grey.shade400),
                      ],
                    ]),
                  ),
                );
              }),
              GestureDetector(
                onTap: onAddCustom,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.lightSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.lightBorder)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text('Custom', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 11, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Greyed = not enough time remaining · Long-press custom to remove',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ── Attachment section (multi-file) ───────────────────────────────────────────

class _AttachmentSection extends StatelessWidget {
  final List<({String path, String mime, String name})> files;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  const _AttachmentSection({
    required this.files,
    required this.onPick,
    required this.onRemove,
  });

  IconData _iconFor(String mime) {
    if (mime == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (mime.startsWith('image/')) return Icons.image_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _colorFor(String mime) {
    if (mime == 'application/pdf') return const Color(0xFFD85A30);
    if (mime.startsWith('image/')) return const Color(0xFF378ADD);
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: AppTheme.lightBorder)),
          ),
          child: Row(children: [
            const Icon(Icons.attach_file_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Attach documents',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            if (files.isNotEmpty)
              Text('${files.length} file${files.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400))
            else
              Text('PDF, image, Word',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            // Existing files list
            if (files.isNotEmpty) ...[
              ...List.generate(files.length, (i) {
                final f = files[i];
                final color = _colorFor(f.mime);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_iconFor(f.mime), color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(f.name,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A2E)),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEEEE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: Color(0xFFA32D2D)),
                      ),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: 4),
            ],

            // Add more / first file button
            GestureDetector(
              onTap: onPick,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: files.isEmpty ? 18 : 10),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.lightBorder),
                ),
                child: files.isEmpty
                    ? Column(children: [
                  Icon(Icons.upload_file_rounded, size: 32, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Tap to attach files',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Will appear in Docs section',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade300)),
                ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_rounded, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text('Add another file',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
