// lib/screens/calendar_screen.dart
// Lightweight month calendar — no external package, pure Flutter.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import '../widgets/task_card.dart';

class CalendarScreen extends StatefulWidget {
  final List<Task> tasks;
  final Function(Task) onToggle;
  final Function(Task) onDelete;
  final Function(Task) onTap;

  const CalendarScreen({
    super.key,
    required this.tasks,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay  = DateTime(now.year, now.month, now.day);
  }

  // Build map: normalised day → tasks due that day
  Map<DateTime, List<Task>> get _tasksByDay {
    final map = <DateTime, List<Task>>{};
    for (final t in widget.tasks) {
      final key = DateTime(t.deadline.year, t.deadline.month, t.deadline.day);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  List<Task> _tasksForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _tasksByDay[key] ?? [];
  }

  void _prevMonth() => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));

  void _nextMonth() => setState(() =>
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isSelected(DateTime d) =>
      _selectedDay != null &&
      d.year == _selectedDay!.year &&
      d.month == _selectedDay!.month &&
      d.day == _selectedDay!.day;

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final topPad  = MediaQuery.of(context).padding.top;
    final byDay   = _tasksByDay;
    final selected = _selectedDay;
    final selectedTasks = selected != null ? (_tasksForDay(selected)) : <Task>[];

    // Calendar grid data
    final firstOfMonth = _focusedMonth;
    final daysInMonth  = DateUtils.getDaysInMonth(firstOfMonth.year, firstOfMonth.month);
    // weekday: Mon=1 … Sun=7 → offset so Mon is col 0
    final startWeekday = firstOfMonth.weekday; // 1=Mon
    final gridCells    = startWeekday - 1 + daysInMonth; // leading blanks + day cells
    final rows         = (gridCells / 7).ceil();

    return Scaffold(
      backgroundColor: AppTheme.surface(isDark),
      body: CustomScrollView(slivers: [

        // ── Header ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLow(isDark),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.arrow_back_rounded,
                      color: AppTheme.primary, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CALENDAR',
                      style: GoogleFonts.manrope(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          letterSpacing: 0.6, color: AppTheme.subtext(isDark))),
                  Text(DateFormat('MMMM yyyy').format(_focusedMonth),
                      style: GoogleFonts.manrope(
                          fontSize: 22, fontWeight: FontWeight.w800,
                          letterSpacing: -0.5, color: AppTheme.text(isDark))),
                ]),
              ),
              // Month navigation
              _NavBtn(icon: Icons.chevron_left_rounded,
                  isDark: isDark, onTap: _prevMonth),
              const SizedBox(width: 8),
              _NavBtn(icon: Icons.chevron_right_rounded,
                  isDark: isDark, onTap: _nextMonth),
            ]),
          ),
        ),

        // ── Day-of-week labels ─────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: LayoutBuilder(builder: (_, constraints) {
              final cellW = constraints.maxWidth / 7;
              return Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) =>
                  SizedBox(
                    width: cellW,
                    child: Center(
                      child: Text(d,
                          style: GoogleFonts.manrope(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: AppTheme.subtext(isDark))),
                    ),
                  ),
                ).toList(),
              );
            }),
          ),
        ),

        // ── Month grid ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (_, constraints) {
              final cellW  = constraints.maxWidth / 7;
              final cellH  = (cellW * 1.2).clamp(36.0, 52.0);
              return Column(
              children: List.generate(rows, (row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: List.generate(7, (col) {
                      final cellIndex = row * 7 + col;
                      final dayNumber = cellIndex - (startWeekday - 1) + 1;
                      if (dayNumber < 1 || dayNumber > daysInMonth) {
                        return SizedBox(width: cellW, height: cellH);
                      }
                      final day = DateTime(
                          firstOfMonth.year, firstOfMonth.month, dayNumber);
                      final hasTasks = byDay.containsKey(day);
                      final pendingCount = byDay[day]
                              ?.where((t) => !t.isDone).length ?? 0;
                      final doneCount = byDay[day]
                              ?.where((t) => t.isDone).length ?? 0;
                      final isSel   = _isSelected(day);
                      final isToday = _isToday(day);

                      return GestureDetector(
                        onTap: () => setState(() => _selectedDay = day),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: cellW, height: cellH,
                          decoration: BoxDecoration(
                            color: isSel
                                ? AppTheme.primary
                                : isToday
                                    ? AppTheme.primary.withValues(alpha: 0.12)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: isToday && !isSel
                                ? Border.all(
                                    color: AppTheme.primary.withValues(alpha: 0.4),
                                    width: 1.5)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('$dayNumber',
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isSel
                                          ? Colors.white
                                          : AppTheme.text(isDark))),
                              if (hasTasks) ...[
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (pendingCount > 0)
                                      Container(
                                        width: 5, height: 5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSel
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : AppTheme.primary,
                                        ),
                                      ),
                                    if (doneCount > 0)
                                      Container(
                                        width: 5, height: 5,
                                        margin: const EdgeInsets.symmetric(horizontal: 1),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isSel
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : AppTheme.calm,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
              );   // end Column
            }),    // end LayoutBuilder
          ),
        ),

        // ── Selected-day task list ─────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  selected != null
                      ? _isToday(selected)
                          ? 'Today'
                          : DateFormat('EEEE, d MMMM').format(selected)
                      : 'Select a day',
                  style: GoogleFonts.manrope(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppTheme.text(isDark)),
                ),
              ),
              if (selectedTasks.isNotEmpty)
                Text('${selectedTasks.length} task${selectedTasks.length == 1 ? "" : "s"}',
                    style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppTheme.subtext(isDark))),
            ]),
          ),
        ),

        if (selectedTasks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Text('No tasks due this day.',
                  style: GoogleFonts.manrope(
                      fontSize: 13, color: AppTheme.subtext(isDark))),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => TaskCard(
                  task: selectedTasks[i],
                  onToggleDone: () => widget.onToggle(selectedTasks[i]),
                  onDelete:     () => widget.onDelete(selectedTasks[i]),
                ),
                childCount: selectedTasks.length,
              ),
            ),
          ),
      ]),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLow(isDark),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: AppTheme.primary),
    ),
  );
}
