// lib/parser/task_parser.dart
//
// Tier 1 upgrades:
//   - Ordinal dates: "5th April", "April 5", "5 tarikh"
//   - "this Friday" vs "next Friday" distinction
//   - EOD / COB / end of day
//   - End of week / weekend / end of month / next month
//   - "within N days" same as "in N days"
//   - "before 5pm" / "by 5" / "5 baje ke pehle" / "5 baje tak"
//   - "N hafte mein" / "do din mein" Hinglish durations
//   - Marathi weekdays + "pudhcha somwar" / "ya aathavdyat"
//   - "shukrawar paryant" (weekday + paryant/tak)
//   - "kal subah" → tomorrow morning, "aaj raat" → tonight
//
// Tier 2 upgrades:
//   - Implicit urgency: "!!!", ALL CAPS, deadline within 6h
//   - Context-aware defaults: exam→9am, meeting→10am, rest→11:59pm
//   - Known abbreviation capitalisation: os→OS, dbms→DBMS etc.
//   - Duplicate word removal after stripping
//   - Multi-task detection: splits comma/newline separated inputs
//   - "N baje" time parsing
//   - 24-hour clock support: "17:00"

class ParsedTask {
  final String taskName;
  final String taskType;
  final DateTime deadline;
  final String deadlineLabel;
  final String priority;
  final String subject;
  final double confidence;
  final bool isMultiTask;
  final List<ParsedTask> subtasks;

  const ParsedTask({
    required this.taskName,
    required this.taskType,
    required this.deadline,
    required this.deadlineLabel,
    required this.priority,
    required this.subject,
    required this.confidence,
    this.isMultiTask = false,
    this.subtasks = const [],
  });
}

class TaskParser {

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════

  static ParsedTask parse(String raw) {
    final parts = _splitMultiTask(raw);
    if (parts.length > 1) {
      final subtasks = parts.map(_parseSingle).toList();
      return ParsedTask(
        taskName:      'Multiple tasks',
        taskType:      'assignment',
        deadline:      subtasks.first.deadline,
        deadlineLabel: 'Multiple',
        priority:      subtasks.any((t) => t.priority == 'urgent')
            ? 'urgent' : 'normal',
        subject:       '',
        confidence:    subtasks.fold(0.0, (s, t) => s + t.confidence) /
            subtasks.length,
        isMultiTask:   true,
        subtasks:      subtasks,
      );
    }
    return _parseSingle(raw);
  }

  // ═══════════════════════════════════════════════════════════════
  // MULTI-TASK SPLIT
  // ═══════════════════════════════════════════════════════════════

  static List<String> _splitMultiTask(String raw) {
    final text = raw.toLowerCase();
    // Count deadline signals
    int signals = 0;
    for (final w in [..._today, ..._tomorrow, ..._weekdays.keys]) {
      if (text.contains(w)) { signals++; if (signals >= 2) break; }
    }
    signals += _monthRe.allMatches(text).length;
    if (signals < 2) return [raw];

    final parts = raw
        .split(RegExp(r'\s*,\s*|\n+|\s*;\s*|\s+aur\s+|\s+and\s+|\s+ani\s+',
        caseSensitive: false))
        .map((p) => p.trim())
        .where((p) => p.length > 5)
        .toList();
    return parts.length >= 2 ? parts : [raw];
  }

  // ═══════════════════════════════════════════════════════════════
  // CORE SINGLE PARSER
  // ═══════════════════════════════════════════════════════════════

