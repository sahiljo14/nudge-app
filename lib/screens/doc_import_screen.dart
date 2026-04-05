// lib/screens/doc_import_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../parser/task_parser.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class DocImportScreen extends StatefulWidget {
  final String fileUri;
  final String mimeType;
  const DocImportScreen(
      {super.key, required this.fileUri, required this.mimeType});
  @override
  State<DocImportScreen> createState() => _DocImportScreenState();
}

class _DocImportScreenState extends State<DocImportScreen> {
  final _promptCtrl = TextEditingController();
  final _nameCtrl   = TextEditingController();

  ParsedTask? _parsed;
  bool _showTask  = false;
  bool _saving    = false;
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  String _priority = 'normal';
  String _subject  = '';

  bool get _isPdf => widget.mimeType == 'application/pdf';

  @override
  void dispose() {
    _promptCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _promptCtrl.text.trim();
    if (text.isEmpty) return;
    final r = TaskParser.parse(text);
    setState(() {
      _parsed   = r;
      _deadline = r.deadline;
      _priority = r.priority;
      _subject  = r.subject;
      _nameCtrl.text =
      r.taskName.length > 2 ? r.taskName : text;
      _showTask = true;
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

    // Save document first
    final doc = NudgeDocument(
      filePath: widget.fileUri,
      mimeType: widget.mimeType,
      subject:  _subject,
      note:     _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : _promptCtrl.text.trim(),
      savedAt:  DateTime.now(),
    );
    final docId = await DBHelper.instance.createDocument(doc);

    // Save linked task if user filled the prompt
    int? taskId;
    if (_showTask && _nameCtrl.text.trim().isNotEmpty) {
      final task = Task(
        name:     _nameCtrl.text.trim(),
        deadline: _deadline,
        priority: _priority,
        taskType: _parsed?.taskType ?? 'assignment',
        subject:  _subject,
        docId:    docId,
      );
      taskId = await DBHelper.instance.createTask(task);
      final savedTask = task.copyWith(id: taskId);
      await NotificationService.instance.scheduleReminders(savedTask);

      // Link task back to doc
      await DBHelper.instance.updateDocument(
          doc.copyWith(id: docId, taskId: taskId));
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
    final subColor =
    AppTheme.subjectColor(_subject.isNotEmpty ? _subject : 'default');

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(_isPdf ? 'PDF document' : 'Image'),
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

            // ── Doc preview ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(children: [
                Icon(
                  _isPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded,
                  size: 56,
                  color: _isPdf
                      ? const Color(0xFFD85A30)
                      : const Color(0xFF378ADD),
                ),
                const SizedBox(height: 10),
                Text(
                  _isPdf ? 'PDF Document' : 'Image',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Shared from your device',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            // ── What + when prompt ─────────────────────────────────────
            const Text("What's this about?",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                    letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text('Type the subject + deadline in one line',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                  _showTask ? AppTheme.primary : AppTheme.border,
                  width: _showTask ? 2 : 1,
                ),
              ),
              child: Column(children: [
                TextField(
                  controller: _promptCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFF1A1A2E)),
                  decoration: const InputDecoration(
                    hintText:
                    'e.g. "OS assignment brief, submit Friday 11pm"\n'
                        'or "Maths unit test syllabus, exam Monday 9am"',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  onSubmitted: (_) => _parse(),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(children: [
                    Text('Just describe it naturally',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400)),
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
                        child: const Text('Set deadline',
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

            // ── Task review ────────────────────────────────────────────
            if (_showTask) ...[
              const SizedBox(height: 20),
              const Divider(color: AppTheme.border),
              const SizedBox(height: 16),

              // Task name
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
                decoration: const InputDecoration(hintText: 'Task name'),
              ),

              const SizedBox(height: 14),

              // Subject + Priority
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _editSubject(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: _subject.isEmpty
                            ? AppTheme.card
                            : subColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _subject.isEmpty
                              ? AppTheme.border
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
                  onTap: () => setState(() => _priority =
                  _priority == 'urgent' ? 'normal' : 'urgent'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _priority == 'urgent'
                          ? const Color(0xFFFFF0EE)
                          : AppTheme.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _priority == 'urgent'
                            ? const Color(0xFFFFCCBB)
                            : AppTheme.border,
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

              const SizedBox(height: 14),

              // Deadline
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
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
                                fontSize: 12,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_rounded,
                        size: 14, color: Colors.grey.shade400),
                  ]),
                ),
              ),
            ],

            // ── Save / Skip ────────────────────────────────────────────
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : Text(_showTask
                    ? 'Save doc + task'
                    : 'Save document only'),
              ),
            ),
            if (!_showTask) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'No deadline? Save the doc and add a task later.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade400),
                ),
              ),
            ],
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
                  side: const BorderSide(color: AppTheme.border),
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