// lib/screens/ocr_scan_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../parser/task_parser.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../theme/app_theme.dart';
import '../widgets/subject_editor_sheet.dart';
import 'home_screen.dart';

class _MutableTask {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final List<TextEditingController> linkCtrls;
  final List<({String path, String mime, String name})> attachedFiles;
  DateTime deadline;
  String taskType;
  String subject;
  String priority;

  _MutableTask.fromParsed(ParsedTask p)
      : nameCtrl     = TextEditingController(text: p.taskName),
        descCtrl     = TextEditingController(),
        linkCtrls    = [TextEditingController()],
        attachedFiles = [],
        deadline = p.deadline,
        taskType = p.taskType,
        subject  = p.subject,
        priority = p.priority;

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    for (final c in linkCtrls) c.dispose();
  }
}

/// Standalone OCR screen accessible from within the app.
///
/// Lets the user pick from gallery or take a photo, then runs
/// on-device OCR, parses task info, and allows full editing.
class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});
  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  String? _imagePath;
  bool _ocrRunning = false;
  String _ocrText  = '';
  String? _ocrError;

  final _promptCtrl = TextEditingController();
  final _nameCtrl   = TextEditingController();
  final _descCtrl   = TextEditingController();
  final List<TextEditingController> _linkCtrls = [TextEditingController()];
  final List<({String path, String mime, String name})> _attachedFiles = [];
  final List<_MutableTask> _multiTasks = [];
  bool _detailsExpanded = false;

  ParsedTask? _parsed;
  bool _showTask  = false;
  bool _saving    = false;
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  String _priority = 'normal';
  String _subject  = '';

  @override
  void dispose() {
    _promptCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _linkCtrls) c.dispose();
    for (final t in _multiTasks) t.dispose();
    super.dispose();
  }

  // ── Image source ─────────────────────────────────────────────────────────
  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    _setNewImage(picked.path);
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (picked == null || !mounted) return;
    _setNewImage(picked.path);
  }

  void _setNewImage(String path) {
    setState(() {
      _imagePath = path;
      _ocrText = '';
      _ocrError = null;
      _showTask = false;
      _promptCtrl.clear();
      _nameCtrl.clear();
    });
    _runOcr();
  }

  Future<void> _runOcr() async {
    if (_imagePath == null) return;
    debugPrint('[OcrScan] Running OCR on: $_imagePath');
    setState(() {
      _ocrRunning = true;
      _ocrError = null;
    });

    final text = await OCRService.extractTextFromImage(_imagePath!);
    if (!mounted) return;

    debugPrint('[OcrScan] OCR result: ${text.length} chars');
    setState(() {
      _ocrRunning = false;
      _ocrText = text;
      if (text.trim().isEmpty) {
        _ocrError = 'No text could be extracted. Try a clearer photo.';
      }
    });

    if (text.trim().isNotEmpty) {
      _promptCtrl.text = text.trim();
      _parse();
    }
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
      _nameCtrl.text = r.taskName.length > 2 ? r.taskName : text;
      _showTask = true;

      for (final t in _multiTasks) t.dispose();
      _multiTasks.clear();
      if (r.isMultiTask && r.subtasks.isNotEmpty) {
        _multiTasks.addAll(r.subtasks.map(_MutableTask.fromParsed));
      }
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

  Future<void> _pickDeadlineFor(int index) async {
    final initial = _multiTasks[index].deadline;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _multiTasks[index].deadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _addLink() => setState(() => _linkCtrls.add(TextEditingController()));

  void _removeLink(int i) => setState(() {
    _linkCtrls[i].dispose();
    _linkCtrls.removeAt(i);
  });

  void _addLinkFor(int i) =>
      setState(() => _multiTasks[i].linkCtrls.add(TextEditingController()));

  void _removeLinkFor(int i, int j) => setState(() {
    _multiTasks[i].linkCtrls[j].dispose();
    _multiTasks[i].linkCtrls.removeAt(j);
  });

  void _removeFileFor(int i, int j) =>
      setState(() => _multiTasks[i].attachedFiles.removeAt(j));

  Future<void> _addAttachmentPhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() {
      if (_attachedFiles.any((a) => a.path == photo.path)) return;
      _attachedFiles.add((path: photo.path, name: photo.name, mime: 'image/jpeg'));
    });
  }

  Future<void> _addAttachmentFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final f in result.files) {
        if (f.path == null) continue;
        if (_attachedFiles.any((a) => a.path == f.path)) continue;
        _attachedFiles.add((
          path: f.path!,
          name: f.name,
          mime: _mimeFromExt(f.extension ?? ''),
        ));
      }
    });
  }

  Future<void> _takePhotoFor(int i) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() {
      if (_multiTasks[i].attachedFiles.any((a) => a.path == photo.path)) return;
      _multiTasks[i].attachedFiles.add((path: photo.path, name: photo.name, mime: 'image/jpeg'));
    });
  }

  Future<void> _pickFileFor(int i) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final f in result.files) {
        if (f.path == null) continue;
        if (_multiTasks[i].attachedFiles.any((a) => a.path == f.path)) continue;
        _multiTasks[i].attachedFiles.add((
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

  String _normalizeUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://$url';
    }
    return url;
  }

  Future<void> _save() async {
    final p = _parsed;
    final isMulti = p != null && p.isMultiTask && _multiTasks.isNotEmpty;
    if (!isMulti && _nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    int? docId;
    if (_imagePath != null) {
      final doc = NudgeDocument(
        filePath: _imagePath!,
        mimeType: 'image/jpeg',
        subject:  _subject,
        note:     isMulti
            ? _promptCtrl.text.trim()
            : _nameCtrl.text.trim(),
        savedAt:  DateTime.now(),
      );
      docId = await DBHelper.instance.createDocument(doc);
    }

    if (isMulti) {
      for (final mt in _multiTasks) {
        final name = mt.nameCtrl.text.trim();
        final mtLinkStr = mt.linkCtrls
            .map((c) => _normalizeUrl(c.text.trim()))
            .where((s) => s.isNotEmpty)
            .join('\n');
        final task = Task(
          name:          name.isNotEmpty ? name : _promptCtrl.text.trim(),
          deadline:      mt.deadline,
          priority:      mt.priority,
          taskType:      mt.taskType,
          subject:       mt.subject.isNotEmpty ? mt.subject : _subject,
          docId:         docId,
          description:   mt.descCtrl.text.trim(),
          referenceLink: mtLinkStr,
        );
        final id = await DBHelper.instance.createTask(task);
        final saved = task.copyWith(id: id);
        await NotificationService.instance.scheduleReminders(saved);
        for (final f in mt.attachedFiles) {
          await DBHelper.instance.createDocument(NudgeDocument(
            filePath: f.path,
            mimeType: f.mime,
            subject:  task.subject,
            note:     f.name,
            savedAt:  DateTime.now(),
            taskId:   id,
          ));
        }
      }
    } else {
      final linkStr = _linkCtrls
          .map((c) => _normalizeUrl(c.text.trim()))
          .where((s) => s.isNotEmpty)
          .join('\n');
      final task = Task(
        name:          _nameCtrl.text.trim(),
        deadline:      _deadline,
        priority:      _priority,
        taskType:      _parsed?.taskType ?? 'assignment',
        subject:       _subject,
        docId:         docId,
        description:   _descCtrl.text.trim(),
        referenceLink: linkStr,
      );
      final id = await DBHelper.instance.createTask(task);
      final saved = task.copyWith(id: id);
      await NotificationService.instance.scheduleReminders(saved);
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
      appBar: AppBar(title: const Text('Scan Image')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── No image yet → prompt to select ─────────────────────────
            if (_imagePath == null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 40),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryContainer],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.document_scanner_rounded,
                        color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text('Scan a document or schedule',
                      style: GoogleFonts.manrope(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: AppTheme.text(isDark))),
                  const SizedBox(height: 6),
                  Text(
                    'Take a photo or pick from gallery.\n'
                        'Nudge will extract text and create tasks automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade500,
                        height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _BigActionButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: _takePhoto,
                    ),
                    const SizedBox(width: 16),
                    _BigActionButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      onTap: _pickFromGallery,
                    ),
                  ]),
                ]),
              ),
            ]

            // ── Image selected → show preview + OCR results ──────────────
            else ...[
              // Image preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_imagePath!),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // OCR status
                  if (_ocrRunning)
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 2.5)),
                      const SizedBox(width: 10),
                      Text('Extracting text…',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ])
                  else if (_ocrText.isNotEmpty)
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
                        const Text('Text extracted',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E7D32))),
                      ]),
                    )
                  else if (_ocrError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppTheme.danger, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_ocrError!,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.danger))),
                      ]),
                    ),

                  const SizedBox(height: 12),

                  // Change image / re-scan actions
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SmallChip(
                        icon: Icons.photo_library_rounded,
                        label: 'Change',
                        onTap: _pickFromGallery,
                      ),
                      _SmallChip(
                        icon: Icons.camera_alt_rounded,
                        label: 'Retake',
                        onTap: _takePhoto,
                      ),
                      if (_ocrText.isNotEmpty)
                        _SmallChip(
                          icon: Icons.refresh_rounded,
                          label: 'Re-scan',
                          onTap: _runOcr,
                        ),
                    ],
                  ),
                ]),
              ),

              // ── Extracted text preview ─────────────────────────────────
              if (_ocrText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Icon(Icons.text_snippet_rounded, size: 16,
                      color: AppTheme.primary),
                  const SizedBox(width: 6),
                  const Text('EXTRACTED TEXT',
                      style: TextStyle(fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFAAAAB5),
                          letterSpacing: 0.5)),
                ]),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 100),
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
              ],

              const SizedBox(height: 20),

              // ── Editable prompt ─────────────────────────────────────────
              Text("What's this about?",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.text(isDark),
                      letterSpacing: -0.4)),
              const SizedBox(height: 4),
              Text(_ocrText.isNotEmpty
                  ? 'Edit or refine the extracted text'
                  : 'Type your task description',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showTask
                        ? AppTheme.primary
                        : AppTheme.border(isDark),
                    width: _showTask ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  TextField(
                    controller: _promptCtrl,
                    maxLines: 4, minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                        fontSize: 15, color: AppTheme.text(isDark)),
                    decoration: const InputDecoration(
                      hintText: 'Describe the task & deadline…',
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
                          top: BorderSide(color: AppTheme.border(isDark))),
                    ),
                    child: Row(children: [
                      Text('Describe it naturally',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400)),
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

              // ── Editable task fields ──────────────────────────────────
              if (_showTask &&
                  _parsed != null &&
                  _parsed!.isMultiTask &&
                  _multiTasks.isNotEmpty) ...[
                const SizedBox(height: 20),
                Divider(color: AppTheme.border(isDark)),
                const SizedBox(height: 16),
                _OcrMultiTaskBanner(count: _multiTasks.length),
                const SizedBox(height: 12),
                ..._multiTasks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final mt = entry.value;
                  return _OcrMultiTaskRow(
                    task: mt,
                    index: i,
                    isDark: isDark,
                    onPickDeadline: _pickDeadlineFor,
                    onAddLink:      _addLinkFor,
                    onRemoveLink:   _removeLinkFor,
                    onPickFile:     _pickFileFor,
                    onTakePhoto:    _takePhotoFor,
                    onRemoveFile:   _removeFileFor,
                    onChanged:      () => setState(() {}),
                  );
                }),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                        : Text('Save ${_multiTasks.length} tasks'),
                  ),
                ),
              ] else if (_showTask) ...[
                const SizedBox(height: 20),
                Divider(color: AppTheme.border(isDark)),
                const SizedBox(height: 16),

                const Text('Task name',
                    style: TextStyle(fontSize: 11,
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
                      color: Theme.of(context).cardTheme.color ??
                          AppTheme.lightCard,
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

                const SizedBox(height: 16),

                // ── Add details (description / links / files) ─────────────
                GestureDetector(
                  onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _detailsExpanded ? 'Hide details' : 'Add details',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppTheme.primary),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _detailsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16, color: AppTheme.primary,
                    ),
                  ]),
                ),
                if (_detailsExpanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface(isDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border(isDark)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextField(
                        controller: _descCtrl,
                        maxLines: 3, minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Description or notes…',
                          hintStyle: TextStyle(fontSize: 13, color: AppTheme.subtext(isDark)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(fontSize: 13, color: AppTheme.text(isDark)),
                      ),
                      const SizedBox(height: 8),
                      Divider(color: AppTheme.border(isDark), height: 1),
                      const SizedBox(height: 8),

                      // Links
                      ...List.generate(_linkCtrls.length, (j) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(Icons.link_rounded, size: 14, color: AppTheme.subtext(isDark)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _linkCtrls[j],
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                hintText: _linkCtrls.length > 1
                                    ? 'Link ${j + 1} (optional)'
                                    : 'Reference link (optional)',
                                hintStyle: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark)),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: TextStyle(fontSize: 12, color: AppTheme.text(isDark)),
                            ),
                          ),
                          if (_linkCtrls.length > 1)
                            GestureDetector(
                              onTap: () => _removeLink(j),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.remove_circle_outline_rounded,
                                    size: 16, color: AppTheme.subtext(isDark)),
                              ),
                            ),
                        ]),
                      )),
                      GestureDetector(
                        onTap: _addLink,
                        child: Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.add_rounded, size: 12, color: AppTheme.primary),
                          SizedBox(width: 3),
                          Text('Add link',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: AppTheme.primary)),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Divider(color: AppTheme.border(isDark), height: 1),
                      const SizedBox(height: 8),

                      // Attached files
                      if (_attachedFiles.isNotEmpty) ...[
                        ...List.generate(_attachedFiles.length, (j) {
                          final f = _attachedFiles[j];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  f.mime == 'application/pdf'
                                      ? Icons.picture_as_pdf_rounded
                                      : f.mime.startsWith('image/')
                                          ? Icons.image_rounded
                                          : Icons.insert_drive_file_rounded,
                                  color: AppTheme.primary, size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(f.name,
                                    style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w600,
                                        color: AppTheme.text(isDark)),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => setState(() => _attachedFiles.removeAt(j)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppTheme.alert.withValues(alpha: 0.15)
                                        : const Color(0xFFFFEEEE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.close_rounded,
                                      size: 14,
                                      color: isDark
                                          ? const Color(0xFFFF8A70)
                                          : const Color(0xFFA32D2D)),
                                ),
                              ),
                            ]),
                          );
                        }),
                        const SizedBox(height: 6),
                      ],

                      Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _addAttachmentPhoto,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.card(isDark),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border(isDark)),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.camera_alt_rounded, size: 13,
                                    color: AppTheme.subtext(isDark)),
                                const SizedBox(width: 4),
                                Text('Photo',
                                    style: TextStyle(
                                        fontSize: 11, color: AppTheme.subtext(isDark),
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: _addAttachmentFile,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.card(isDark),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border(isDark)),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.add_rounded, size: 13,
                                    color: AppTheme.subtext(isDark)),
                                const SizedBox(width: 4),
                                Text('File',
                                    style: TextStyle(
                                        fontSize: 11, color: AppTheme.subtext(isDark),
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),

                // Save
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _BigActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BigActionButton({
    required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, size: 32, color: AppTheme.primary),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallChip({
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
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _OcrMultiTaskBanner extends StatelessWidget {
  final int count;
  const _OcrMultiTaskBanner({required this.count});

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
            '$count tasks detected — all linked to this scan',
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

class _OcrMultiTaskRow extends StatefulWidget {
  final _MutableTask task;
  final int index;
  final bool isDark;
  final ValueChanged<int> onPickDeadline;
  final ValueChanged<int> onAddLink;
  final void Function(int, int) onRemoveLink;
  final ValueChanged<int> onPickFile;
  final ValueChanged<int> onTakePhoto;
  final void Function(int, int) onRemoveFile;
  final VoidCallback onChanged;

  const _OcrMultiTaskRow({
    required this.task,
    required this.index,
    required this.isDark,
    required this.onPickDeadline,
    required this.onAddLink,
    required this.onRemoveLink,
    required this.onPickFile,
    required this.onTakePhoto,
    required this.onRemoveFile,
    required this.onChanged,
  });

  @override
  State<_OcrMultiTaskRow> createState() => _OcrMultiTaskRowState();
}

class _OcrMultiTaskRowState extends State<_OcrMultiTaskRow> {
  bool _expanded = false;

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

  Future<void> _editSubject(BuildContext context) async {
    final result = await showSubjectEditor(context, initial: widget.task.subject);
    if (result == null || !mounted) return;
    setState(() => widget.task.subject = result);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final task   = widget.task;
    final index  = widget.index;
    final sc = AppTheme.subjectColor(
        task.subject.isNotEmpty ? task.subject : 'default');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('${index + 1}',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: task.nameCtrl,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppTheme.text(isDark)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              GestureDetector(
                onTap: () => widget.onPickDeadline(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 11, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text(DateFormat('d MMM · h:mm a').format(task.deadline),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => _editSubject(context),
                child: task.subject.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: sc.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(task.subject,
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600, color: sc)),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surface(isDark),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.border(isDark)),
                        ),
                        child: Text('Add subject',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: AppTheme.subtext(isDark))),
                      ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => task.priority =
                      task.priority == 'urgent' ? 'normal' : 'urgent');
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: task.priority == 'urgent'
                        ? AppTheme.alert.withValues(alpha: 0.10)
                        : AppTheme.surface(isDark),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: task.priority == 'urgent'
                          ? AppTheme.alert.withValues(alpha: 0.3)
                          : AppTheme.border(isDark),
                    ),
                  ),
                  child: Text(
                    task.priority == 'urgent' ? 'Urgent' : 'Normal',
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: task.priority == 'urgent'
                            ? AppTheme.alert
                            : AppTheme.subtext(isDark)),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _expanded ? 'Hide details' : 'Add details',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppTheme.primary),
                ),
                const SizedBox(width: 3),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 14, color: AppTheme.primary,
                ),
              ]),
            ),

            if (_expanded) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: task.descCtrl,
                    maxLines: 2, minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Description or notes…',
                      hintStyle: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(fontSize: 12, color: AppTheme.text(isDark)),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.border(isDark), height: 1),
                  const SizedBox(height: 8),
                  ...List.generate(task.linkCtrls.length, (j) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(Icons.link_rounded, size: 14, color: AppTheme.subtext(isDark)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: task.linkCtrls[j],
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: task.linkCtrls.length > 1
                                ? 'Link ${j + 1} (optional)'
                                : 'Reference link (optional)',
                            hintStyle: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: TextStyle(fontSize: 12, color: AppTheme.text(isDark)),
                        ),
                      ),
                      if (task.linkCtrls.length > 1)
                        GestureDetector(
                          onTap: () => widget.onRemoveLink(index, j),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.remove_circle_outline_rounded,
                                size: 16, color: AppTheme.subtext(isDark)),
                          ),
                        ),
                    ]),
                  )),
                  GestureDetector(
                    onTap: () => widget.onAddLink(index),
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.add_rounded, size: 12, color: AppTheme.primary),
                      SizedBox(width: 3),
                      Text('Add link',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.border(isDark), height: 1),
                  const SizedBox(height: 8),
                  if (task.attachedFiles.isNotEmpty) ...[
                    ...List.generate(task.attachedFiles.length, (j) {
                      final f = task.attachedFiles[j];
                      final color = _colorFor(f.mime);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_iconFor(f.mime), color: color, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f.name,
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: AppTheme.text(isDark)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => widget.onRemoveFile(index, j),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.alert.withValues(alpha: 0.15)
                                    : const Color(0xFFFFEEEE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.close_rounded,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFFFF8A70)
                                      : const Color(0xFFA32D2D)),
                            ),
                          ),
                        ]),
                      );
                    }),
                    const SizedBox(height: 6),
                  ],
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onTakePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.card(isDark),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border(isDark)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.camera_alt_rounded, size: 13,
                                color: AppTheme.subtext(isDark)),
                            const SizedBox(width: 4),
                            Text('Photo',
                                style: TextStyle(
                                    fontSize: 11, color: AppTheme.subtext(isDark),
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onPickFile(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.card(isDark),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border(isDark)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_rounded, size: 13,
                                color: AppTheme.subtext(isDark)),
                            const SizedBox(width: 4),
                            Text('File',
                                style: TextStyle(
                                    fontSize: 11, color: AppTheme.subtext(isDark),
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
