// lib/widgets/task_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';

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

  String get _timeLabel {
    if (task.isDone) return 'Completed';
    final diff = task.deadline.difference(DateTime.now());
    if (diff.isNegative) {
      final h = -diff.inHours;
      return h < 24 ? 'Overdue by ${h}h' : 'Overdue by ${-diff.inDays}d';
    }
    if (diff.inMinutes < 60) return 'Due in ${diff.inMinutes}m';
    if (diff.inHours < 24)   return 'Due in ${diff.inHours}h';
    if (diff.inDays == 1)    return 'Due tomorrow';
    return DateFormat('d MMM · h:mm a').format(task.deadline);
  }

  @override
  Widget build(BuildContext context) {
    final subjectColor = AppTheme.subjectColor(task.subject);
    final urgColor = task.isDone
        ? const Color(0xFF3B6D11)
        : AppTheme.urgencyColor(task.deadline);
    final isDone = task.isDone;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(task.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async { onDelete(); return false; },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEEE),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFCCCC)),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFA32D2D), size: 24),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(
                color: isDone ? const Color(0xFFCCCCD8) : subjectColor,
                width: 3.5,
              ),
              top: const BorderSide(color: AppTheme.border),
              right: const BorderSide(color: AppTheme.border),
              bottom: const BorderSide(color: AppTheme.border),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Checkbox
                GestureDetector(
                  onTap: onToggleDone,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? const Color(0xFF3B6D11) : Colors.transparent,
                      border: Border.all(
                        color: isDone
                            ? const Color(0xFF3B6D11)
                            : const Color(0xFFCCCCD8),
                        width: 2,
                      ),
                    ),
                    child: isDone
                        ? const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDone
                                    ? const Color(0xFFAAAAB5)
                                    : const Color(0xFF1A1A2E),
                                decoration: isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: const Color(0xFFAAAAB5),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (task.priority == 'urgent' && !isDone)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0EE),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFFFFCCBB)),
                              ),
                              child: const Text('URGENT',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF993C1D),
                                      letterSpacing: 0.8)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Subject pill
                          if (task.subject.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                subjectColor.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                task.subject,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: subjectColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Type icon
                          Icon(
                            AppTheme.taskTypeIcon(task.taskType),
                            size: 13,
                            color: const Color(0xFFAAAAB5),
                          ),
                          const SizedBox(width: 4),
                          // Urgency label
                          Expanded(
                            child: Text(
                              _timeLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDone
                                    ? const Color(0xFF3B6D11)
                                    : urgColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}