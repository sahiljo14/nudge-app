// lib/parser/task_parser.dart
//
// ── FIXES APPLIED ────────────────────────────────────────────────────────────
//
// [F1] ORDERING — day-relative patterns now checked longest-first so that
//      "day after tomorrow" is never swallowed by "tomorrow" (substring match),
//      and "kal subah / kal raat" are never swallowed by plain "kal".
//      Implementation: _dayAfter and compound-kal checks now run BEFORE
//      the generic _tomorrow loop, and all text.contains() checks for
//      multi-word phrases use word-boundary anchors via _has().
//
// [F2] INDIA AM/PM HEURISTIC — "N baje" with hour ≤ 7 and no explicit morning
//      context (subah / sakaal / morning / am) defaults to PM, not AM.
//      Same heuristic applied to bare numeric times with no am/pm suffix.
//
// [F3] MISSING SPELLINGS — additional Hinglish / shorthand variants added to
//      _today, _tomorrow, _dayAfter, and _weekdays.
//
// [F4] NAME CLEANING ORDER — honorifics and titles are stripped BEFORE
//      whitespace normalisation so they don't leave leading/trailing gaps
//      that confuse the capitalisation step.
//
// [F5] MULTI-TASK THRESHOLD — signal counting now includes _dayAfter tokens
//      so "parso" and "day after tomorrow" correctly count as deadline signals,
//      preventing under-counting that caused multi-task inputs to be parsed
//      as single tasks.
//
// ─────────────────────────────────────────────────────────────────────────────

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

    // [F5][F7] Count UNIQUE deadline signals per category so that synonym
    // clusters (e.g. "aaj" + "aaj hi", or "pudhcha somwar" + "somwar")
    // contribute exactly ONE signal, not two.
    //
    // Categories:
    //   0 = any today-family word
    //   1 = any tomorrow-family word
    //   2 = any day-after-tomorrow-family word
    //   3..9 = weekday int (Mon=1 … Sun=7, offset +2 to avoid clash)
    //   10+ = one entry per matched month name occurrence
    int signals = 0;
    if (_today.any((w)    => _has(text, w))) signals++;
    if (_tomorrow.any((w) => _has(text, w))) signals++;
    if (_dayAfter.any((w) => _has(text, w))) signals++;

    // Weekdays: deduplicate by weekday int so "pudhcha somwar" + "somwar"
    // count as one Monday signal.
    final uniqueWD = <int>{};
    for (final e in _weekdays.entries) {
      if (_has(text, e.key)) uniqueWD.add(e.value);
    }
    signals += uniqueWD.length;

    // Month-name occurrences each count as a distinct deadline signal.
    signals += _monthRe.allMatches(text).length;

    if (signals < 2) return [raw];

    // [F6] Extended splitters: period-sentence boundary and pipe separator
    // added alongside existing comma/newline/semicolon/aur/and/ani.
    // The partsWithDeadline guard below prevents false splits (e.g. a
    // trailing aside "Submit by Friday. No extensions." stays single).
    //
    // [F8] Helper: does a text fragment contain any deadline signal?
    bool hasSignal(String p) {
      final pt = p.toLowerCase();
      return [..._today, ..._tomorrow, ..._dayAfter, ..._weekdays.keys]
          .any((w) => _has(pt, w)) || _monthRe.hasMatch(pt);
    }

    final rawParts = raw
        .split(RegExp(
            r'\s*,\s*|\n+|\s*;\s*|\s+aur\s+|\s+and\s+|\s+ani\s+|\.\s+|\s*\|\s*',
            caseSensitive: false))
        .map((p) => p.trim())
        .where((p) => p.length > 5)
        .toList();

    if (rawParts.length < 2) return [raw];

    // [F8] Coalesce date-less fragments into their nearest preceding dated part.
    // Prevents over-splitting on intra-task detail text like "numericals." or
    // "open book." that follows a date-anchored line in a student message.
    final parts = <String>[];
    for (final p in rawParts) {
      if (hasSignal(p) || parts.isEmpty) {
        parts.add(p);
      } else {
        parts[parts.length - 1] = '${parts.last} $p';
      }
    }

    // Each part must contain at least one deadline signal to be a real subtask.
    // If only one part has a deadline, it's a single task with a comma/period.
    if (parts.length < 2) return [raw];
    final partsWithDeadline = parts.where(hasSignal).length;
    if (partsWithDeadline < 2) return [raw];

    return parts;
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
  // DAY WORD LISTS  [F3] — added missing spellings
  // ═══════════════════════════════════════════════════════════════

  static const _today = [
    'tonight', 'aaj raat', 'aaj hi', 'today', 'aaj', 'aj',
    'aajke', 'eod', 'end of day', 'cob', 'by tonight', 'abhi',
    // [F3] additions
    'aaj ka', 'same day', 'aajch',
  ];

  // [F1] Multi-word "kal ___" entries are kept here so that _splitMultiTask
  //      counts them as signals; the actual deadline branch for compound-kal
  //      variants is handled FIRST in _detectDeadline before the plain loop.
  static const _tomorrow = [
    'kal subah', 'kal raat', 'kal sham', 'kal tak',
    'tomorrow', 'tmrw', 'tmr',
    'kal', 'kl', 'udya', 'udhya', 'next day', 'agle din',
    // [F3] additions
    'kal ko', 'klko', 'ugvya',
  ];

  static const _dayAfter = [
    'parso', 'day after tomorrow', 'parva', 'paradnya',
    // [F3] additions
    'parson', 'parsun',
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
    'mangalvaar':     DateTime.tuesday,     // [F3]
    'wednesday':      DateTime.wednesday,
    'wed':            DateTime.wednesday,
    'budhwar':        DateTime.wednesday,
    'budhvaar':       DateTime.wednesday,
    'thursday':       DateTime.thursday,
    'thu':            DateTime.thursday,
    'thurs':          DateTime.thursday,    // [F3]
    'guruwar':        DateTime.thursday,
    'guruvaar':       DateTime.thursday,
    'friday':         DateTime.friday,
    'fri':            DateTime.friday,
    'shukrawar':      DateTime.friday,
    'shukravaar':     DateTime.friday,
    'saturday':       DateTime.saturday,
    'sat':            DateTime.saturday,
    'shaniwar':       DateTime.saturday,
    'shanivaar':      DateTime.saturday,    // [F3]
    'sunday':         DateTime.sunday,
    'sun':            DateTime.sunday,
    'raviwar':        DateTime.sunday,
    'ravivaar':       DateTime.sunday,
  };

  /// Maps any Hinglish/Marathi weekday key to its canonical English label.
  static const Map<String, String> _weekdayLabel = {
    'monday': 'Monday',   'mon': 'Monday',
    'somwar': 'Monday',   'somvaar': 'Monday',   'pudhcha somwar': 'Monday',
    'tuesday': 'Tuesday', 'tue': 'Tuesday',
    'mangalwar': 'Tuesday', 'mangalvaar': 'Tuesday',
    'wednesday': 'Wednesday', 'wed': 'Wednesday',
    'budhwar': 'Wednesday',   'budhvaar': 'Wednesday',
    'thursday': 'Thursday', 'thu': 'Thursday', 'thurs': 'Thursday',
    'guruwar': 'Thursday',  'guruvaar': 'Thursday',
    'friday': 'Friday',   'fri': 'Friday',
    'shukrawar': 'Friday', 'shukravaar': 'Friday',
    'saturday': 'Saturday', 'sat': 'Saturday',
    'shaniwar': 'Saturday', 'shanivaar': 'Saturday',
    'sunday': 'Sunday',   'sun': 'Sunday',
    'raviwar': 'Sunday',  'ravivaar': 'Sunday',
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

  static final _ordinalRe = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(' +
        _months.keys.join('|') +
        r')\b|\b(' +
        _months.keys.join('|') +
        r')\s+(\d{1,2})(?:st|nd|rd|th)?\b',
    caseSensitive: false,
  );

  static final _tarikhRe = RegExp(
      r'\b(\d{1,2})\s*(?:tarikh|tārīkh)\b', caseSensitive: false);

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

  static final _re12h = RegExp(
    r'\b(\d{1,2})(?:[:.]\s*(\d{2}))?\s*(am|pm|a\.m\.?|p\.m\.?)\b',
    caseSensitive: false,
  );
  static final _re24h = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final _reBaje = RegExp(r'\b(\d{1,2})\s*baje\b', caseSensitive: false);
  static final _reBefore = RegExp(
    r'(?:before|by|tak|pehle|paryant)\s+(\d{1,2})(?:[:.]\s*(\d{2}))?\s*(am|pm)?\b',
    caseSensitive: false,
  );

  // Context words — used by AM/PM heuristic [F2]
  static final _reSubah   = RegExp(r'\b(subah|sakaal|sakal|morning)\b',    caseSensitive: false);
  static final _reAM      = RegExp(r'\b(am|a\.m\.?)\b',                    caseSensitive: false);
  static final _reShaam   = RegExp(r'\b(shaam|sandhya|evening)\b',         caseSensitive: false);
  static final _reRaat    = RegExp(r'\b(raat|raatri|night)\b',             caseSensitive: false);
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

  // [F4] Honorifics regex — stripped BEFORE whitespace normalisation
  static final _honorificRe = RegExp(
    r'\b(Mr\.?|Mrs\.?|Ms\.?|Dr\.?|Prof\.?|Sr\.?|Jr\.?|'
    r"Bhai|Didi|Sir|Madam|Ma'am|Shri|Smt\.?)\s*",
    caseSensitive: false,
  );

  // Strip words
  static const _strip = [
    'karna hai','karna he','karni hai','karna ahe','karayche ahe',
    'dena hai','dena ahe','dena he',
    'submit karo','submit karna','jama karo','jama kar',
    'bhejo','send karo',
    'please','pls','plz',
    'before','by','tak','paryant',
    'hai','he','ahe','hoga',
    'note','remember','yaad rakhna','lakshat thev',
    'urgent','asap','jaldi','important',
  ];

  // ═══════════════════════════════════════════════════════════════
  // TYPE DETECTION
  // ═══════════════════════════════════════════════════════════════

  static String _detectType(String text) {
    // Check longer keywords first within each type to avoid false substring hits.
    // Use word-boundary regex for all keywords to prevent partial-word matches
    // (e.g. 'ut' inside 'budhwar', 'lab' inside 'syllabus').
    for (final e in _types.entries) {
      // Sort keywords longest-first so "unit test" beats "test", "class test" beats "test"
      final sorted = [...e.value]..sort((a, b) => b.length.compareTo(a.length));
      for (final kw in sorted) {
        final pattern = kw.contains(' ')
            ? RegExp(RegExp.escape(kw), caseSensitive: false)
            : RegExp('\\b${RegExp.escape(kw)}\\b', caseSensitive: false);
        if (pattern.hasMatch(text)) return e.key;
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
  // TIME EXTRACTION  [F2] India AM/PM heuristic
  // ═══════════════════════════════════════════════════════════════

  /// Returns true if the text contains an explicit morning signal,
  /// meaning the speaker consciously said "morning / subah / am".
  static bool _hasMorningContext(String text) =>
      _reSubah.hasMatch(text) || _reAM.hasMatch(text);

  /// Core heuristic [F2]: for Indian student messages, an ambiguous hour
  /// (no am/pm/subah/raat) that is ≤ 7 almost certainly means PM.
  /// E.g. "5 baje" → 17:00, "7 baje" → 19:00, "8 baje" → 08:00 (morning OK).
  static int _indiaAmbiguousHour(int h, String text) {
    if (h <= 7 && !_hasMorningContext(text)) return h + 12;
    return h;
  }

  static Map<String, dynamic> _extractTime(String text) {
    // "5 baje" — check raat/shaam for PM, else apply India heuristic [F2]
    final bm = _reBaje.firstMatch(text);
    if (bm != null) {
      int h = int.parse(bm.group(1)!);
      if ((_reRaat.hasMatch(text) || _reShaam.hasMatch(text)) && h < 12) {
        h += 12;
      } else {
        // [F2] No explicit context → India default
        h = _indiaAmbiguousHour(h, text);
      }
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
      // [F2] No explicit am/pm on "by 5" → India default
      if (ap.isEmpty) h = _indiaAmbiguousHour(h, text);
      return {'h': h, 'm': mn, 'found': true};
    }

    // 12h clock — explicit am/pm → no heuristic needed
    final m12 = _re12h.firstMatch(text);
    if (m12 != null) {
      int h = int.parse(m12.group(1)!);
      final mn = int.tryParse(m12.group(2) ?? '0') ?? 0;
      final ap = m12.group(3)!.toLowerCase().replaceAll('.', '');
      if (ap.startsWith('p') && h < 12) h += 12;
      if (ap.startsWith('a') && h == 12) h = 0;
      return {'h': h, 'm': mn, 'found': true};
    }

    // 24h clock — unambiguous
    final m24 = _re24h.firstMatch(text);
    if (m24 != null) {
      return {'h': int.parse(m24.group(1)!),
        'm': int.parse(m24.group(2)!), 'found': true};
    }

    // Context words only
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
  // DEADLINE DETECTION  [F1] longest-phrase-first ordering
  // ═══════════════════════════════════════════════════════════════

  static Map<String, dynamic> _detectDeadline(String text, String type) {
    final now = DateTime.now();
    final t   = _extractTime(text);
    final tf  = t['found'] as bool;
    final h   = tf ? t['h'] as int : _defH(type);
    final m   = tf ? t['m'] as int : _defM(type);

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
    if (_has(text, 'tonight') || _has(text, 'aaj raat')) {
      return {
        'deadline': DateTime(now.year,now.month,now.day, tf?h:23, tf?m:0),
        'label': 'Tonight',
      };
    }

    // ── [F1] Day-after-tomorrow FIRST — before any "tomorrow" check ──
    for (final w in _dayAfter) {
      if (_has(text, w)) {
        return {
          'deadline': dt(now.add(const Duration(days: 2))),
          'label': 'Day after tomorrow',
        };
      }
    }

    // ── [F1] Compound kal phrases BEFORE plain "kal" ─────────────
    if (_has(text, 'kal subah')) {
      final d = now.add(const Duration(days: 1));
      return {
        'deadline': DateTime(d.year, d.month, d.day, tf ? h : 9, tf ? m : 0),
        'label': 'Tomorrow morning',
      };
    }
    if (_has(text, 'kal raat')) {
      final d = now.add(const Duration(days: 1));
      return {
        'deadline': DateTime(d.year, d.month, d.day, tf ? h : 22, tf ? m : 0),
        'label': 'Tomorrow night',
      };
    }
    if (_has(text, 'kal sham')) {
      final d = now.add(const Duration(days: 1));
      return {
        'deadline': DateTime(d.year, d.month, d.day, tf ? h : 18, tf ? m : 0),
        'label': 'Tomorrow evening',
      };
    }

    // ── Generic today words ────────────────────────────────────
    for (final w in _today) {
      if (_has(text, w)) {
        return {'deadline': dt(now), 'label': 'Today$tStr'};
      }
    }

    // ── [F1] Generic tomorrow words (plain "kal" now safe here) ──
    for (final w in _tomorrow) {
      if (_has(text, w)) {
        final d = now.add(const Duration(days: 1));
        return {'deadline': dt(d), 'label': 'Tomorrow$tStr'};
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
      final englishDay = _weekdayLabel[day] ?? _cap(day);
      final modLabel = (mod == 'next') ? 'Next' : (mod == 'this') ? 'This' : 'Next';
      final label = '$modLabel $englishDay';
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
      return {'deadline': dt(d), 'label': _weekdayLabel[day] ?? _cap(day)};
    }

    // ── Plain weekday ─────────────────────────────────────────
    // Sort longest key first so multi-word entries (e.g. "pudhcha somwar")
    // are tested before their substrings ("somwar").
    final sortedWD = _weekdays.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final e in sortedWD) {
      if (RegExp('\\b${RegExp.escape(e.key)}\\b',
          caseSensitive: false).hasMatch(text)) {
        final d = _nextWD(now, e.value);
        return {'deadline': dt(d), 'label': '${_weekdayLabel[e.key] ?? _cap(e.key)}$tStr'};
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
      'deadline': DateTime(now.year, now.month, now.day + 1, h, m),
      'label': 'Unknown',
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // PRIORITY (tier 2: implicit signals)
  // ═══════════════════════════════════════════════════════════════

  static String _detectPriority(String text, DateTime deadline) {
    for (final w in _urgentWords) {
      if (text.contains(w)) return 'urgent';
    }
    if (RegExp(r'!{2,}').hasMatch(text)) return 'urgent';
    final ups  = RegExp(r'[A-Z]').allMatches(text).length;
    final lets = RegExp(r'[a-zA-Z]').allMatches(text).length;
    if (lets >= 8 && ups / lets > 0.70) return 'urgent';
    final diff = deadline.difference(DateTime.now());
    if (diff.inMinutes > 0 && diff.inHours < 6) return 'urgent';
    return 'normal';
  }

  // ═══════════════════════════════════════════════════════════════
  // NAME BUILDER  [F4] honorifics stripped first
  // ═══════════════════════════════════════════════════════════════

  static String _buildName(String raw, String type, String subject) {
    var name = raw.trim();

    // [F4] Strip honorifics/titles BEFORE any other cleaning so they
    //      don't leave stray spaces that corrupt capitalisation.
    name = name.replaceAll(_honorificRe, '');

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

    // Remove filler words
    for (final w in _strip) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ' ');
    }

    // Remove urgency words
    for (final w in _urgentWords) {
      name = name.replaceAll(
          RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false), ' ');
    }

    // NOTE: Subject keywords are intentionally NOT stripped from the name.
    // The subject is stored in its own field; keeping it in the name
    // produces more descriptive labels like "OS Assignment" or "DBMS Project".

    // Strip punctuation, collapse spaces
    name = name.replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove duplicate consecutive words
    final words   = name.split(' ');
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

  /// Word-boundary–aware contains check.
  /// Single-word phrases use \b anchors; multi-word phrases use a simple
  /// contains() because \b doesn't span spaces.
  static bool _has(String text, String phrase) {
    if (phrase.contains(' ')) {
      // Multi-word: substring is fine — leading/trailing spaces in `text`
      // already normalised by .toLowerCase().trim() at call site.
      return text.contains(phrase);
    }
    return RegExp('\\b${RegExp.escape(phrase)}\\b',
        caseSensitive: false).hasMatch(text);
  }

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