  static ParsedTask _parseSingle(String raw) {
    final text = raw.toLowerCase().trim();
    double conf = 0.0;

    final taskType = _detectType(text);
    if (taskType != 'assignment') conf += 0.20;

    final subject = _detectSubject(text);
    if (subject.isNotEmpty) conf += 0.15;

    final dl = _detectDeadline(text, taskType);
    if (dl['label'] != 'Unknown') conf += 0.40;

    final deadline = dl['deadline'] as DateTime;
    final priority = _detectPriority(text, deadline);
    if (priority == 'urgent') conf += 0.05;

    final name = _buildName(raw, taskType, subject);
    if (name.length > 3) conf += 0.20;

    return ParsedTask(
      taskName:      name,
      taskType:      taskType,
      deadline:      deadline,
      deadlineLabel: dl['label'] as String,
      priority:      priority,
      subject:       subject,
      confidence:    conf.clamp(0.0, 1.0),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // KNOWN ABBREVIATION MAP
  // ═══════════════════════════════════════════════════════════════

  static const Map<String, String> _abbrevCaps = {
    'os':    'OS',    'dbms':  'DBMS',  'dsa':   'DSA',
    'cn':    'CN',    'se':    'SE',    'ml':    'ML',
    'ai':    'AI',    'toc':   'TOC',   'cg':    'CG',
    'html':  'HTML',  'css':   'CSS',   'sql':   'SQL',
    'php':   'PHP',   'ui':    'UI',    'ux':    'UX',
    'api':   'API',   'http':  'HTTP',  'oop':   'OOP',
    'oops':  'OOPS',  'jdbc':  'JDBC',  'mvc':   'MVC',
  };

  // ═══════════════════════════════════════════════════════════════
  // DAY WORD LISTS
  // ═══════════════════════════════════════════════════════════════

  static const _today = [
    'tonight', 'aaj raat', 'aaj hi', 'today', 'aaj', 'aj',
    'aajke', 'eod', 'end of day', 'cob', 'by tonight', 'abhi',
  ];

  static const _tomorrow = [
    'kal subah', 'kal raat', 'tomorrow', 'tmrw', 'tmr',
    'kal', 'kl', 'udya', 'udhya', 'next day', 'agle din', 'kal tak',
  ];

  static const _dayAfter = [
    'parso', 'day after tomorrow', 'parva', 'paradnya',
  ];

  // ── Weekdays ───────────────────────────────────────────────────
  static const Map<String, int> _weekdays = {
    'monday':         DateTime.monday,
    'mon':            DateTime.monday,
    'somwar':         DateTime.monday,
    'somvaar':        DateTime.monday,
    'pudhcha somwar': DateTime.monday,
    'tuesday':        DateTime.tuesday,
    'tue':            DateTime.tuesday,
    'mangalwar':      DateTime.tuesday,
    'wednesday':      DateTime.wednesday,
    'wed':            DateTime.wednesday,
    'budhwar':        DateTime.wednesday,
    'budhvaar':       DateTime.wednesday,
    'thursday':       DateTime.thursday,
    'thu':            DateTime.thursday,
    'guruwar':        DateTime.thursday,
    'guruvaar':       DateTime.thursday,
    'friday':         DateTime.friday,
    'fri':            DateTime.friday,
    'shukrawar':      DateTime.friday,
    'shukravaar':     DateTime.friday,
    'saturday':       DateTime.saturday,
    'sat':            DateTime.saturday,
    'shaniwar':       DateTime.saturday,
    'sunday':         DateTime.sunday,
    'sun':            DateTime.sunday,
    'raviwar':        DateTime.sunday,
    'ravivaar':       DateTime.sunday,
  };

  // ── Month names ────────────────────────────────────────────────
  static const Map<String, int> _months = {
    'january':1,  'jan':1,  'february':2, 'feb':2,
    'march':3,    'mar':3,  'april':4,    'apr':4,
    'may':5,      'june':6, 'jun':6,      'july':7,
    'jul':7,      'august':8,'aug':8,     'september':9,
    'sep':9,      'sept':9, 'october':10, 'oct':10,
    'november':11,'nov':11, 'december':12,'dec':12,
  };

  static final _monthRe = RegExp(
      _months.keys.join('|'), caseSensitive: false);

  // Ordinal + month: "5th April", "April 5", "5 April"
  static final _ordinalRe = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(' +
        _months.keys.join('|') +
        r')\b|\b(' +
        _months.keys.join('|') +
        r')\s+(\d{1,2})(?:st|nd|rd|th)?\b',
    caseSensitive: false,
  );

  // "5 tarikh"
  static final _tarikhRe = RegExp(
      r'\b(\d{1,2})\s*(?:tarikh|tारीख)\b', caseSensitive: false);

  // ═══════════════════════════════════════════════════════════════
  // TASK TYPES
  // ═══════════════════════════════════════════════════════════════

  static const Map<String, List<String>> _types = {
    'assignment': [
      'assignment', 'assignmnt', 'homework', 'hw', 'project',
      'proj', 'practical', 'lab', 'coursework', 'practicals',
    ],
    'exam': [
      'exam', 'exm', 'test', 'quiz', 'viva', 'oral', 'paper',
      'midsem', 'mid sem', 'endsem', 'end sem',
      'unit test', 'ut', 'class test', 'ct', 'final', 'finals',
      'assessment',
    ],
    'submission': [
      'submit', 'submission', 'sbmit', 'jama', 'upload',
      'dena hai', 'dena ahe', 'bhejo', 'form',
      'jama karo', 'jama kar',
    ],
    'reminder': [
      'reminder', 'remind', 'yaad', 'note', 'remember',
      'lakshat thev',
    ],
    'meeting': [
      'meeting', 'meet', 'call', 'attend', 'attendance',
      'seminar', 'lecture', 'class', 'session', 'workshop',
    ],
  };

  // ═══════════════════════════════════════════════════════════════
  // SUBJECTS
  // ═══════════════════════════════════════════════════════════════

  static const Map<String, List<String>> _subjects = {
    'Operating Systems':    ['os', 'operating system', 'operating systems'],
    'Mathematics':          ['maths', 'math', 'mathematics', 'calculus',
      'algebra', 'stats', 'statistics', 'ganit'],
    'Database Management':  ['dbms', 'database', 'db', 'sql', 'mysql',
      'mongodb', 'postgres'],
    'Data Structures':      ['dsa', 'data structure', 'data structures',
      'algorithms', 'algo'],
    'Computer Networks':    ['cn', 'network', 'networks', 'computer network',
      'networking'],
    'Physics':              ['physics', 'phy', 'mechanics', 'optics',
      'bhautikashastra'],
    'Chemistry':            ['chemistry', 'chem', 'organic', 'inorganic',
      'rasayan'],
    'English':              ['english', 'communication', 'writing', 'grammar'],
    'Software Engineering': ['se', 'software engineering', 'sdlc', 'agile'],
    'Machine Learning':     ['ml', 'machine learning', 'deep learning',
      'neural', 'ai'],
    'Web Development':      ['web', 'html', 'css', 'javascript', 'react',
      'flask', 'django', 'nodejs'],
    'Computer Graphics':    ['cg', 'graphics', 'computer graphics', 'opengl'],
    'Theory of Computation':['toc', 'automata', 'compiler'],
    'Java':                 ['java', 'oops', 'oop', 'object oriented'],
    'Python':               ['python', 'py'],
  };

  // ═══════════════════════════════════════════════════════════════
  // URGENCY WORDS
  // ═══════════════════════════════════════════════════════════════

  static const _urgentWords = [
    'urgent', 'asap', 'immediately', 'jaldi', 'important',
    'critical', 'must', 'right now', 'priority', 'aaj hi',
    'please please', 'help help', 'abhi abhi',
  ];

  // ═══════════════════════════════════════════════════════════════
  // TIME REGEXES
  // ═══════════════════════════════════════════════════════════════

  // 12h: "5pm" "5:30pm" "5 pm" "5.30 am"
  static final _re12h = RegExp(
    r'\b(\d{1,2})(?:[:.]\s*(\d{2}))?\s*(am|pm|a\.m\.?|p\.m\.?)\b',
    caseSensitive: false,
  );
  // 24h: "17:00" "09:30"
  static final _re24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  // "5 baje"
  static final _reBaje = RegExp(r'\b(\d{1,2})\s*baje\b', caseSensitive: false);
  // "before/by/tak 5pm"
  static final _reBefore = RegExp(
    r'(?:before|by|tak|pehle|paryant)\s+(\d{1,2})(?:[:.]\s*(\d{2}))?\s*(am|pm)?\b',
    caseSensitive: false,
  );
  // Context words
  static final _reSubah   = RegExp(r'\b(subah|sakaal|sakal|morning)\b', caseSensitive: false);
  static final _reShaam   = RegExp(r'\b(shaam|sandhya|evening)\b',      caseSensitive: false);
  static final _reRaat    = RegExp(r'\b(raat|raatri|night)\b',          caseSensitive: false);
  static final _reDopahar = RegExp(r'\b(dopahar|duphar|noon|afternoon)\b', caseSensitive: false);

  // Durations
  static final _reDays  = RegExp(
    r'(?:within|in|mein|me)?\s*(\d+)\s*(?:din|days?|divas)',
    caseSensitive: false,
  );
  static final _reWeeks = RegExp(
    r'(\d+|ek|do|teen|char|one|two|three)\s*(?:weeks?|hafte)',
    caseSensitive: false,
  );
  static const _wordNums = {
    'ek':1,'do':2,'teen':3,'char':4,'one':1,'two':2,'three':3,
  };

  // Strip words
  static const _strip = [
    'karna hai','karna he','karni hai','karna ahe','karayche ahe',
    'dena hai','dena ahe','dena he',
    'submit karo','submit karna','jama karo','jama kar',
    'bhejo','send karo',
    'please','pls','plz',
    'before','by','tak','paryant','paryant',
    'hai','he','ahe','hoga',
    'note','remember','yaad rakhna','lakshat thev',
    'urgent','asap','jaldi','important',
  ];

  // ═══════════════════════════════════════════════════════════════
  // TYPE DETECTION
  // ═══════════════════════════════════════════════════════════════

  static String _detectType(String text) {
    for (final e in _types.entries) {
      for (final kw in e.value) {
        if (text.contains(kw)) return e.key;
      }
    }
    return 'assignment';
  }

  // ═══════════════════════════════════════════════════════════════
  // SUBJECT DETECTION
  // ═══════════════════════════════════════════════════════════════

  static String _detectSubject(String text) {
    for (final e in _subjects.entries) {
      for (final kw in e.value) {
        final pattern = kw.length <= 3
            ? RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false)
            : RegExp(RegExp.escape(kw), caseSensitive: false);
        if (pattern.hasMatch(text)) return e.key;
      }
    }
    return '';
  }

  // ═══════════════════════════════════════════════════════════════
  // TIME EXTRACTION
  // ═══════════════════════════════════════════════════════════════

  static Map<String, dynamic> _extractTime(String text) {
    // "5 baje" — check context for AM/PM
    final bm = _reBaje.firstMatch(text);
    if (bm != null) {
      int h = int.parse(bm.group(1)!);
      if ((_reRaat.hasMatch(text) || _reShaam.hasMatch(text)) && h < 12) h += 12;
      return {'h': h, 'm': 0, 'found': true};
    }

    // "before/by/tak N"
    final bf = _reBefore.firstMatch(text);
    if (bf != null) {
      int h = int.parse(bf.group(1)!);
      final mn = int.tryParse(bf.group(2) ?? '0') ?? 0;
      final ap = (bf.group(3) ?? '').toLowerCase();
      if (ap == 'pm' && h < 12) h += 12;
      if (ap == 'am' && h == 12) h = 0;
      if (ap.isEmpty && h <= 6) h += 12; // "by 5" → 5pm
      return {'h': h, 'm': mn, 'found': true};
    }

    // 12h clock
    final m12 = _re12h.firstMatch(text);
    if (m12 != null) {
      int h = int.parse(m12.group(1)!);
      final mn = int.tryParse(m12.group(2) ?? '0') ?? 0;
      final ap = m12.group(3)!.toLowerCase().replaceAll('.', '');
      if (ap.startsWith('p') && h < 12) h += 12;
      if (ap.startsWith('a') && h == 12) h = 0;
      return {'h': h, 'm': mn, 'found': true};
    }

    // 24h clock
    final m24 = _re24h.firstMatch(text);
    if (m24 != null) {
      return {'h': int.parse(m24.group(1)!),
        'm': int.parse(m24.group(2)!), 'found': true};
    }

    // Context words
    if (_reSubah.hasMatch(text))   return {'h': 9,  'm': 0, 'found': true};
    if (_reDopahar.hasMatch(text)) return {'h': 12, 'm': 0, 'found': true};
    if (_reShaam.hasMatch(text))   return {'h': 18, 'm': 0, 'found': true};
    if (_reRaat.hasMatch(text))    return {'h': 22, 'm': 0, 'found': true};

    return {'h': null, 'm': null, 'found': false};
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTEXT-AWARE DEFAULT TIME
  // ═══════════════════════════════════════════════════════════════

  static int _defH(String type) {
    switch (type) {
      case 'exam':    return 9;
      case 'meeting': return 10;
      default:        return 23;
    }
  }

  static int _defM(String type) =>
      (type == 'exam' || type == 'meeting') ? 0 : 59;

  // ═══════════════════════════════════════════════════════════════
  // DEADLINE DETECTION
  // ═══════════════════════════════════════════════════════════════

  static Map<String, dynamic> _detectDeadline(String text, String type) {
    final now = DateTime.now();
    final t   = _extractTime(text);
    final tf  = t['found'] as bool;
    final h   = tf ? t['h'] as int : _defH(type);
    final m   = tf ? t['m'] as int : _defM(type);

    // Build a DateTime from a date + extracted/default time
    DateTime dt(DateTime base) =>
        DateTime(base.year, base.month, base.day, h, m);

    final tStr = tf
        ? ' at ${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}'
        : '';

    // ── EOD / COB ──────────────────────────────────────────────
    if (RegExp(r'\b(eod|cob|end of day|end-of-day)\b',
        caseSensitive: false).hasMatch(text)) {
      return {'deadline': DateTime(now.year,now.month,now.day,23,59),
        'label': 'Today (EOD)'};
    }

    // ── Tonight / aaj raat ────────────────────────────────────
    if (text.contains('tonight') || text.contains('aaj raat')) {
      return {'deadline': DateTime(now.year,now.month,now.day, tf?h:23, tf?m:0),
        'label': 'Tonight'};
    }

    // ── Today ─────────────────────────────────────────────────
    for (final w in _today) {
      if (text.contains(w)) {
        return {'deadline': dt(now), 'label': 'Today$tStr'};
      }
    }

    // ── Kal subah ─────────────────────────────────────────────
    if (text.contains('kal subah')) {
      final d = now.add(const Duration(days: 1));
      return {'deadline': DateTime(d.year,d.month,d.day, tf?h:9, tf?m:0),
        'label': 'Tomorrow morning'};
    }

    // ── Tomorrow ──────────────────────────────────────────────
    for (final w in _tomorrow) {
      if (text.contains(w)) {
        final d = now.add(const Duration(days: 1));
        return {'deadline': dt(d), 'label': 'Tomorrow$tStr'};
      }
    }

    // ── Day after tomorrow ────────────────────────────────────
    for (final w in _dayAfter) {
      if (text.contains(w)) {
        return {'deadline': dt(now.add(const Duration(days: 2))),
          'label': 'Day after tomorrow'};
      }
    }

    // ── "this/next Friday" ────────────────────────────────────
    final tnRe = RegExp(
      r'\b(this|next|aagla|pudhcha)\s+(' + _weekdays.keys.join('|') + r')\b',
      caseSensitive: false,
    );
    final tnM = tnRe.firstMatch(text);
    if (tnM != null) {
      final mod   = tnM.group(1)!.toLowerCase();
      final day   = tnM.group(2)!.toLowerCase();
      final wday  = _weekdays[day]!;
      final force = mod == 'next' || mod == 'aagla' || mod == 'pudhcha';
      final d     = _nextWD(now, wday, forceNext: force);
      final label = '${_cap(mod)} ${_cap(day)}';
      return {'deadline': dt(d), 'label': label};
    }

    // ── "shukrawar paryant / tak" ─────────────────────────────
    final paryantRe = RegExp(
      r'(' + _weekdays.keys.join('|') + r')\s*(?:paryant|tak|until|by)',
      caseSensitive: false,
    );
    final pM = paryantRe.firstMatch(text);
    if (pM != null) {
      final day = pM.group(1)!.toLowerCase();
      final d   = _nextWD(now, _weekdays[day]!);
      return {'deadline': dt(d), 'label': _cap(day)};
    }

    // ── Plain weekday ─────────────────────────────────────────
    for (final e in _weekdays.entries) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b',
          caseSensitive: false).hasMatch(text)) {
        final d = _nextWD(now, e.value);
        return {'deadline': dt(d), 'label': '${_cap(e.key)}$tStr'};
      }
    }

