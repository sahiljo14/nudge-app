import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/task.dart';
import '../widgets/task_card.dart';
import 'add_task_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    final tasks = await DBHelper.instance.getAllTasks();
    setState(() {
      _tasks = tasks;
      _isLoading = false;
    });
  }

  Future<void> _navigateToAddTask() async {
    final newTask = await Navigator.of(context).push<Task>(
      MaterialPageRoute(builder: (_) => const AddTaskScreen()),
    );
    if (newTask != null) {
      await DBHelper.instance.createTask(newTask);
      await _loadTasks();
    }
  }

  Future<void> _toggleDone(Task task) async {
    final updated = task.copyWith(isDone: !task.isDone);
    await DBHelper.instance.updateTask(updated);
    await _loadTasks();
  }

  Future<void> _deleteTask(Task task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Task?'),
        content: Text('Delete "${task.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(color: Colors.red.shade600))),
        ],
      ),
    );
    if (confirm == true) {
      await DBHelper.instance.deleteTask(task.id!);
      await _loadTasks();
    }
  }

  int get _pendingCount => _tasks.where((t) => !t.isDone).length;
  int get _doneCount => _tasks.where((t) => t.isDone).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('My Tasks',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 16),
            alignment: Alignment.centerLeft,
            child: Text(
              '$_pendingCount pending  •  $_doneCount done',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 80, color: Colors.indigo.shade200),
            const SizedBox(height: 16),
            Text('No tasks yet!',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade300)),
            const SizedBox(height: 8),
            Text('Tap "Add Task" to get started',
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 14)),
          ],
        ),
      )
          : ListView.builder(
        padding:
        const EdgeInsets.only(top: 12, bottom: 100),
        itemCount: _tasks.length,
        itemBuilder: (context, index) {
          final task = _tasks[index];
          return TaskCard(
            task: task,
            onToggleDone: () => _toggleDone(task),
            onDelete: () => _deleteTask(task),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddTask,
        backgroundColor: Colors.indigo.shade600,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Task',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}