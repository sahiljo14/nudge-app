import 'date_resolver.dart';

class ParsedTask {
  final String name;
  final DateTime? deadline;
  final double confidence;

  ParsedTask({
    required this.name,
    this.deadline,
    required this.confidence,
  });
}

class RuleParser {
  static const _taskKeywords = [
    'submit', 'jama karo', 'jama kar', 'dena hai', 'dena ahe',
    'assignment', 'homework', 'project', 'exam', 'test', 'quiz',
    'presentation', 'report', 'practical', 'viva', 'lab',
    'upload', 'send', 'share', 'complete', 'finish',
    'karna hai', 'karo', 'karna', 'bhejdo', 'bhejo',
    'deadline', 'due', 'last date', 'submission',
  ];

  static const _deadlineSignals = [
    'by', 'before', 'until', 'till', 'on',
    'tak', 'pehle', 'ko', 'se pehle',
  ];

  static ParsedTask parse(String rawText) {
    final text = rawText.trim();
    final lower = text.toLowerCase();

    DateTime? deadline;
    double confidence = 0.3;

    for (final signal in _deadlineSignals) {
      final pattern = RegExp('$signal\\s+(.{3,30})', caseSensitive: false);
      final match = pattern.firstMatch(lower);
      if (match != null) {
        final candidate = match.group(1) ?? '';
        final resolved = DateResolver.resolve(candidate);
        if (resolved != null) {
          deadline = resolved;
          confidence += 0.4;
          break;
        }
      }
    }

    if (deadline == null) {
      deadline = DateResolver.resolve(lower);
      if (deadline != null) confidence += 0.3;
    }

    final hasTaskKeyword = _taskKeywords.any((k) => lower.contains(k));
    if (hasTaskKeyword) confidence += 0.2;

    final name = _extractTaskName(text);

    return ParsedTask(
      name: name,
      deadline: deadline,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  static String _extractTaskName(String text) {
    String name = text;

    final fillers = [
      // Date references
      RegExp(r'\b\d{1,2}[/\-]\d{1,2}[/\-]\d{4}\b'),
      RegExp(r'\bin\s+\d+\s*(din|days?|d)\b', caseSensitive: false),
      RegExp(r'\bby\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|today|kal|aaj)\b', caseSensitive: false),
      RegExp(r'\bon\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', caseSensitive: false),
      RegExp(r'\b(next|this)\s+(week|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', caseSensitive: false),

      // Hinglish / Marathi action phrases
      RegExp(r'\bkal\s+tak\b', caseSensitive: false),
      RegExp(r'\baaj\s+tak\b', caseSensitive: false),
      RegExp(r'\budya\b', caseSensitive: false),
      RegExp(r'\bkal\b', caseSensitive: false),
      RegExp(r'\baaj\b', caseSensitive: false),
      RegExp(r'\bparso\b', caseSensitive: false),
      RegExp(r'\bsubmit\s+karna\s+hai\b', caseSensitive: false),
      RegExp(r'\bkarna\s+hai\b', caseSensitive: false),
      RegExp(r'\bna\s+hai\b', caseSensitive: false),
      RegExp(r'\bdena\s+hai\b', caseSensitive: false),
      RegExp(r'\bdena\s+ahe\b', caseSensitive: false),
      RegExp(r'\bjama\s+kar\b', caseSensitive: false),
      RegExp(r'\bbhejo\b', caseSensitive: false),
      RegExp(r'\bbhejdo\b', caseSensitive: false),
      RegExp(r'\bkaro\b', caseSensitive: false),
      RegExp(r'\bsubmit\b', caseSensitive: false),
      RegExp(r'\btak\b', caseSensitive: false),
      RegExp(r'\bby\b', caseSensitive: false),
      RegExp(r'\bon\b', caseSensitive: false),
    ];

    for (final filler in fillers) {
      name = name.replaceAll(filler, '');
    }

    // Clean up extra spaces
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (name.isEmpty) return text.trim();
    return name[0].toUpperCase() + name.substring(1);
  }
}