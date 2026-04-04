import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../parser/rule_parser.dart';
import '../database/db_helper.dart';  // ← NEW
import 'home_screen.dart';            // ← NEW

class AddTaskScreen extends StatefulWidget {
  final String? initialRawText;
  const AddTaskScreen({super.key, this.initialRawText});

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
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDeadline),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedDeadline = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('New Task',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
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
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.assignment_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ── Deadline ───────────────────────────────────────
              const Text('Deadline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          color: Colors.indigo.shade400, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('EEE, dd MMM yyyy  •  hh:mm a')
                            .format(_selectedDeadline),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
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
                  child: const Text('Save Task',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}