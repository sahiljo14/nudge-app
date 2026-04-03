import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onToggleDone;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggleDone,
    required this.onDelete,
  });

  Color _deadlineColor() {
    final daysLeft = task.deadline.difference(DateTime.now()).inDays;
    if (task.isDone) return Colors.green.shade400;
    if (daysLeft < 0) return Colors.red.shade700;
    if (daysLeft == 0) return Colors.red.shade400;
    if (daysLeft <= 2) return Colors.orange.shade400;
    return Colors.blue.shade400;
  }

  String _deadlineLabel() {
    final daysLeft = task.deadline.difference(DateTime.now()).inDays;
    if (task.isDone) return 'Done ✓';
    if (daysLeft < 0) return 'Overdue!';
    if (daysLeft == 0) return 'Due Today!';
    if (daysLeft == 1) return 'Due Tomorrow';
    return 'Due: ${DateFormat('dd MMM, hh:mm a').format(task.deadline)}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _deadlineColor();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GestureDetector(
          onTap: onToggleDone,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.isDone ? Colors.green.shade400 : Colors.transparent,
              border: Border.all(
                color: task.isDone
                    ? Colors.green.shade400
                    : Colors.grey.shade400,
                width: 2,
              ),
            ),
            child: task.isDone
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ),
        title: Text(
          task.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            decoration: task.isDone ? TextDecoration.lineThrough : null,
            color: task.isDone ? Colors.grey : Colors.black87,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.access_time_rounded, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                _deadlineLabel(),
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
          onPressed: onDelete,
        ),
      ),
    );
  }
}