// lib/models/document.dart

class NudgeDocument {
  final int? id;
  final String filePath;   // URI/path to original file — reference-based
  final String mimeType;   // 'application/pdf' | 'image/*'
  final String subject;    // subject tag
  final String note;       // user's description e.g. "OS assignment brief"
  final DateTime savedAt;
  final int? taskId;       // linked task

  const NudgeDocument({
    this.id,
    required this.filePath,
    required this.mimeType,
    this.subject = '',
    this.note = '',
    required this.savedAt,
    this.taskId,
  });

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');

  Map<String, dynamic> toMap() => {
    'id': id,
    'filePath': filePath,
    'mimeType': mimeType,
    'subject': subject,
    'note': note,
    'savedAt': savedAt.toIso8601String(),
    'taskId': taskId,
  };

  factory NudgeDocument.fromMap(Map<String, dynamic> m) => NudgeDocument(
    id: m['id'] as int?,
    filePath: m['filePath'] as String,
    mimeType: m['mimeType'] as String,
    subject: m['subject'] as String? ?? '',
    note: m['note'] as String? ?? '',
    savedAt: DateTime.parse(m['savedAt'] as String),
    taskId: m['taskId'] as int?,
  );

  NudgeDocument copyWith({
    int? id,
    String? filePath,
    String? mimeType,
    String? subject,
    String? note,
    DateTime? savedAt,
    int? taskId,
  }) =>
      NudgeDocument(
        id: id ?? this.id,
        filePath: filePath ?? this.filePath,
        mimeType: mimeType ?? this.mimeType,
        subject: subject ?? this.subject,
        note: note ?? this.note,
        savedAt: savedAt ?? this.savedAt,
        taskId: taskId ?? this.taskId,
      );
}