    // ── Ordinal date: "5th April" / "April 5" ─────────────────
    final om = _ordinalRe.firstMatch(text);
    if (om != null) {
      int day, mon;
      if (om.group(1) != null) {
        day = int.parse(om.group(1)!);
        mon = _months[om.group(2)!.toLowerCase()]!;
      } else {
        mon = _months[om.group(3)!.toLowerCase()]!;
        day = int.parse(om.group(4)!);
      }
      var yr = now.year;
      if (DateTime(yr, mon, day).isBefore(now)) yr++;
      return {
        'deadline': DateTime(yr, mon, day, h, m),
        'label': '$day ${_monthName(mon)}',
      };
    }

    // ── "5 tarikh" ────────────────────────────────────────────
    final tkM = _tarikhRe.firstMatch(text);
    if (tkM != null) {
      final day = int.parse(tkM.group(1)!);
      var d = DateTime(now.year, now.month, day);
      if (d.isBefore(now)) d = DateTime(now.year, now.month + 1, day);
      return {'deadline': DateTime(d.year,d.month,d.day,h,m),
        'label': '$day tarikh'};
    }

    // ── End of week / weekend ─────────────────────────────────
    if (RegExp(r'\b(end of week|weekend|this week|ya aathavdyat)\b',
        caseSensitive: false).hasMatch(text)) {
      final d = _nextWD(now, DateTime.sunday);
      return {'deadline': DateTime(d.year,d.month,d.day,23,59),
        'label': 'End of week'};
    }

