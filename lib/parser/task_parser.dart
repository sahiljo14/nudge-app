// lib/parser/task_parser.dart

class ParsedTask {
  final String taskName;
  final String taskType;
  final DateTime deadline;
  final String deadlineLabel;
  final String priority;
  final String subject;
  final double confidence;

  const ParsedTask({
    required this.taskName,
    required this.taskType,
    required this.deadline,
    required this.deadlineLabel,
    required this.priority,
    required this.subject,
    required this.confidence,
  });
}

class TaskParser {
  // ── Today ────────────────────────────────────────────────────────────────
  static const _today = [
    'today', 'aaj', 'aj', 'tonight', 'abhi', 'aajke', 'aaj hi',
  ];

  // ── Tomorrow ─────────────────────────────────────────────────────────────
  static const _tomorrow = [
    'tomorrow', 'tmrw', 'tmr', 'kal', 'kl', 'udya', 'udhya',
    'next day', 'agle din', 'kal tak',
  ];

  // ── Day after ────────────────────────────────────────────────────────────
  static const _dayAfter = [
    'parso', 'day after tomorrow', 'parva',
  ];

  // ── Weekdays ─────────────────────────────────────────────────────────────
  static const Map<String, int> _weekdays = {
    'monday': DateTime.monday,    'mon': DateTime.monday,    'somwar': DateTime.monday,
    'tuesday': DateTime.tuesday,  'tue': DateTime.tuesday,
    'wednesday': DateTime.wednesday, 'wed': DateTime.wednesday, 'budhwar': DateTime.wednesday,
    'thursday': DateTime.thursday,'thu': DateTime.thursday,  'guruwar': DateTime.thursday,
    'friday': DateTime.friday,    'fri': DateTime.friday,    'shukrawar': DateTime.friday,
    'saturday': DateTime.saturday,'sat': DateTime.saturday,  'shaniwar': DateTime.saturday,
    'sunday': DateTime.sunday,    'sun': DateTime.sunday,    'raviwar': DateTime.sunday,
  };

  // ── Task types ────────────────────────────────────────────────────────────
  static const Map<String, List<String>> _types = {
    'assignment': [
      'assignment', 'assignmnt', 'homework', 'hw', 'project',
      'proj', 'practical', 'lab', 'coursework',
    ],
    'exam': [
      'exam', 'exm', 'test', 'quiz', 'viva', 'oral', 'paper',
      'midsem', 'mid sem', 'endsem', 'end sem',
      'unit test', 'ut', 'class test', 'ct', 'final',
    ],
    'submission': [
      'submit', 'submission', 'sbmit', 'jama', 'upload',
      'dena hai', 'dena ahe', 'bhejo', 'form', 'jama karo',
    ],
    'reminder': [
      'reminder', 'remind', 'yaad', 'note', 'remember',
    ],
    'meeting': [
      'meeting', 'meet', 'call', 'attend', 'attendance',
      'seminar', 'lecture', 'class', 'session',
    ],
  };

  // ── Subject keywords ──────────────────────────────────────────────────────
  static const Map<String, List<String>> _subjects = {
    'Operating Systems': ['os', 'operating system', 'operating systems'],
    'Mathematics': ['maths', 'math', 'mathematics', 'calculus', 'algebra', 'stats', 'statistics'],
    'Database Management': ['dbms', 'database', 'db', 'sql', 'mysql', 'mongodb'],
    'Data Structures': ['dsa', 'ds', 'data structure', 'data structures', 'algorithms', 'algo'],
    'Networks': ['cn', 'network', 'networks', 'computer network', 'networking'],
    'Physics': ['physics', 'phy', 'mechanics', 'thermodynamics', 'optics'],
    'Chemistry': ['chemistry', 'chem', 'organic', 'inorganic'],
    'English': ['english', 'eng', 'communication', 'writing'],
    'Software Engineering': ['se', 'software engineering', 'software', 'sdlc', 'agile'],
    'Machine Learning': ['ml', 'machine learning', 'ai', 'deep learning', 'neural'],
    'Web Development': ['web', 'html', 'css', 'javascript', 'react', 'flask', 'django'],
    'Computer Graphics': ['cg', 'graphics', 'computer graphics', 'opengl'],
    'Theory of Computation': ['toc', 'theory', 'automata', 'compiler'],
  };

