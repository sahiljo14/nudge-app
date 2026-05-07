// lib/screens/doc_import_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../parser/task_parser.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/subject_editor_sheet.dart';
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

  // ── OCR state ─────────────────────────────────────────────────────────────
  bool _ocrRunning = false;
  String _ocrText  = '';
  String? _ocrError;

  bool get _isPdf  => widget.mimeType == 'application/pdf';
  bool get _isImage => widget.mimeType.startsWith('image/');

  /// The actual local file path currently being used for OCR / display.
  /// Starts as widget.fileUri but can change if user picks a new image.
  late String _currentImagePath;

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.fileUri;
    debugPrint('[DocImport] initState: fileUri=${widget.fileUri}, mime=${widget.mimeType}');
    // Auto-OCR when the shared file is an image
    if (_isImage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runOcr());
    }
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Run on-device OCR and auto-fill the prompt + task fields.
  Future<void> _runOcr() async {
    debugPrint('[DocImport] Running OCR on: $_currentImagePath');
    setState(() {
      _ocrRunning = true;
      _ocrError = null;
    });

    final text = await OCRService.extractTextFromImage(_currentImagePath);
    if (!mounted) return;

    debugPrint('[DocImport] OCR result: ${text.length} chars');
    setState(() {
      _ocrRunning = false;
      _ocrText = text;
      if (text.trim().isEmpty) {
        _ocrError = 'No text could be extracted from this image. '
            'Try a clearer photo or type below manually.';
      }
    });

    if (text.trim().isNotEmpty) {
      _promptCtrl.text = text.trim();
      _parse(); // auto-fill task fields from the extracted text
    }
  }

  /// Let user pick a new image from gallery for OCR
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    setState(() {
      _currentImagePath = picked.path;
      _ocrText = '';
      _ocrError = null;
      _showTask = false;
      _promptCtrl.clear();
      _nameCtrl.clear();
    });
    _runOcr();
  }

  /// Let user take a photo with camera for OCR
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (picked == null || !mounted) return;
    setState(() {
      _currentImagePath = picked.path;
      _ocrText = '';
      _ocrError = null;
      _showTask = false;
      _promptCtrl.clear();
      _nameCtrl.clear();
    });
    _runOcr();
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

    final p = _parsed;
    final isMulti = _showTask && p != null && p.isMultiTask && p.subtasks.isNotEmpty;

    // Save document first — one doc record holds the file regardless of how
    // many tasks reference it. The doc.note still uses the user's edited
    // single-task name when available, otherwise the raw prompt.
    final doc = NudgeDocument(
      filePath: _currentImagePath,
      mimeType: widget.mimeType,
      subject:  _subject,
      note:     _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : _promptCtrl.text.trim(),
      savedAt:  DateTime.now(),
    );
    final docId = await DBHelper.instance.createDocument(doc);

    if (isMulti) {
      int? firstTaskId;
      for (final sub in p.subtasks) {
        final task = Task(
          name:     sub.taskName,
          deadline: sub.deadline,
          priority: sub.priority,
          taskType: sub.taskType,
          subject:  sub.subject.isNotEmpty ? sub.subject : _subject,
          docId:    docId,
        );
        final id = await DBHelper.instance.createTask(task);
        final saved = task.copyWith(id: id);
        await NotificationService.instance.scheduleReminders(saved);
        firstTaskId ??= id;
      }
      if (firstTaskId != null) {
        await DBHelper.instance.updateDocument(
            doc.copyWith(id: docId, taskId: firstTaskId));
      }
    } else if (_showTask && _nameCtrl.text.trim().isNotEmpty) {
      final task = Task(
        name:     _nameCtrl.text.trim(),
        deadline: _deadline,
        priority: _priority,
        taskType: _parsed?.taskType ?? 'assignment',
        subject:  _subject,
        docId:    docId,
      );
      final taskId = await DBHelper.instance.createTask(task);
      final savedTask = task.copyWith(id: taskId);
      await NotificationService.instance.scheduleReminders(savedTask);

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor =
    AppTheme.subjectColor(_subject.isNotEmpty ? _subject : 'default');
    final imageFile = File(_currentImagePath);
    final canShowImage = _isImage && imageFile.existsSync();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_isPdf ? 'PDF document' : 'Scan Image'),
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

            // ── Image preview + OCR status ──────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border(isDark)),
              ),
              child: Column(children: [
                // Show image thumbnail if it's an image
                if (canShowImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      imageFile,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Icon(
                    _isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    size: 56,
                    color: _isPdf
                        ? const Color(0xFFD85A30)
                        : const Color(0xFF378ADD),
                  ),
                const SizedBox(height: 12),

                // OCR status message
                if (_ocrRunning) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 10),
                    Text('Extracting text from image…',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                  ]),
                ] else if (_ocrText.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF2E7D32), size: 16),
                      const SizedBox(width: 6),
                      const Text('Text extracted successfully',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32))),
                    ]),
                  ),
                ] else if (_ocrError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppTheme.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_ocrError!,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.danger,
                                height: 1.4)),
                      ),
                    ]),
                  ),
                ] else ...[
                  Text(
                    _isPdf ? 'PDF Document' : 'Shared from your device',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],

                // ── Image action buttons (change image) ──────────────────
                if (_isImage) ...[
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _ActionChip(
                      icon: Icons.photo_library_rounded,
                      label: 'Change image',
                      onTap: _pickFromGallery,
                    ),
                    const SizedBox(width: 10),
                    _ActionChip(
                      icon: Icons.camera_alt_rounded,
                      label: 'Take photo',
                      onTap: _takePhoto,
                    ),
                    if (_ocrText.isNotEmpty && !_ocrRunning) ...[
                      const SizedBox(width: 10),
                      _ActionChip(
                        icon: Icons.refresh_rounded,
                        label: 'Re-scan',
                        onTap: _runOcr,
                      ),
                    ],
                  ]),
                ],
              ]),
            ),

            const SizedBox(height: 20),

            // ── Extracted text preview (expandable, editable) ────────────
            if (_ocrText.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.text_snippet_rounded,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text('EXTRACTED TEXT',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFAAAAB5),
                        letterSpacing: 0.5)),
                const Spacer(),
                Text('${_ocrText.split('\n').length} lines',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.12)),
                ),
                child: SingleChildScrollView(
                  child: Text(_ocrText,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.text(isDark),
                          height: 1.5,
                          fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── What + when prompt ─────────────────────────────────────
            Text("What's this about?",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text(isDark),
                    letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text(_ocrText.isNotEmpty
                    ? 'Edit the parsed text or add more context'
                    : 'Type the subject + deadline in one line',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                  _showTask ? AppTheme.primary : AppTheme.border(isDark),
                  width: _showTask ? 2 : 1,
                ),
              ),
              child: Column(children: [
                TextField(
                  controller: _promptCtrl,
                  maxLines: 4,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                      fontSize: 15, color: AppTheme.text(isDark)),
                  decoration: InputDecoration(
                    hintText: _ocrText.isNotEmpty
                        ? 'Extracted text is above. Edit or add context here…'
                        : 'e.g. "OS assignment brief, submit Friday 11pm"\n'
                            'or "Maths unit test syllabus, exam Monday 9am"',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  onSubmitted: (_) => _parse(),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: AppTheme.border(isDark))),
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
            if (_showTask &&
                _parsed != null &&
                _parsed!.isMultiTask &&
                _parsed!.subtasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              Divider(color: AppTheme.border(isDark)),
              const SizedBox(height: 16),
              _DocMultiTaskBanner(count: _parsed!.subtasks.length),
              const SizedBox(height: 12),
              ..._parsed!.subtasks.map(
                  (s) => _DocMultiTaskTile(parsed: s, isDark: isDark)),
            ] else if (_showTask) ...[
              const SizedBox(height: 20),
              Divider(color: AppTheme.border(isDark)),
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
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text(isDark)),
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
                  onTap: () => setState(() => _priority =
                  _priority == 'urgent' ? 'normal' : 'urgent'),
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

              const SizedBox(height: 14),

              // Deadline
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border(isDark)),
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
                    : Text(
                    _showTask
                        ? (_parsed?.isMultiTask == true &&
                                (_parsed?.subtasks.isNotEmpty ?? false)
                            ? 'Save doc + ${_parsed!.subtasks.length} tasks'
                            : 'Save doc + task')
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
                  side: BorderSide(color: AppTheme.border(isDark)),
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

// ── Small action chip widget ─────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _DocMultiTaskBanner extends StatelessWidget {
  final int count;
  const _DocMultiTaskBanner({required this.count});

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
            '$count tasks detected — all linked to this document',
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

class _DocMultiTaskTile extends StatelessWidget {
  final ParsedTask parsed;
  final bool isDark;
  const _DocMultiTaskTile({required this.parsed, required this.isDark});

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
