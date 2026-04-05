// lib/models/task.dart

class Task {
  final int? id;
  final String name;
  final DateTime deadline;
  final bool isDone;
  final String priority;  // 'urgent' | 'normal'
  final String taskType;  // 'assignment'|'exam'|'submission'|'reminder'|'meeting'|'unknown'
  final String subject;   // auto-detected or user-set, e.g. 'Operating Systems'
  final int? docId;       // linked document id, nullable

  const Task({
    this.id,
    required this.name,
    required this.deadline,
    this.isDone = false,
    this.priority = 'normal',
    this.taskType = 'assignment',
    this.subject = '',
    this.docId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'deadline': deadline.toIso8601String(),
    'isDone': isDone ? 1 : 0,
    'priority': priority,
    'taskType': taskType,
    'subject': subject,
    'docId': docId,
  };

  factory Task.fromMap(Map<String, dynamic> m) => Task(
    id: m['id'] as int?,
    name: m['name'] as String,
    deadline: DateTime.parse(m['deadline'] as String),
    isDone: (m['isDone'] as int) == 1,
    priority: m['priority'] as String? ?? 'normal',
    taskType: m['taskType'] as String? ?? 'assignment',
    subject: m['subject'] as String? ?? '',
    docId: m['docId'] as int?,
  );

  Task copyWith({
    int? id,
    String? name,
    DateTime? deadline,
    bool? isDone,
    String? priority,
    String? taskType,
    String? subject,
    int? docId,
  }) =>
      Task(
        id: id ?? this.id,
        name: name ?? this.name,
        deadline: deadline ?? this.deadline,
        isDone: isDone ?? this.isDone,
        priority: priority ?? this.priority,
        taskType: taskType ?? this.taskType,
        subject: subject ?? this.subject,
        docId: docId ?? this.docId,
      );
}