  // ── Urgency ───────────────────────────────────────────────────────────────
  static const _urgent = [
    'urgent', 'asap', 'immediately', 'jaldi', 'important',
    'critical', 'must', 'right now', 'priority',
  ];

  // ── Time patterns ─────────────────────────────────────────────────────────
  // Matches: "5pm", "5:30pm", "17:00", "5 pm", "subah 10", "raat 11"
  static final _timeRegex = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m|p\.m)?'
    r'|(\bsubah\b|\bsakal\b)\s*(\d{1,2})'
    r'|(\bshaam\b|\bevening\b)\s*(\d{1,2})'
    r'|(\braat\b|\bright\b|\bnight\b)\s*(\d{1,2})',
    caseSensitive: false,
  );

  // ── Words to strip from task name ─────────────────────────────────────────
  static const _strip = [
    'karna hai', 'karna he', 'karni hai', 'karna ahe',
    'dena hai', 'dena ahe', 'dena he',
    'submit karo', 'submit karna', 'jama karo',
    'bhejo', 'send karo',
    'please', 'pls', 'plz',
    'before', 'by', 'tak', 'paryant', 'by the end of',
    'hai', 'he', 'ahe', 'hoga', 'ahe',
    'note', 'remember', 'yaad rakhna',
    'urgent', 'asap', 'jaldi', 'important',
  ];

  // ═══════════════════════════════════════════════════════════════
  // Main parse entry point
  // ═══════════════════════════════════════════════════════════════
  static ParsedTask parse(String raw) {
    final text = raw.toLowerCase().trim();
    double conf = 0.0;

    final taskType = _detectType(text);
    if (taskType != 'unknown') conf += 0.25;

    final subject = _detectSubject(text);
    if (subject.isNotEmpty) conf += 0.15;

    final dl = _detectDeadline(text);
    if (dl['label'] != 'Unknown') conf += 0.40;

    final priority = _detectPriority(text);
    if (priority == 'urgent') conf += 0.05;

    final name = _buildName(raw, taskType, subject);
    if (name.length > 3) conf += 0.15;

    return ParsedTask(
      taskName: name,
      taskType: taskType,
      deadline: dl['deadline'] as DateTime,
      deadlineLabel: dl['label'] as String,
      priority: priority,
      subject: subject,
      confidence: conf.clamp(0.0, 1.0),
    );
  }

  // ── Type detection ────────────────────────────────────────────────────────
  static String _detectType(String text) {
    for (final entry in _types.entries) {
      for (final kw in entry.value) {
        if (text.contains(kw)) return entry.key;
      }
    }
    return 'assignment'; // safe default
  }

  // ── Subject detection ─────────────────────────────────────────────────────
  static String _detectSubject(String text) {
    for (final entry in _subjects.entries) {
      for (final kw in entry.value) {
        // Use word boundary check for short abbreviations
        if (kw.length <= 3) {
          final r = RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false);
          if (r.hasMatch(text)) return entry.key;
        } else {
          if (text.contains(kw)) return entry.key;
        }
      }
    }
    return '';
  }

  // ── Deadline + time detection ─────────────────────────────────────────────
  static Map<String, dynamic> _detectDeadline(String text) {
    final now = DateTime.now();

    // Try to get time component
    int hour = 23;
    int minute = 59;
    bool timeFound = false;

    final tm = _timeRegex.firstMatch(text);
    if (tm != null) {
      timeFound = true;
      if (tm.group(4) != null) {
        // subah/sakal N
        hour = int.tryParse(tm.group(5) ?? '9') ?? 9;
        if (hour < 6) hour += 12;
      } else if (tm.group(6) != null) {
        // shaam/evening N
        hour = int.tryParse(tm.group(7) ?? '18') ?? 18;
        if (hour < 12) hour += 12;
      } else if (tm.group(8) != null) {
        // raat/night N
        hour = int.tryParse(tm.group(9) ?? '22') ?? 22;
        if (hour < 8) hour += 12;
      } else {
        hour = int.tryParse(tm.group(1) ?? '23') ?? 23;
        minute = int.tryParse(tm.group(2) ?? '0') ?? 0;
        final ampm = (tm.group(3) ?? '').toLowerCase().replaceAll('.', '');
        if (ampm == 'pm' && hour < 12) hour += 12;
        if (ampm == 'am' && hour == 12) hour = 0;
      }
    }

    DateTime makeDate(DateTime base) => DateTime(
      base.year, base.month, base.day,
      timeFound ? hour : 23,
      timeFound ? minute : 59,
    );

    // Today
    for (final w in _today) {
      if (text.contains(w)) {
        return {'deadline': makeDate(now), 'label': 'Today${timeFound ? " at $hour:${minute.toString().padLeft(2,'0')}" : ""}'};
      }
    }

    // Tomorrow
    for (final w in _tomorrow) {
      if (text.contains(w)) {
        final d = now.add(const Duration(days: 1));
        return {'deadline': makeDate(d), 'label': 'Tomorrow${timeFound ? " at $hour:${minute.toString().padLeft(2,'0')}" : ""}'};
      }
    }

    // Day after
    for (final w in _dayAfter) {
      if (text.contains(w)) {
        final d = now.add(const Duration(days: 2));
        return {'deadline': makeDate(d), 'label': 'Day after tomorrow'};
      }
    }

    // Weekday
    for (final entry in _weekdays.entries) {
      if (text.contains(entry.key)) {
        final d = _nextWeekday(now, entry.value);
        final label = entry.key[0].toUpperCase() + entry.key.substring(1);
        return {'deadline': makeDate(d), 'label': label};
      }
    }

    // "in N days/din"
    final nd = RegExp(r'(\d+)\s*(?:din|days?)').firstMatch(text);
    if (nd != null) {
      final n = int.tryParse(nd.group(1) ?? '');
      if (n != null && n > 0) {
        final d = now.add(Duration(days: n));
        return {'deadline': makeDate(d), 'label': 'In $n day${n == 1 ? '' : 's'}'};
      }
    }

    // Next week
    if (text.contains('next week') || text.contains('agli hafte')) {
      final d = now.add(const Duration(days: 7));
      return {'deadline': makeDate(d), 'label': 'Next week'};
    }

    // End of month
    if (text.contains('end of month') || text.contains('month end')) {
      final d = DateTime(now.year, now.month + 1, 0, 23, 59);
      return {'deadline': d, 'label': 'End of month'};
    }

    // Fallback
    return {
      'deadline': DateTime(now.year, now.month, now.day + 1, 23, 59),
      'label': 'Unknown',
    };
  }

  static DateTime _nextWeekday(DateTime from, int weekday) {
    int ahead = weekday - from.weekday;
    if (ahead <= 0) ahead += 7;
    return from.add(Duration(days: ahead));
  }

  // ── Priority ──────────────────────────────────────────────────────────────
  static String _detectPriority(String text) {
    for (final w in _urgent) {
      if (text.contains(w)) return 'urgent';
    }
    return 'normal';
  }

  // ── Clean name ────────────────────────────────────────────────────────────
  static String _buildName(String raw, String taskType, String subject) {
    var name = raw.trim();

    // Remove deadline words
    final deadlineWords = [
      ..._today, ..._tomorrow, ..._dayAfter, ..._weekdays.keys,
      'next week', 'agli hafte', 'end of month',
    ];
    for (final w in deadlineWords) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), '');
    }

    // Remove filler
    for (final w in _strip) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), '');
    }

    // Remove time patterns
    name = name.replaceAll(_timeRegex, '');

    // Remove detected subject keywords if subject was found
    if (subject.isNotEmpty) {
      for (final entry in _subjects.entries) {
        if (entry.key == subject) {
          for (final kw in entry.value) {
            name = name.replaceAll(
                RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false), '');
          }
        }
      }
    }

    name = name.replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (name.isEmpty || name.length < 3) {
      final sub = subject.isNotEmpty ? '$subject ' : '';
      final type = taskType[0].toUpperCase() + taskType.substring(1);
      return '$sub$type';
    }

    return name[0].toUpperCase() + name.substring(1);
  }
}