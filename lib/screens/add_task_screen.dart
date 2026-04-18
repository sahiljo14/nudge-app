// lib/screens/add_task_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/task.dart';
import '../models/document.dart';
import '../parser/task_parser.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../services/notification_service.dart';
import '../features/voice_gate.dart';
import '../services/voice_service.dart';
import 'home_screen.dart';

// ── Mutable task holder for multi-task preview editing ───────────────────────

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
  final Task? initialTask; // non-null → edit mode
  final bool autoVoice;   // true → start voice capture on screen open
  const AddTaskScreen({super.key, this.prefill = '', this.initialTask, this.autoVoice = false});
  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _ctrl      = TextEditingController();
  final _focus     = FocusNode();
  final _descCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController(); // edit-mode name field
  final List<TextEditingController> _linkCtrls = [];  // multiple links
  final List<_MutableTask> _multiTasks = [];          // multi-task preview
  ParsedTask? _parsed;
  bool _showReview = false;
  bool _saving           = false;
  bool _isListening      = false;
  bool _voiceTransitioning = false; // true while stopListening() is awaited
  String? _voiceError;
  Timer? _watchdogTimer; // auto-stops if no speech within 2.7 s of start

  bool get _isEditMode => widget.initialTask != null;

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

    // Initialise link controllers
    if (widget.initialTask != null) {
      final links = widget.initialTask!.referenceLinks;
      _linkCtrls.addAll(links.isEmpty
          ? [TextEditingController()]
          : links.map((l) => TextEditingController(text: l)));
    } else {
      _linkCtrls.add(TextEditingController());
    }

    if (_isEditMode) {
      final t = widget.initialTask!;
      _deadline    = t.deadline;
      _priority    = t.priority;
      _taskType    = t.taskType;
      _subject     = t.subject;
      _nameCtrl.text = t.name;
      _descCtrl.text = t.description;
      _parsed = ParsedTask(
        taskName:      t.name,
        taskType:      t.taskType,
        deadline:      t.deadline,
        deadlineLabel: DateFormat('d MMMM').format(t.deadline),
        priority:      t.priority,
        subject:       t.subject,
        confidence:    1.0,
      );
      _showReview = true;
    } else if (widget.autoVoice && VoiceGate.isEnabled) {
      // Opened via Voice option in the plus menu — start listening immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) => _startVoice());
    } else if (widget.prefill.isNotEmpty) {
      _ctrl.text = widget.prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
    _ctrl.addListener(_onTextChanged);
    // Warm up the speech engine so the first tap starts instantly.
    if (VoiceGate.isEnabled) VoiceService.instance.init();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    // Stop mic if screen is closed mid-listening (fire-and-forget — dispose() is sync)
    if (_isListening) VoiceService.instance.stopListening();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _focus.dispose();
    for (final c in _linkCtrls) c.dispose();
    for (final t in _multiTasks) t.dispose();
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
      _nameCtrl.text = r.taskName;
      _showReview = true;
      // Populate mutable task list for multi-task preview
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

  // ── Link list management ─────────────────────────────────────────────────────
  void _addLink() => setState(() => _linkCtrls.add(TextEditingController()));

  void _removeLink(int i) => setState(() {
    _linkCtrls[i].dispose();
    _linkCtrls.removeAt(i);
  });

  // ── Per-task (multi-task) helpers ─────────────────────────────────────────────
  void _addLinkFor(int i) =>
      setState(() => _multiTasks[i].linkCtrls.add(TextEditingController()));

  void _removeLinkFor(int i, int j) => setState(() {
    _multiTasks[i].linkCtrls[j].dispose();
    _multiTasks[i].linkCtrls.removeAt(j);
  });

  void _removeFileFor(int i, int j) =>
      setState(() => _multiTasks[i].attachedFiles.removeAt(j));

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

  /// Prepends https:// to URLs that have no scheme.
  String _normalizeUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return 'https://$url';
    }
    return url;
  }

  // ── Per-task deadline picker for multi-task preview ──────────────────────────
  Future<void> _pickDeadlineFor(int index) async {
    final initial = _multiTasks[index].deadline;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
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
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _multiTasks[index].deadline =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() {
      if (_attachedFiles.any((a) => a.path == photo.path)) return;
      _attachedFiles.add((path: photo.path, name: photo.name, mime: 'image/jpeg'));
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
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.90,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
          ),
            ),
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

  // ── Voice input ───────────────────────────────────────────────────────────

  Future<void> _onVoiceTap() async {
    // Block re-entrant taps while a stop transition is already in progress.
    if (_voiceTransitioning) return;

    if (_isListening) {
      // Out-of-sync guard: if the service is no longer actually listening
      // (e.g. it crashed silently), just reset the UI without touching native.
      if (VoiceService.instance.state != VoiceState.listening) {
        if (mounted) setState(() { _isListening = false; _voiceError = null; });
        return;
      }

      // Normal second-tap stop: cancel watchdog and block further taps.
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      if (mounted) setState(() => _voiceTransitioning = true);
      String? capturedText;
      try {
        capturedText = await VoiceService.instance.stopListening();
      } finally {
        if (mounted) setState(() { _isListening = false; _voiceTransitioning = false; });
      }
      // Commit any text that was captured before the user stopped.
      if (capturedText != null && capturedText.isNotEmpty && mounted) {
        setState(() { _ctrl.text = capturedText!; _voiceError = null; });
        _parse();
      }
      return;
    }

    VoiceGate.request(
      onGranted: _startVoice,
      onDenied: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice input is not available.')),
        );
      },
    );
  }

  Future<void> _startVoice() async {
    // Guard: do not start if a stop is still resolving or widget is gone.
    if (!mounted || _voiceTransitioning) return;
    setState(() { _isListening = true; _voiceError = null; });
    final error = await VoiceService.instance.startListening(
      onResult: (text) {
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
        if (!mounted) return;
        setState(() { _ctrl.text = text; _isListening = false; _voiceError = null; });
        _parse();
      },
      // Live partial updates — first non-empty partial cancels the no-speech watchdog.
      onPartialResult: (text) {
        if (text.isNotEmpty) { _watchdogTimer?.cancel(); _watchdogTimer = null; }
        if (!mounted) return;
        setState(() => _ctrl.text = text);
      },
      // Called on timeout, error, or silent stop — always clears listening state.
      onStop: () {
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
        if (!mounted) return;
        setState(() => _isListening = false);
      },
    );
    if (error != null && mounted) {
      // Map error strings to user-friendly messages.
      // Covers both speech_to_text and legacy error keywords.
      String msg = error;
      if (error.contains('permission') || error.contains('denied') ||
          error.contains('PERMISSION_DENIED')) {
        msg = 'Microphone permission denied. Enable in Settings.';
      } else if (error.contains('not available') || error.contains('INIT_FAILED') ||
          error.contains('initialize') || error.contains('extract')) {
        msg = 'Voice engine failed to start. Try again.';
      } else if (error.contains('Could not') || error.contains('START_FAILED')) {
        msg = 'Could not access microphone. Try again.';
      }
      setState(() { _voiceError = msg; _isListening = false; });
    } else if (error == null && mounted) {
      // Listening started — auto-stop if user says nothing within 2.7 s.
      _watchdogTimer = Timer(const Duration(milliseconds: 2700), () async {
        if (!mounted || !_isListening || _voiceTransitioning) return;
        setState(() => _voiceTransitioning = true);
        await VoiceService.instance.stopListening();
        if (mounted) setState(() { _isListening = false; _voiceTransitioning = false; });
      });
    }
  }

  Future<void> _save() async {
    if (!_isEditMode && _ctrl.text.trim().isEmpty) return;
    if (!_showReview) { _parse(); return; }
    setState(() => _saving = true);

    // ── Edit mode: update existing task ──────────────────────────
    if (_isEditMode) {
      final t = widget.initialTask!;
      final name = _nameCtrl.text.trim();
      final updated = t.copyWith(
        name:          name.isNotEmpty ? name : t.name,
        deadline:      _deadline,
        priority:      _priority,
        taskType:      _taskType,
        subject:       _subject,
        description:   _descCtrl.text.trim(),
        referenceLink: _linkCtrls.map((c) => _normalizeUrl(c.text.trim())).where((s) => s.isNotEmpty).join('\n'),
      );
      await DBHelper.instance.updateTask(updated);
      await _scheduleSelected(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }

    final desc    = _descCtrl.text.trim();
    final linkStr = _linkCtrls
        .map((c) => _normalizeUrl(c.text.trim()))
        .where((s) => s.isNotEmpty)
        .join('\n');

    if (_parsed != null && _parsed!.isMultiTask && _multiTasks.isNotEmpty) {
      // Multi-task: create one DB task per (user-edited) mutable task
      for (final mt in _multiTasks) {
        final name = mt.nameCtrl.text.trim();
        final mtLinkStr = mt.linkCtrls
            .map((c) => _normalizeUrl(c.text.trim()))
            .where((s) => s.isNotEmpty)
            .join('\n');
        final task = Task(
          name:          name.isNotEmpty ? name : _ctrl.text.trim(),
          deadline:      mt.deadline,
          priority:      mt.priority,
          taskType:      mt.taskType,
          subject:       mt.subject.isNotEmpty ? mt.subject : _subject,
          description:   mt.descCtrl.text.trim(),
          referenceLink: mtLinkStr,
        );
        final id    = await DBHelper.instance.createTask(task);
        final saved = task.copyWith(id: id);
        await _scheduleSelected(saved);
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
      // Single-task path — prefer user-edited name from _nameCtrl
      final nameOverride = _nameCtrl.text.trim();
      final taskName = nameOverride.isNotEmpty
          ? nameOverride
          : (_parsed?.taskName ?? _ctrl.text.trim());
      final task = Task(
        name:          taskName.isNotEmpty ? taskName : _ctrl.text.trim(),
        deadline:      _deadline,
        priority:      _priority,
        taskType:      _taskType,
        subject:       _subject,
        description:   desc,
        referenceLink: linkStr,
      );
      final id    = await DBHelper.instance.createTask(task);
      final saved = task.copyWith(id: id);
      await _scheduleSelected(saved);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.lightSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_isEditMode
              ? Icons.arrow_back_rounded
              : Icons.close_rounded),
          onPressed: () {
            if (_isEditMode) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (_) => false,
              );
            }
          },
        ),
        title: Text(_isEditMode ? 'Edit task' : 'New task'),
        actions: [
          if (_showReview)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                  (_parsed?.isMultiTask ?? false) && _multiTasks.isNotEmpty
                      ? 'Save all'
                      : 'Save',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isEditMode) ...[
                // Edit mode: name text field
                const Text('Task name',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: Color(0xFF888899), letterSpacing: 0.3)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.lightCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.lightBorder),
                  ),
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
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
                    style: TextStyle(fontSize: 15, color: AppTheme.text(isDark), height: 1.5),
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
                      if (VoiceGate.isEnabled) ...[
                        const SizedBox(width: 12),
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: _voiceTransitioning ? null : _onVoiceTap,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  _isListening
                                      ? Icons.mic_rounded
                                      : Icons.mic_none_rounded,
                                  size: 16,
                                  color: _isListening
                                      ? AppTheme.primary
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _voiceTransitioning
                                      ? 'Stopping…'
                                      : (_isListening ? 'Listening…' : 'Voice'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isListening
                                        ? AppTheme.primary
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ],
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

              // Voice error banner (shown below input box, clears on next action)
              if (_voiceError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _voiceError!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB80438),
                    height: 1.4,
                  ),
                ),
              ],

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
              ], // end if (!_showReview)
              ], // end else (non-edit-mode NLP input block)

              // Review card + extras
              if (_showReview && _parsed != null) ...[
                const SizedBox(height: 24),
                if (_parsed!.isMultiTask && _multiTasks.isNotEmpty)
                  _MultiTaskPreviewSection(
                    tasks:          _multiTasks,
                    onRemove:       (i) => setState(() {
                      _multiTasks[i].dispose();
                      _multiTasks.removeAt(i);
                      if (_multiTasks.isEmpty) {
                        _showReview = false;
                      }
                    }),
                    onPickDeadline: _pickDeadlineFor,
                    onAddLink:      _addLinkFor,
                    onRemoveLink:   _removeLinkFor,
                    onPickFile:      _pickFileFor,
                    onTakePhoto:     _takePhotoFor,
                    onRemoveFile:    _removeFileFor,
                    onBatchSubject:  (s) => setState(() {
                      for (final mt in _multiTasks) mt.subject = s;
                    }),
                  )
                else
                  _ReviewCard(
                    parsed: _parsed!, deadline: _deadline,
                    priority: _priority, taskType: _taskType, subject: _subject,
                    nameCtrl:         _nameCtrl,
                    onPickDeadline:   _pickDeadline,
                    onPriorityChange: (v) => setState(() => _priority = v),
                    onTypeChange:     (v) => setState(() => _taskType = v),
                    onSubjectChange:  (v) => setState(() => _subject = v),
                  ),
                if (!(_parsed!.isMultiTask && _multiTasks.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  _DescLinksSection(
                    descCtrl:    _descCtrl,
                    linkCtrls:   _linkCtrls,
                    onAddLink:   _addLink,
                    onRemoveLink: _removeLink,
                  ),
                ],
                const SizedBox(height: 16),
                _RemindersSection(
                  reminders:      _reminders,
                  deadline:       _deadline,
                  onToggle:       (i) => setState(() => _reminders[i].enabled = !_reminders[i].enabled),
                  onAddCustom:    _addCustomReminder,
                  onRemoveCustom: (i) => setState(() => _reminders.removeAt(i)),
                ),
                if (!(_parsed!.isMultiTask && _multiTasks.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  _AttachmentSection(
                    files:       _attachedFiles,
                    onPick:      _pickFile,
                    onTakePhoto: _takePhoto,
                    onRemove:    (i) => setState(() => _attachedFiles.removeAt(i)),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(_parsed!.isMultiTask && _multiTasks.isNotEmpty
                            ? 'Save ${_multiTasks.length} task${_multiTasks.length == 1 ? "" : "s"}'
                            : 'Save task'),
                  ),
                ),
              ],
            ],
          ),
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
  final TextEditingController nameCtrl;
  final VoidCallback onPickDeadline;
  final ValueChanged<String> onPriorityChange, onTypeChange, onSubjectChange;

  const _ReviewCard({
    required this.parsed, required this.deadline,
    required this.priority, required this.taskType, required this.subject,
    required this.nameCtrl,
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
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E), letterSpacing: -0.4),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: 'Task name',
              ),
            ),
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
        child: SingleChildScrollView(
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
          ...['assignment', 'exam', 'submission', 'reminder', 'meeting', 'personal'].map((t) => ListTile(
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

// ── Description + Links section (multiple links) ─────────────────────────────

class _DescLinksSection extends StatelessWidget {
  final TextEditingController descCtrl;
  final List<TextEditingController> linkCtrls;
  final VoidCallback onAddLink;
  final ValueChanged<int> onRemoveLink;

  const _DescLinksSection({
    required this.descCtrl,
    required this.linkCtrls,
    required this.onAddLink,
    required this.onRemoveLink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: AppTheme.lightBorder)),
          ),
          child: Row(children: [
            const Icon(Icons.notes_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Notes & links',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            Text('optional', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: descCtrl,
              maxLines: 2, minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Description or notes…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 10),
            Divider(color: AppTheme.lightBorder, height: 1),
            const SizedBox(height: 10),
            // Link fields
            ...List.generate(linkCtrls.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.link_rounded, size: 16, color: Colors.grey.shade400),
                ),
                Expanded(
                  child: TextField(
                    controller: linkCtrls[i],
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: linkCtrls.length > 1
                          ? 'Link ${i + 1} (optional)'
                          : 'Reference link (optional)',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)),
                  ),
                ),
                if (linkCtrls.length > 1)
                  GestureDetector(
                    onTap: () => onRemoveLink(i),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.remove_circle_outline_rounded,
                          size: 18, color: Colors.grey.shade400),
                    ),
                  ),
              ]),
            )),
            // Add link button
            GestureDetector(
              onTap: onAddLink,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 14, color: AppTheme.primary),
                const SizedBox(width: 4),
                const Text('Add link',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              ]),
            ),
          ]),
        ),
      ]),
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
  final VoidCallback onTakePhoto;
  final ValueChanged<int> onRemove;

  const _AttachmentSection({
    required this.files,
    required this.onPick,
    required this.onTakePhoto,
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

            // Camera + file picker buttons
            if (files.isEmpty) ...[
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onTakePhoto,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: Column(children: [
                        Icon(Icons.camera_alt_rounded, size: 28, color: Colors.grey.shade400),
                        const SizedBox(height: 6),
                        Text('Take Photo',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onPick,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: Column(children: [
                        Icon(Icons.upload_file_rounded, size: 28, color: Colors.grey.shade400),
                        const SizedBox(height: 6),
                        Text('Attach File',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ] else ...[
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onTakePhoto,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.camera_alt_rounded, size: 15, color: Colors.grey.shade500),
                        const SizedBox(width: 5),
                        Text('Photo', style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onPick,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.lightSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_rounded, size: 15, color: Colors.grey.shade500),
                        const SizedBox(width: 5),
                        Text('File', style: TextStyle(fontSize: 12, color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Multi-task preview section ────────────────────────────────────────────────

class _MultiTaskPreviewSection extends StatelessWidget {
  final List<_MutableTask> tasks;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPickDeadline;
  final ValueChanged<int> onAddLink;
  final void Function(int, int) onRemoveLink;
  final ValueChanged<int> onPickFile;
  final ValueChanged<int> onTakePhoto;
  final void Function(int, int) onRemoveFile;
  final ValueChanged<String> onBatchSubject;

  const _MultiTaskPreviewSection({
    required this.tasks,
    required this.onRemove,
    required this.onPickDeadline,
    required this.onAddLink,
    required this.onRemoveLink,
    required this.onPickFile,
    required this.onTakePhoto,
    required this.onRemoveFile,
    required this.onBatchSubject,
  });

  void _batchSubjectSheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Set subject for all tasks',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(controller: ctrl, autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'e.g. Operating Systems, Maths…')),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    onBatchSubject(ctrl.text.trim());
                    Navigator.pop(sheetCtx);
                  },
                  child: const Text('Done'),
                )),
          ]),
        ),
      ),
    );
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
            const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text('${tasks.length} task${tasks.length == 1 ? "" : "s"} detected',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const SizedBox(width: 6),
            Text('·', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _batchSubjectSheet(context),
              child: const Text('Set all \u25b8',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ),
            const Spacer(),
            Flexible(
              child: Text('Tap to edit • tap date to change',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ),
          ]),
        ),
        // Task rows
        ...tasks.asMap().entries.map((entry) {
          final i    = entry.key;
          final task = entry.value;
          return _MultiTaskRow(
            task:           task,
            index:          i,
            isLast:         i == tasks.length - 1,
            onRemove:       onRemove,
            onPickDeadline: onPickDeadline,
            onAddLink:      onAddLink,
            onRemoveLink:   onRemoveLink,
            onPickFile:     onPickFile,
            onTakePhoto:    onTakePhoto,
            onRemoveFile:   onRemoveFile,
          );
        }),
      ]),
    );
  }
}

