// lib/screens/add_task_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../models/task.dart';
import '../parser/rule_parser.dart';
import '../database/db_helper.dart';  // ← NEW
import 'home_screen.dart';            // ← NEW

class AddTaskScreen extends StatefulWidget {
  final String? initialRawText;
  const AddTaskScreen({super.key, this.initialRawText});

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
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rawMessageController = TextEditingController();
  DateTime _selectedDeadline = DateTime.now().add(const Duration(days: 1));
  bool _showConfirmBanner = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRawText != null && widget.initialRawText!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rawMessageController.text = widget.initialRawText!;
        _parseMessage();
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rawMessageController.dispose();
    super.dispose();
  }

  void _parseMessage() {
    final raw = _rawMessageController.text.trim();
    if (raw.isEmpty) return;

    final result = RuleParser.parse(raw);

    setState(() {
      if (result.name.isNotEmpty) {
        _nameController.text = result.name;
      }
      if (result.deadline != null) {
        _selectedDeadline = result.deadline!;
      }
      _showConfirmBanner = result.confidence < 0.6;
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

  void _saveTask() async {                                        // ← CHANGED
    if (!_formKey.currentState!.validate()) return;
    final newTask = Task(
      name: _nameController.text.trim(),
      deadline: _selectedDeadline,
    );

    if (widget.initialRawText != null) {                          // ← NEW
      // Launched from share intent — save directly then go to HomeScreen
      await DBHelper.instance.createTask(newTask);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
        );
      }
    } else {
      // Launched normally from HomeScreen — pop back with task
      Navigator.of(context).pop(newTask);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_isEditMode
              ? Icons.arrow_back_rounded
              : Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
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

              // ── Paste Message Section ──────────────────────────
              const Text('Paste a message (optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _rawMessageController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'e.g. "kal tak DSA assignment submit karna hai"',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.message_outlined),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _parseMessage,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Auto-fill from message'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.indigo.shade600,
                    side: BorderSide(color: Colors.indigo.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              // ── Confirmation Banner ────────────────────────────
              if (_showConfirmBanner) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Low confidence — please check the details below.',
                          style: TextStyle(
                              color: Colors.orange.shade800, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // ── Task Name ──────────────────────────────────────
              const Text('Task Name',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g., Submit OS Assignment',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border(isDark)),
                  ),
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppTheme.text(isDark)),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
              Text('What do you need to do?',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                      color: AppTheme.text(isDark), letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Type anything — Nudge figures out the rest',
                  style: TextStyle(fontSize: 13, color: AppTheme.subtext(isDark))),
              const SizedBox(height: 16),

              // Input box
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.card(isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showReview ? AppTheme.primary : AppTheme.border(isDark),
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
                        border: Border(top: BorderSide(color: AppTheme.border(isDark)))),
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
                          Icon(Icons.content_paste_rounded, size: 15, color: AppTheme.subtext(isDark)),
                          const SizedBox(width: 4),
                          Text('Paste', style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark))),
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
                                      : AppTheme.subtext(isDark),
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
                                        : AppTheme.subtext(isDark),
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
              const SizedBox(height: 24),

              // ── Deadline ───────────────────────────────────────
              const Text('Deadline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
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
                            color: subject.isEmpty ? AppTheme.subtext(isDark) : sc)),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => _editType(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppTheme.surface(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border(isDark))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(AppTheme.taskTypeIcon(taskType), size: 12, color: AppTheme.subtext(isDark)),
                    const SizedBox(width: 4),
                    Text(taskType[0].toUpperCase() + taskType.substring(1),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtext(isDark))),
                  ]),
                ),
              ),
              GestureDetector(
                onTap: () => onPriorityChange(priority == 'urgent' ? 'normal' : 'urgent'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: priority == 'urgent'
                          ? (isDark ? AppTheme.alert.withValues(alpha: 0.12) : const Color(0xFFFFF0EE))
                          : AppTheme.surface(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: priority == 'urgent'
                              ? (isDark ? AppTheme.alert.withValues(alpha: 0.35) : const Color(0xFFFFCCBB))
                              : AppTheme.border(isDark))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(priority == 'urgent' ? Icons.bolt_rounded : Icons.flag_outlined,
                        size: 12,
                        color: priority == 'urgent'
                            ? (isDark ? const Color(0xFFFF8A70) : const Color(0xFF993C1D))
                            : AppTheme.subtext(isDark)),
                    const SizedBox(width: 4),
                    Text(priority == 'urgent' ? 'Urgent' : 'Normal',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: priority == 'urgent'
                                ? (isDark ? const Color(0xFFFF8A70) : const Color(0xFF993C1D))
                                : AppTheme.subtext(isDark))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onPickDeadline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: AppTheme.surface(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border(isDark))),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.urgencyColor(deadline)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(DateFormat('EEEE, d MMMM yyyy').format(deadline),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.text(isDark))),
                    Text(DateFormat('h:mm a').format(deadline),
                        style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark))),
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
                  Icon(Icons.edit_rounded, size: 14, color: AppTheme.subtext(isDark)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _editSubject(BuildContext context) async {
    final result = await showSubjectEditor(context, initial: subject);
    if (result == null) return;
    onSubjectChange(result);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: AppTheme.border(isDark))),
          ),
          child: Row(children: [
            const Icon(Icons.notes_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Notes & links',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            Text('optional', style: TextStyle(fontSize: 11, color: AppTheme.subtext(isDark))),
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
                hintStyle: TextStyle(fontSize: 13, color: AppTheme.subtext(isDark)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(fontSize: 13, color: AppTheme.text(isDark)),
            ),
            const SizedBox(height: 10),
            Divider(color: AppTheme.border(isDark), height: 1),
            const SizedBox(height: 10),
            // Link fields
            ...List.generate(linkCtrls.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.link_rounded, size: 16, color: AppTheme.subtext(isDark)),
                ),
                Expanded(
                  child: TextField(
                    controller: linkCtrls[i],
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: linkCtrls.length > 1
                          ? 'Link ${i + 1} (optional)'
                          : 'Reference link (optional)',
                      hintStyle: TextStyle(fontSize: 13, color: AppTheme.subtext(isDark)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(fontSize: 13, color: AppTheme.text(isDark)),
                  ),
                ),
                if (linkCtrls.length > 1)
                  GestureDetector(
                    onTap: () => onRemoveLink(i),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.remove_circle_outline_rounded,
                          size: 18, color: AppTheme.subtext(isDark)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    return Container(
      decoration: BoxDecoration(color: AppTheme.card(isDark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border(isDark))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: AppTheme.border(isDark)))),
          child: Row(children: [
            const Icon(Icons.notifications_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('Reminders',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const Spacer(),
            Text('Tap to toggle',
                style: TextStyle(fontSize: 10, color: AppTheme.subtext(isDark))),
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
                      color: !possible ? AppTheme.surface(isDark)
                          : active ? AppTheme.primary.withValues(alpha: 0.12)
                          : AppTheme.surfaceLow(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !possible ? AppTheme.border(isDark)
                            : active ? AppTheme.primary.withValues(alpha: 0.4)
                            : AppTheme.border(isDark),
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        active ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                        size: 12,
                        color: !possible ? AppTheme.border(isDark)
                            : active ? AppTheme.primary : AppTheme.subtext(isDark),
                      ),
                      const SizedBox(width: 5),
                      Text(r.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: !possible ? AppTheme.border(isDark)
                                : active ? AppTheme.primary : AppTheme.subtext(isDark),
                          )),
                      if (isCustom && possible) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.close_rounded, size: 10,
                            color: active ? AppTheme.primary : AppTheme.subtext(isDark)),
                      ],
                    ]),
                  ),
                );
              }),
              GestureDetector(
                onTap: onAddCustom,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppTheme.surface(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border(isDark))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 12, color: AppTheme.subtext(isDark)),
                    const SizedBox(width: 4),
                    Text('Custom', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.subtext(isDark))),
                  ]),
                ),
              ),
              const SizedBox(height: 40),

              // ── Save Button ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                        color: AppTheme.surface(isDark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border(isDark)),
                      ),
                      child: Column(children: [
                        Icon(Icons.upload_file_rounded, size: 28, color: AppTheme.subtext(isDark)),
                        const SizedBox(height: 6),
                        Text('Attach File',
                            style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark),
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
                        color: AppTheme.surface(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border(isDark)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.camera_alt_rounded, size: 15, color: AppTheme.subtext(isDark)),
                        const SizedBox(width: 5),
                        Text('Photo', style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark),
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
                        color: AppTheme.surface(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border(isDark)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_rounded, size: 15, color: AppTheme.subtext(isDark)),
                        const SizedBox(width: 5),
                        Text('File', style: TextStyle(fontSize: 12, color: AppTheme.subtext(isDark),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border(isDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: AppTheme.border(isDark))),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text('${tasks.length} task${tasks.length == 1 ? "" : "s"} detected',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const SizedBox(width: 6),
            Text('·', style: TextStyle(fontSize: 11, color: AppTheme.subtext(isDark))),
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
                  style: TextStyle(fontSize: 11, color: AppTheme.subtext(isDark))),
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

  Future<void> _editSubject(BuildContext context) async {
    final result =
        await showSubjectEditor(context, initial: widget.task.subject);
    if (result == null || !mounted) return;
    setState(() => widget.task.subject = result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final task  = widget.task;
    final index = widget.index;
    final sc = AppTheme.subjectColor(
        task.subject.isNotEmpty ? task.subject : 'default');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: index > 0
            ? Border(top: BorderSide(color: AppTheme.border(isDark)))
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surface(isDark),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: Text(
                    task.taskType[0].toUpperCase() + task.taskType.substring(1),
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: AppTheme.subtext(isDark))),
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
                  color: AppTheme.surface(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border(isDark)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Description field
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
                  // Link fields
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
                  Divider(color: AppTheme.border(isDark), height: 1),
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
                                color: isDark ? AppTheme.alert.withValues(alpha: 0.15) : const Color(0xFFFFEEEE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.close_rounded,
                                  size: 14, color: isDark ? const Color(0xFFFF8A70) : const Color(0xFFA32D2D)),
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
        // Remove button
        GestureDetector(
          onTap: () => widget.onRemove(index),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.remove_circle_outline_rounded,
                size: 20, color: AppTheme.subtext(isDark)),
          ),
        ),
      ]),
    );
  }
}
