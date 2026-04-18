// lib/screens/ocr_scan_screen.dart

import 'dart:io';
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
import 'home_screen.dart';

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

    // Save image as a document
    int? docId;
    if (_imagePath != null) {
      final doc = NudgeDocument(
        filePath: _imagePath!,
        mimeType: 'image/jpeg',
        subject:  _subject,
        note:     _nameCtrl.text.trim(),
        savedAt:  DateTime.now(),
      );
      docId = await DBHelper.instance.createDocument(doc);
    }

    // Save the task
    final task = Task(
      name:     _nameCtrl.text.trim(),
      deadline: _deadline,
      priority: _priority,
      taskType: _parsed?.taskType ?? 'assignment',
      subject:  _subject,
      docId:    docId,
    );
    final id = await DBHelper.instance.createTask(task);
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
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _SmallChip(
                      icon: Icons.photo_library_rounded,
                      label: 'Change',
                      onTap: _pickFromGallery,
                    ),
                    const SizedBox(width: 8),
                    _SmallChip(
                      icon: Icons.camera_alt_rounded,
                      label: 'Retake',
                      onTap: _takePhoto,
                    ),
                    if (_ocrText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _SmallChip(
                        icon: Icons.refresh_rounded,
                        label: 'Re-scan',
                        onTap: _runOcr,
                      ),
                    ],
                  ]),
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
              const Text("What's this about?",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
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
                    style: const TextStyle(
                        fontSize: 15, color: Color(0xFF1A1A2E)),
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
              if (_showTask) ...[
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
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E)),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