class _MultiTaskRow extends StatefulWidget {
  final _MutableTask task;
  final int index;
  final bool isLast;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onPickDeadline;
  final ValueChanged<int> onAddLink;
  final void Function(int, int) onRemoveLink;
  final ValueChanged<int> onPickFile;
  final ValueChanged<int> onTakePhoto;
  final void Function(int, int) onRemoveFile;

  const _MultiTaskRow({
    required this.task,
    required this.index,
    required this.isLast,
    required this.onRemove,
    required this.onPickDeadline,
    required this.onAddLink,
    required this.onRemoveLink,
    required this.onPickFile,
    required this.onTakePhoto,
    required this.onRemoveFile,
  });

  @override
  State<_MultiTaskRow> createState() => _MultiTaskRowState();
}

class _MultiTaskRowState extends State<_MultiTaskRow> {
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

  void _editSubject(BuildContext context) {
    final ctrl = TextEditingController(text: widget.task.subject);
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Subject',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
                controller: ctrl, autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'e.g. Operating Systems, Maths…')),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => widget.task.subject = ctrl.text.trim());
                    Navigator.pop(sheetCtx);
                  },
                  child: const Text('Done'),
                )),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task  = widget.task;
    final index = widget.index;
    final sc = AppTheme.subjectColor(
        task.subject.isNotEmpty ? task.subject : 'default');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: index > 0
            ? Border(top: BorderSide(color: AppTheme.lightBorder))
            : null,
        borderRadius: widget.isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16))
            : null,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Index bubble
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
            // Editable task name
            TextField(
              controller: task.nameCtrl,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E)),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 6),
            // Chips row
            Wrap(spacing: 6, runSpacing: 4, children: [
              // Deadline chip (tappable)
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
                          color: AppTheme.lightSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.lightBorder),
                        ),
                        child: Text('Add subject',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: Colors.grey.shade400)),
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.lightBorder),
                ),
                child: Text(
                    task.taskType[0].toUpperCase() + task.taskType.substring(1),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: Color(0xFF888899))),
              ),
            ]),
            // "Add details / Hide details" toggle
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
            // Collapsible details section
            if (_expanded) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.lightBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Description field
                  TextField(
                    controller: task.descCtrl,
                    maxLines: 2, minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Description or notes…',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A2E)),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.lightBorder, height: 1),
                  const SizedBox(height: 8),
                  // Link fields
                  ...List.generate(task.linkCtrls.length, (j) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(Icons.link_rounded, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: task.linkCtrls[j],
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            hintText: task.linkCtrls.length > 1
                                ? 'Link ${j + 1} (optional)'
                                : 'Reference link (optional)',
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A2E)),
                        ),
                      ),
                      if (task.linkCtrls.length > 1)
                        GestureDetector(
                          onTap: () => widget.onRemoveLink(index, j),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.remove_circle_outline_rounded,
                                size: 16, color: Colors.grey.shade400),
                          ),
                        ),
                    ]),
                  )),
                  // Add link button
                  GestureDetector(
                    onTap: () => widget.onAddLink(index),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 3),
                      const Text('Add link',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppTheme.lightBorder, height: 1),
                  const SizedBox(height: 8),
                  // Attached files list
                  if (task.attachedFiles.isNotEmpty) ...[
                    ...List.generate(task.attachedFiles.length, (j) {
                      final f     = task.attachedFiles[j];
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
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A2E)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => widget.onRemoveFile(index, j),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEEE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Color(0xFFA32D2D)),
                            ),
                          ),
                        ]),
                      );
                    }),
                    const SizedBox(height: 6),
                  ],
                  // Photo + file picker buttons
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => widget.onTakePhoto(index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.camera_alt_rounded, size: 13,
                                color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('Photo',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500,
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
                            color: AppTheme.lightCard,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.lightBorder),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_rounded, size: 13,
                                color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text('File',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500,
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
        // Remove button
        GestureDetector(
          onTap: () => widget.onRemove(index),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.remove_circle_outline_rounded,
                size: 20, color: Colors.grey.shade400),
          ),
        ),
      ]),
    );
  }
}
