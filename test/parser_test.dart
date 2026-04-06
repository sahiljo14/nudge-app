// test/parser_test.dart
//
// Run with:  flutter test test/parser_test.dart
// All tests should pass with 0 failures.

import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/parser/task_parser.dart';

void main() {
  // Helper — makes test output readable
  void check(
      String input, {
        String? label,       // deadlineLabel contains this
        String? type,        // taskType equals this
        String? subject,     // subject equals this
        String? priority,    // priority equals this
        String? nameContains,// taskName contains this
        int? daysFromNow,    // deadline is roughly N days from now
        int? hour,           // deadline hour
        bool? isMulti,       // isMultiTask
      }) {
    test('"$input"', () {
      final r = TaskParser.parse(input);
      if (label != null) {
        expect(r.deadlineLabel.toLowerCase(),
            contains(label.toLowerCase()),
            reason: 'label mismatch — got: ${r.deadlineLabel}');
      }
      if (type != null) {
        expect(r.taskType, equals(type),
            reason: 'type mismatch — got: ${r.taskType}');
      }
      if (subject != null) {
        expect(r.subject, equals(subject),
            reason: 'subject mismatch — got: ${r.subject}');
      }
      if (priority != null) {
        expect(r.priority, equals(priority),
            reason: 'priority mismatch — got: ${r.priority}');
      }
      if (nameContains != null) {
        expect(r.taskName.toLowerCase(),
            contains(nameContains.toLowerCase()),
            reason: 'name mismatch — got: ${r.taskName}');
      }
      if (daysFromNow != null) {
        final diff = r.deadline.difference(DateTime.now()).inDays;
        expect(diff, closeTo(daysFromNow, 1),
            reason: 'days mismatch — got: $diff days');
      }
      if (hour != null) {
        expect(r.deadline.hour, equals(hour),
            reason: 'hour mismatch — got: ${r.deadline.hour}');
      }
      if (isMulti != null) {
        expect(r.isMultiTask, equals(isMulti),
            reason: 'isMultiTask mismatch');
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  // GROUP 1 — TODAY VARIANTS
  // ══════════════════════════════════════════════════════════════
  group('Today', () {
    check('Submit form today',          label: 'today',   daysFromNow: 0);
    check('aaj submit karna hai',       label: 'today',   daysFromNow: 0);
    check('Submit by EOD',              label: 'eod',     daysFromNow: 0);
    check('Send it by COB',             label: 'eod',     daysFromNow: 0);
    check('End of day submission',      label: 'eod',     daysFromNow: 0);
    check('Submit tonight',             label: 'tonight', daysFromNow: 0);
    check('aaj raat tak bhejo',         label: 'tonight', daysFromNow: 0);
    check('Submit today by 5pm',        label: 'today',   hour: 17, daysFromNow: 0);
    check('aaj 5 baje tak dena hai',    label: 'today',   hour: 17, daysFromNow: 0);
    check('Submit today before 3pm',    label: 'today',   hour: 15, daysFromNow: 0);
    check('Submit form today 17:00',    label: 'today',   hour: 17, daysFromNow: 0);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 2 — TOMORROW VARIANTS
  // ══════════════════════════════════════════════════════════════
  group('Tomorrow', () {
    check('kal assignment submit karna hai', label: 'tomorrow', daysFromNow: 1);
    check('udya practical ahe',              label: 'tomorrow', daysFromNow: 1);
    check('Submit tomorrow by 9am',          label: 'tomorrow', hour: 9,  daysFromNow: 1);
    check('kal subah 10 baje exam hai',      label: 'tomorrow morning', hour: 10, daysFromNow: 1);
    check('kal raat tak submit karo',        label: 'tomorrow', daysFromNow: 1);
    check('tmrw assignment due',             label: 'tomorrow', daysFromNow: 1);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 3 — DAY AFTER TOMORROW
  // ══════════════════════════════════════════════════════════════
  group('Day after tomorrow', () {
    check('parso exam hai',               label: 'day after tomorrow', daysFromNow: 2);
    check('Day after tomorrow 9am test', label: 'day after tomorrow', daysFromNow: 2);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 4 — WEEKDAYS
  // ══════════════════════════════════════════════════════════════
  group('Weekdays', () {
    check('Exam on Monday 9am',           label: 'monday',    hour: 9);
    check('Submit by Friday',             label: 'friday');
    check('shukrawar paryant assignment', label: 'shukrawar');
    check('somwar tak project submit',    label: 'somvar');
    check('this Friday exam',             label: 'this friday');
    check('next Monday submit',           label: 'next monday');
    check('pudhcha somwar viva ahe',      label: 'monday');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 5 — ORDINAL DATES + MONTH NAMES
  // ══════════════════════════════════════════════════════════════
  group('Ordinal dates', () {
    check('Submit by 5th April',    label: '5 april');
    check('Exam on April 10',       label: '10 april');
    check('Assignment due 15 May',  label: '15 may');
    check('Submit by 1st January',  label: '1 january');
    check('5 tarikh tak submit',    label: '5 tarikh');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 6 — RELATIVE DURATIONS
  // ══════════════════════════════════════════════════════════════
  group('Relative durations', () {
    check('Submit in 3 days',            daysFromNow: 3);
    check('within 5 days submit karo',   daysFromNow: 5);
    check('do din mein assignment',      daysFromNow: 2);
    check('3 din mein submit karna hai', daysFromNow: 3);
    check('in 2 weeks submit',           daysFromNow: 14);
    check('do hafte mein project',       daysFromNow: 14);
    check('ek hafte mein exam',          daysFromNow: 7);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 7 — WEEK / MONTH END
  // ══════════════════════════════════════════════════════════════
  group('Week and month end', () {
    check('Submit by end of week',  label: 'end of week');
    check('Weekend submission due', label: 'end of week');
    check('ya aathavdyat submit',   label: 'end of week');
    check('End of month payment',   label: 'end of month');
    check('mahina end tak submit',  label: 'end of month');
    check('Next month project',     label: 'next month');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 8 — TIME PARSING
  // ══════════════════════════════════════════════════════════════
  group('Time parsing', () {
    check('Exam tomorrow at 9am',      hour: 9);
    check('Meeting today at 2:30pm',   hour: 14);
    check('Submit today by 11:59pm',   hour: 23);
    check('Call today at 17:00',       hour: 17);
    check('kal subah 10 baje exam',    hour: 10);
    check('aaj shaam 6 baje meeting',  hour: 18);
    check('raat 10 baje tak submit',   hour: 22);
    check('today before 5',            hour: 17);
    check('Submit by 5:30pm tomorrow', hour: 17);
    check('4:00 PM exam tomorrow',     hour: 16);
    check('today dopahar tak submit',  hour: 12);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 9 — TASK TYPES
  // ══════════════════════════════════════════════════════════════
  group('Task types', () {
    check('OS assignment kal tak',      type: 'assignment');
    check('Maths exam Monday',          type: 'exam');
    check('Submit form today',          type: 'submission');
    check('Meeting tomorrow 10am',      type: 'meeting');
    check('Remind me Friday',           type: 'reminder');
    check('DBMS viva next week',        type: 'exam');
    check('Lab practical tomorrow',     type: 'assignment');
    check('Unit test budhwar',          type: 'exam');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 10 — SUBJECTS
  // ══════════════════════════════════════════════════════════════
  group('Subject detection', () {
    check('OS assignment kal tak',              subject: 'Operating Systems');
    check('DBMS project next week',             subject: 'Database Management');
    check('Maths exam Monday 9am',              subject: 'Mathematics');
    check('CN assignment submit Friday',        subject: 'Computer Networks');
    check('ML project due end of month',        subject: 'Machine Learning');
    check('DSA test next week',                 subject: 'Data Structures');
    check('Web development assignment today',   subject: 'Web Development');
    check('TOC exam this Friday',               subject: 'Theory of Computation');
    check('Java OOP project kal',               subject: 'Java');
    check('Python assignment submit tomorrow',  subject: 'Python');
    check('SE project submission Friday',       subject: 'Software Engineering');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 11 — PRIORITY
  // ══════════════════════════════════════════════════════════════
  group('Priority detection', () {
    check('urgent assignment kal tak',      priority: 'urgent');
    check('SUBMIT ASAP IMPORTANT!!!',       priority: 'urgent');
    check('assignment aaj hi submit karo',  priority: 'urgent');
    check('Submit assignment tomorrow',     priority: 'normal');
    check('EXAM KAL HAI JALDI KARO',        priority: 'urgent'); // ALL CAPS
    check('Project submit karo!!',          priority: 'urgent'); // !!
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 12 — HINGLISH / MARATHI
  // ══════════════════════════════════════════════════════════════
  group('Hinglish and Marathi', () {
    check('kal tak OS assignment submit karna hai urgent',
        label: 'tomorrow', subject: 'Operating Systems', priority: 'urgent');
    check('udya practical ahe jaldi kara',
        label: 'tomorrow', priority: 'urgent');
    check('shukrawar paryant assignment jama karo',
        label: 'shukrawar', type: 'assignment');
    check('somwar tak project submit karna hai',
        label: 'somvar');
    check('aaj 5 baje tak form dena hai',
        label: 'today', hour: 17, type: 'submission');
    check('do din mein assignment karna hai',
        daysFromNow: 2, type: 'assignment');
    check('ek hafte mein maths exam ahe',
        daysFromNow: 7, type: 'exam', subject: 'Mathematics');
    check('pudhcha somwar viva ahe',
        label: 'monday', type: 'exam');
    check('ya aathavdyat submit karayche ahe',
        label: 'end of week');
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 13 — TASK NAME CLEANING
  // ══════════════════════════════════════════════════════════════
  group('Task name cleaning', () {
    check('OS assignment kal tak submit karna hai',
        nameContains: 'OS');           // abbreviation capitalised
    check('DBMS project next week',
        nameContains: 'DBMS');         // abbreviation capitalised
    check('submit submit form today',
        nameContains: 'form');         // duplicate removal
    check('maths maths exam Monday',
        nameContains: 'Maths');        // duplicate + capitalise
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 14 — CONTEXT-AWARE DEFAULTS
  // ══════════════════════════════════════════════════════════════
  group('Context-aware defaults', () {
    check('Maths exam tomorrow',   type: 'exam',    hour: 9);   // exam → 9am
    check('Meeting on Friday',     type: 'meeting', hour: 10);  // meeting → 10am
    check('Assignment due Monday', type: 'assignment', hour: 23); // assignment → 11pm
    check('Submit form tomorrow',  type: 'submission', hour: 23); // submission → 11pm
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 15 — MULTI-TASK DETECTION
  // ══════════════════════════════════════════════════════════════
  group('Multi-task', () {
    check(
      'Maths exam Monday, OS assignment Wednesday, DBMS submission Friday',
      isMulti: true,
    );
    check(
      'Kal maths test ahe aur parso OS assignment submit karna hai',
      isMulti: true,
    );
    // Single task should NOT be flagged as multi
    check('OS assignment kal tak', isMulti: false);
  });

  // ══════════════════════════════════════════════════════════════
  // GROUP 16 — REAL WORLD WHATSAPP-STYLE MESSAGES
  // ══════════════════════════════════════════════════════════════
  group('Real world messages', () {
    check(
      'Dear students, please submit your OS assignment by Friday 11:59pm. Urgent!',
      label: 'friday', hour: 23, subject: 'Operating Systems', priority: 'urgent',
    );
    check(
      'Kal tak DBMS practical submit karna hai, jaldi karo!!',
      label: 'tomorrow', subject: 'Database Management', priority: 'urgent',
    );
    check(
      'Maths unit test on Wednesday 9am. Syllabus: chapter 3 and 4.',
      label: 'wednesday', hour: 9, subject: 'Mathematics', type: 'exam',
    );
    check(
      'CN assignment due 15th April. Submit on Google Classroom.',
      label: '15 april', subject: 'Computer Networks',
    );
    check(
      'ML project demo next Monday at 2pm. Team of 3.',
      label: 'next monday', hour: 14, subject: 'Machine Learning',
    );
    check(
      'Aaj shaam 5 baje tak form bharo, last date hai aaj hi!',
      label: 'today', hour: 17, priority: 'urgent',
    );
    check(
      'SE viva is on this Thursday at 11am. Prepare unit 2.',
      label: 'this thursday', hour: 11,
      subject: 'Software Engineering', type: 'exam',
    );
  });
}
