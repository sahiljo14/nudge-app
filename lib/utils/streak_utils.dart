// lib/utils/streak_utils.dart
//
// Shared helpers for streak / completion-day computation. Previously this
// logic was duplicated across home_screen.dart (twice) and profile_screen.dart
// with slight algorithmic variations — including an O(365 × n) loop that
// re-scanned all tasks for every day in the year. The Set-based
// implementations here are O(n) for current streak and O(n log n) for best
// streak, while preserving exactly the same outputs.

import '../models/task.dart';

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Calendar day a done task should count toward.
/// Uses real `completedAt` when available; falls back to `deadline` for
/// pre-migration rows that have isDone=true but completedAt=null.
DateTime? completionDay(Task t) {
  if (!t.isDone) return null;
  final dt = t.completedAt ?? t.deadline;
  return DateTime(dt.year, dt.month, dt.day);
}

/// Set of all calendar days that have at least one completed task.
Set<DateTime> doneDaysSet(List<Task> tasks) {
  final s = <DateTime>{};
  for (final t in tasks) {
    final d = completionDay(t);
    if (d != null) s.add(d);
  }
  return s;
}

/// Today (calendar day) at 00:00 local time.
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Current consecutive-day streak ending today.
/// Counts today if any task was completed today, then walks backwards while
/// each previous day also has a completion, up to 365 days.
int currentStreak(List<Task> tasks) {
  final done = doneDaysSet(tasks);
  if (done.isEmpty) return 0;
  final today = _today();
  int streak = 0;
  if (done.contains(today)) streak++;
  for (int i = 1; i < 365; i++) {
    final day = today.subtract(Duration(days: i));
    if (done.contains(day)) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}

/// Longest run of consecutive days with at least one completed task.
int bestStreak(List<Task> tasks) {
  final done = doneDaysSet(tasks);
  if (done.isEmpty) return 0;
  final sorted = done.toList()..sort();
  int best = 1, cur = 1;
  for (int i = 1; i < sorted.length; i++) {
    if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 1;
    }
  }
  return best;
}

/// Map of {calendar day → completion count, clamped to [0,5]} for the most
/// recent [days] days (ending today, inclusive). Days without completions
/// are present with value 0 so callers can render a fixed-size heatmap.
Map<DateTime, int> heatmapByDay(List<Task> tasks, {int days = 28}) {
  final today = _today();
  final map = <DateTime, int>{};
  for (int i = days - 1; i >= 0; i--) {
    map[today.subtract(Duration(days: i))] = 0;
  }
  for (final t in tasks) {
    final day = completionDay(t);
    if (day != null && map.containsKey(day)) {
      map[day] = (map[day]! + 1).clamp(0, 5);
    }
  }
  return map;
}

/// Has at least one task been completed today? [O(n)].
bool hasCompletionToday(List<Task> tasks) {
  final today = _today();
  for (final t in tasks) {
    final d = completionDay(t);
    if (d != null && isSameDay(d, today)) return true;
  }
  return false;
}

/// Count of tasks completed today.
int todayDoneCount(List<Task> tasks) {
  final today = _today();
  int n = 0;
  for (final t in tasks) {
    final d = completionDay(t);
    if (d != null && isSameDay(d, today)) n++;
  }
  return n;
}