    // ── End of month ──────────────────────────────────────────
    if (RegExp(r'\b(end of month|month end|mahina end)\b',
        caseSensitive: false).hasMatch(text)) {
      final d = DateTime(now.year, now.month + 1, 0);
      return {'deadline': DateTime(d.year,d.month,d.day,23,59),
        'label': 'End of month'};
    }

    // ── Next month ────────────────────────────────────────────
    if (RegExp(r'\b(next month|agle mahine|pudhcha mahina)\b',
        caseSensitive: false).hasMatch(text)) {
      final d = DateTime(now.year, now.month + 1, 1);
      return {'deadline': dt(d), 'label': 'Next month'};
    }

    // ── "N weeks / hafte" ─────────────────────────────────────
    final wm = _reWeeks.firstMatch(text);
    if (wm != null) {
      final raw = wm.group(1)!.toLowerCase();
      final n   = int.tryParse(raw) ?? _wordNums[raw] ?? 1;
      final d   = now.add(Duration(days: n * 7));
      return {'deadline': dt(d),
        'label': 'In $n week${n==1?'':'s'}'};
    }

    // ── "next week / agli hafte" ──────────────────────────────
    if (RegExp(r'\b(next week|agli hafte|agle hafte)\b',
        caseSensitive: false).hasMatch(text)) {
      return {'deadline': dt(now.add(const Duration(days: 7))),
        'label': 'Next week'};
    }

