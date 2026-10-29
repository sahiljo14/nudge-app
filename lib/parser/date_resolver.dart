class DateResolver {
  static DateTime? resolve(String input) {
    final text = input.toLowerCase().trim();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // ── Hinglish / Marathi ──────────────────────────────────────
    if (_match(text, ['aaj', 'aaj hi', 'today'])) {
      return today.add(const Duration(hours: 23, minutes: 59));
    }

    if (_match(text, ['kal', 'kl', 'udhya', 'udya', 'tomorrow'])) {
      return today.add(const Duration(days: 1, hours: 23, minutes: 59));
    }

    if (_match(text, ['parso', 'parson', 'day after tomorrow'])) {
      return today.add(const Duration(days: 2, hours: 23, minutes: 59));
    }

    if (_match(text, ['is hafte', 'this week'])) {
      return _endOfThisWeek(today);
    }

    if (_match(text, [
      'agle hafte', 'agli week', 'next week',
      'pudcha aathavda', 'pudchya aathavdyat'
    ])) {
      return today.add(const Duration(days: 7));
    }

    if (_match(text, ['is mahine', 'this month'])) {
      return DateTime(now.year, now.month + 1, 0, 23, 59);
    }

    // ── "next Monday" / "next Friday" etc ───────────────────────
    final nextWeekday = _resolveNextWeekday(text);
    if (nextWeekday != null) return nextWeekday;

    // ── "in X days" / "X din mein" ──────────────────────────────
    final inDays = _resolveInDays(text);
    if (inDays != null) return inDays;

    // ── DD/MM/YYYY or DD-MM-YYYY ─────────────────────────────────
    final explicit = _resolveExplicitDate(text);
    if (explicit != null) return explicit;

    return null;
  }

  static bool _match(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  static DateTime _endOfThisWeek(DateTime today) {
    final daysUntilSunday = 7 - today.weekday;
    return today.add(Duration(days: daysUntilSunday, hours: 23, minutes: 59));
  }

  static DateTime? _resolveNextWeekday(String text) {
    final weekdays = {
      'monday': 1, 'mon': 1, 'somwar': 1,
      'tuesday': 2, 'tue': 2, 'mangalwar': 2,
      'wednesday': 3, 'wed': 3, 'budhwar': 3,
      'thursday': 4, 'thu': 4, 'thurs': 4, 'guruwar': 4,
      'friday': 5, 'fri': 5, 'shukrawar': 5,
      'saturday': 6, 'sat': 6, 'shaniwar': 6,
      'sunday': 7, 'sun': 7, 'raviwar': 7,
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in weekdays.entries) {
      if (text.contains(entry.key)) {
        int daysUntil = entry.value - today.weekday;
        if (daysUntil <= 0) daysUntil += 7;
        return today.add(
          Duration(days: daysUntil, hours: 23, minutes: 59),
        );
      }
    }
    return null;
  }

  static DateTime? _resolveInDays(String text) {
    // matches: "3 din mein", "in 3 days", "3 days"
    final pattern = RegExp(r'(\d+)\s*(din|days?|d\b)');
    final match = pattern.firstMatch(text);
    if (match != null) {
      final days = int.tryParse(match.group(1) ?? '');
      if (days != null && days > 0 && days <= 365) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day)
            .add(Duration(days: days, hours: 23, minutes: 59));
      }
    }
    return null;
  }

  static DateTime? _resolveExplicitDate(String text) {
    // matches: 25/12/2025 or 25-12-2025
    final pattern = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})');
    final match = pattern.firstMatch(text);
    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final year = int.tryParse(match.group(3) ?? '');
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, 23, 59);
      }
    }
    return null;
  }
}