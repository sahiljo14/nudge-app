// lib/models/task.dart

// Sentinel used by copyWith to distinguish "leave unchanged" from explicit null.
const _keep = Object();

class Task {
  final int? id;
  final String name;
  final DateTime deadline;
  final bool isDone;
  final String priority;    // 'urgent' | 'normal'
  final String taskType;    // 'assignment'|'exam'|'submission'|'reminder'|'meeting'|'unknown'|'personal'
  final String subject;     // auto-detected or user-set, e.g. 'Operating Systems'
  final int? docId;         // linked document id, nullable
  final DateTime? completedAt; // real timestamp when task was marked done; null if pending
  final String description;   // optional notes/details
  final String referenceLink; // newline-separated URLs (backward-compat with old single URL)

  /// Parses referenceLink into individual URLs. Backward-compatible with old
  /// single-URL format — a value without '\n' is returned as a one-element list.
  List<String> get referenceLinks =>
      referenceLink.isEmpty
          ? []
          : referenceLink.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  const Task({
    this.id,
    required this.name,
    required this.deadline,
    this.isDone = false,
    this.priority = 'normal',
    this.taskType = 'assignment',
    this.subject = '',
    this.docId,
    this.completedAt,
    this.description = '',
    this.referenceLink = '',
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
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'description': description,
    'referenceLink': referenceLink,
  };

  factory Task.fromMap(Map<String, dynamic> m) {
    final rawCompletedAt = m['completedAt'];
    return Task(
      id: m['id'] as int?,
      name: m['name'] as String,
      deadline: DateTime.parse(m['deadline'] as String),
      isDone: (m['isDone'] as int) == 1,
      priority: m['priority'] as String? ?? 'normal',
      taskType: m['taskType'] as String? ?? 'assignment',
      subject: m['subject'] as String? ?? '',
      docId: m['docId'] as int?,
      completedAt: rawCompletedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(rawCompletedAt as int)
          : null,
      description: m['description'] as String? ?? '',
      referenceLink: m['referenceLink'] as String? ?? '',
    );
  }

  Task copyWith({
    int? id,
    String? name,
    DateTime? deadline,
    bool? isDone,
    String? priority,
    String? taskType,
    String? subject,
    int? docId,
    // Use sentinel so callers can explicitly pass completedAt: null to clear it.
    Object? completedAt = _keep,
    String? description,
    String? referenceLink,
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
        completedAt: identical(completedAt, _keep)
            ? this.completedAt
            : completedAt as DateTime?,
        description: description ?? this.description,
        referenceLink: referenceLink ?? this.referenceLink,
      );
}