    // ── "in N days / din" ─────────────────────────────────────
    final dm = _reDays.firstMatch(text);
    if (dm != null) {
      final n = int.tryParse(dm.group(1) ?? '') ?? 1;
      if (n > 0 && n <= 365) {
        final d = now.add(Duration(days: n));
        return {'deadline': dt(d),
          'label': 'In $n day${n==1?'':'s'}'};
      }
    }

    // ── Fallback ──────────────────────────────────────────────
    return {
      'deadline': DateTime(now.year,now.month,now.day+1, _defH(type), _defM(type)),
      'label': 'Unknown',
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // PRIORITY (tier 2: implicit signals)
  // ═══════════════════════════════════════════════════════════════

  static String _detectPriority(String text, DateTime deadline) {
    // Explicit words
    for (final w in _urgentWords) {
      if (text.contains(w)) return 'urgent';
    }
    // "!!!" or "!!"
    if (RegExp(r'!{2,}').hasMatch(text)) return 'urgent';
    // ALL CAPS (≥8 letter chars, >70% uppercase)
    final ups  = RegExp(r'[A-Z]').allMatches(text).length;
    final lets = RegExp(r'[a-zA-Z]').allMatches(text).length;
    if (lets >= 8 && ups / lets > 0.70) return 'urgent';
    // Deadline within 6 hours
    final diff = deadline.difference(DateTime.now());
    if (diff.inMinutes > 0 && diff.inHours < 6) return 'urgent';
    return 'normal';
  }

  // ═══════════════════════════════════════════════════════════════
  // NAME BUILDER (tier 2: smarter cleaning)
  // ═══════════════════════════════════════════════════════════════

  static String _buildName(String raw, String type, String subject) {
    var name = raw.trim();

    // Remove all date/time words
    for (final w in [..._today, ..._tomorrow, ..._dayAfter,
      ..._weekdays.keys,
      'next week','agli hafte','agle hafte',
      'end of month','month end','end of week','weekend',
      'next month','eod','cob','end of day']) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ' ');
    }
    // Remove time patterns
    name = name
        .replaceAll(_re12h, ' ').replaceAll(_re24h, ' ')
        .replaceAll(_reBaje, ' ').replaceAll(_reBefore, ' ')
        .replaceAll(_reSubah, ' ').replaceAll(_reShaam, ' ')
        .replaceAll(_reRaat, ' ').replaceAll(_reDopahar, ' ')
        .replaceAll(_reDays, ' ').replaceAll(_reWeeks, ' ')
        .replaceAll(_ordinalRe, ' ').replaceAll(_tarikhRe, ' ');
    // Remove filler
    for (final w in _strip) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ' ');
    }
    // Remove urgency words
    for (final w in _urgentWords) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ' ');
    }
    // Remove subject keywords
    if (subject.isNotEmpty) {
      for (final e in _subjects.entries) {
        if (e.key == subject) {
          for (final kw in e.value) {
            name = name.replaceAll(
                RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false), ' ');
          }
        }
      }
    }

    // Strip punctuation, collapse spaces
    name = name.replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove duplicate consecutive words
    final words  = name.split(' ');
    final deduped = <String>[];
    for (var i = 0; i < words.length; i++) {
      if (i == 0 || words[i].toLowerCase() != words[i-1].toLowerCase()) {
        deduped.add(words[i]);
      }
    }
    name = deduped.join(' ').trim();

    // Fallback if nothing left
    if (name.length < 3) {
      final sub = subject.isNotEmpty ? '$subject ' : '';
      return '$sub${_cap(type)}';
    }

    // Capitalise known abbreviations
    _abbrevCaps.forEach((low, up) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(low)}\\b', caseSensitive: false), up);
    });

    // Sentence case
    return name[0].toUpperCase() + name.substring(1);
  }

  // ═══════════════════════════════════════════════════════════════
  // SMALL HELPERS
  // ═══════════════════════════════════════════════════════════════

  static DateTime _nextWD(DateTime from, int weekday,
      {bool forceNext = false}) {
    int ahead = weekday - from.weekday;
    if (ahead <= 0 || forceNext) ahead += 7;
    return from.add(Duration(days: ahead));
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _monthName(int n) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ][n];
}
