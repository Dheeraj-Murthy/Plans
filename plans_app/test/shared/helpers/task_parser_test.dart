import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/features/projects/models/project.dart';
import 'package:plans_app/features/tasks/models/task.dart';
import 'package:plans_app/shared/helpers/task_parser.dart';

void main() {
  final projects = [
    Project(id: 'default', name: 'Inbox', colorIndex: 0),
    Project(id: 'work', name: 'Work', colorIndex: 1),
    Project(id: 'personal', name: 'Personal', colorIndex: 2),
  ];

  // Fixed "now" — 2026-05-19 14:30:00 (Tuesday 2:30pm)
  final now = DateTime(2026, 5, 19, 14, 30, 0);

  group('Priority', () {
    test('p1 → high', () {
      final r = TaskParser.parse('p1 fix bug', projects, now: now);
      expect(r.priority, TaskPriority.high);
      expect(r.title, 'fix bug');
    });

    test('p2 → medium', () {
      final r = TaskParser.parse('p2 update docs', projects, now: now);
      expect(r.priority, TaskPriority.medium);
      expect(r.title, 'update docs');
    });

    test('p3 → low', () {
      final r = TaskParser.parse('p3 clean up', projects, now: now);
      expect(r.priority, TaskPriority.low);
      expect(r.title, 'clean up');
    });

    test('p4 → none', () {
      final r = TaskParser.parse('p4 whatever', projects, now: now);
      expect(r.priority, TaskPriority.none);
      expect(r.title, 'whatever');
    });

    test('!high → high', () {
      final r = TaskParser.parse('!high urgent', projects, now: now);
      expect(r.priority, TaskPriority.high);
      expect(r.title, 'urgent');
    });

    test('!medium → medium', () {
      final r = TaskParser.parse('!medium task', projects, now: now);
      expect(r.priority, TaskPriority.medium);
    });

    test('!low → low', () {
      final r = TaskParser.parse('!low chill', projects, now: now);
      expect(r.priority, TaskPriority.low);
    });

    test('!none → none', () {
      final r = TaskParser.parse('!none trivial', projects, now: now);
      expect(r.priority, TaskPriority.none);
    });

    test('priority can be anywhere in text', () {
      final r = TaskParser.parse('fix bug p1', projects, now: now);
      expect(r.priority, TaskPriority.high);
      expect(r.title, 'fix bug');
    });

    test('no priority when not present', () {
      final r = TaskParser.parse('just a task', projects, now: now);
      expect(r.priority, isNull);
    });
  });

  group('Project', () {
    test('@Work matches project name case-insensitive', () {
      final r = TaskParser.parse('meeting @Work', projects, now: now);
      expect(r.projectId, 'work');
      expect(r.title, 'meeting');
    });

    test('@personal matches', () {
      final r = TaskParser.parse('gym @personal', projects, now: now);
      expect(r.projectId, 'personal');
    });

    test('unmatched @tag ignored', () {
      final r = TaskParser.parse('note @random', projects, now: now);
      expect(r.projectId, isNull);
      expect(r.title, 'note @random');
    });

    test('@ at end of word not extracted', () {
      final r = TaskParser.parse('email @ work', projects, now: now);
      // "@ work" is two tokens, not @word
      expect(r.projectId, isNull);
    });

    test('mid-word @ inside an email-like token is not a project tag', () {
      final r = TaskParser.parse('email john@work about the deploy', projects, now: now);
      expect(r.projectId, isNull);
      expect(r.title, 'email john@work about the deploy');
    });
  });

  group('Time — explicit am/pm', () {
    test('10am in the future → today 10:00 (now is 2:30)', () {
      final morning = DateTime(2026, 5, 19, 9, 0);
      final r = TaskParser.parse('at 10am', projects, now: morning);
      expect(r.dueDate!.hour, 10);
      expect(r.dueDate!.day, now.day);
    });

    test('2pm in the past (now is 2:30pm) → tomorrow 14:00', () {
      final r = TaskParser.parse('at 2pm', projects, now: now);
      expect(r.hasDueDate, true);
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, 14);
    });

    test('9am → today 09:00 (already past at 14:30 → tomorrow)', () {
      final r = TaskParser.parse('at 9am', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, 9);
    });

    test('12am → midnight', () {
      final r = TaskParser.parse('midnight at 12am', projects, now: now);
      expect(r.dueDate!.hour, 0);
    });

    test('12pm → noon', () {
      final r = TaskParser.parse('lunch at 12pm', projects, now: now);
      expect(r.dueDate!.hour, 12);
    });
  });

  group('Time — ambiguous (no am/pm, next occurrence)', () {
    test('7 at 2:30pm → 7pm today', () {
      final r = TaskParser.parse('dinner at 7', projects, now: now);
      expect(r.dueDate!.hour, 19);
      expect(r.dueDate!.day, now.day);
    });

    test('3 at 2:30pm → 3pm tomorrow... no, 3pm today', () {
      // am=3am(past), pm=3pm(future) → 3pm today
      final r = TaskParser.parse('meet at 3', projects, now: now);
      expect(r.dueDate!.hour, 15);
      expect(r.dueDate!.day, now.day);
    });

    test('11 at 10am → 11am today', () {
      final morning = DateTime(2026, 5, 19, 10, 0);
      final r = TaskParser.parse('at 11', projects, now: morning);
      expect(r.dueDate!.hour, 11);
      expect(r.dueDate!.day, 19);
    });

    test('7 at 10pm → 7am tomorrow', () {
      final late = DateTime(2026, 5, 19, 22, 0);
      final r = TaskParser.parse('at 7', projects, now: late);
      expect(r.dueDate!.day, 20);
      expect(r.dueDate!.hour, 7);
    });

    test('12 at 10am → noon today', () {
      final morning = DateTime(2026, 5, 19, 10, 0);
      final r = TaskParser.parse('at 12', projects, now: morning);
      expect(r.dueDate!.hour, 12);
      expect(r.dueDate!.day, 19);
    });

    test('12 at 1pm → noon tomorrow', () {
      final afternoon = DateTime(2026, 5, 19, 13, 0);
      final r = TaskParser.parse('at 12', projects, now: afternoon);
      expect(r.dueDate!.day, 20);
      expect(r.dueDate!.hour, 12);
    });

    test('literal 24h hour (20) already past → tomorrow 20:00, not 08:00', () {
      final late = DateTime(2026, 5, 19, 21, 0);
      final r = TaskParser.parse('at 20', projects, now: late);
      expect(r.dueDate!.day, 20);
      expect(r.dueDate!.hour, 20);
    });

    test('literal 24h hour (20) still ahead → today 20:00', () {
      final r = TaskParser.parse('at 20', projects, now: now); // now is 14:30
      expect(r.dueDate!.day, now.day);
      expect(r.dueDate!.hour, 20);
    });
  });

  group('Date keywords', () {
    test('today → same time today', () {
      final r = TaskParser.parse('buy milk today', projects, now: now);
      expect(r.hasDueDate, true);
      expect(r.dueDate!.day, now.day);
      expect(r.dueDate!.hour, now.hour);
    });

    test('tomorrow → same time tomorrow', () {
      final r = TaskParser.parse('meeting tomorrow', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, now.hour);
    });

    test('tom → same time tomorrow', () {
      final r = TaskParser.parse('call tom', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('tmr → same time tomorrow', () {
      final r = TaskParser.parse('call tmr', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('in 3 days', () {
      final r = TaskParser.parse('done in 3 days', projects, now: now);
      expect(r.dueDate!.day, now.day + 3);
      expect(r.dueDate!.hour, now.hour); // same time of day
    });

    test('in 2 weeks', () {
      // May 19 + 14 days = June 2
      final r = TaskParser.parse('review in 2 weeks', projects, now: now);
      expect(r.dueDate!.month, 6);
      expect(r.dueDate!.day, 2);
      expect(r.dueDate!.hour, now.hour);
    });

    test('next monday', () {
      // now is Tuesday 2026-05-19, next Monday is 2026-05-25
      final r = TaskParser.parse('ship next monday', projects, now: now);
      expect(r.dueDate!.day, 25);
      expect(r.dueDate!.month, 5);
    });

    test('friday (this week)', () {
      // now is Tuesday, next friday is May 22
      final r = TaskParser.parse('party friday', projects, now: now);
      expect(r.dueDate!.day, 22);
      expect(r.dueDate!.month, 5);
    });

    test('monday (next week since today is Tuesday)', () {
      // Tuesday → next Monday = +6 days = May 25
      final r = TaskParser.parse('plan monday', projects, now: now);
      expect(r.dueDate!.day, 25);
    });
  });

  group('Date + Time combined', () {
    test('tomorrow at 7 → tomorrow 7am (default AM for non-today)', () {
      final r = TaskParser.parse('meet tomorrow at 7', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, 7);
    });

    test('tomorrow at 7pm → tomorrow 19:00', () {
      final r = TaskParser.parse('meet tomorrow at 7pm', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, 19);
    });

    test('today at 7 → next occurrence (7pm today)', () {
      final r = TaskParser.parse('eat today at 7', projects, now: now);
      expect(r.dueDate!.day, now.day);
      expect(r.dueDate!.hour, 19);
    });

    test('friday at 3pm → 15:00 on friday', () {
      final r = TaskParser.parse('meet friday at 3pm', projects, now: now);
      expect(r.dueDate!.day, 22);
      expect(r.dueDate!.hour, 15);
    });

    test('next monday at 9:30am → 09:30 on next monday', () {
      final r = TaskParser.parse('standup next monday at 9:30am', projects, now: now);
      expect(r.dueDate!.day, 25);
      expect(r.dueDate!.hour, 9);
      expect(r.dueDate!.minute, 30);
    });
  });

  group('Full integration', () {
    test('p1 fix login @work at 7 tomorrow', () {
      final r = TaskParser.parse(
        'p1 fix login @work at 7 tomorrow',
        projects,
        now: now,
      );
      expect(r.title, 'fix login');
      expect(r.priority, TaskPriority.high);
      expect(r.projectId, 'work');
      expect(r.dueDate!.day, now.day + 1);
      expect(r.dueDate!.hour, 7);
    });

    test('!high buy milk @personal tomorrow', () {
      final r = TaskParser.parse(
        '!high buy milk @personal tomorrow',
        projects,
        now: now,
      );
      expect(r.title, 'buy milk');
      expect(r.priority, TaskPriority.high);
      expect(r.projectId, 'personal');
      expect(r.dueDate!.day, now.day + 1);
    });

    test('gym at 6pm', () {
      final r = TaskParser.parse('gym at 6pm', projects, now: now);
      expect(r.title, 'gym');
      expect(r.dueDate!.hour, 18);
      expect(r.dueDate!.minute, 0);
    });
  });

  group('Short day names', () {
    test('mon → next monday', () {
      // Tue May 19 → next Mon May 25
      final r = TaskParser.parse('meeting mon', projects, now: now);
      expect(r.dueDate!.day, 25);
      expect(r.title, 'meeting');
    });

    test('tue → this tuesday (today since now is Tuesday)', () {
      final r = TaskParser.parse('call tue', projects, now: now);
      expect(r.dueDate!.day, 19);
    });

    test('tues → tuesday', () {
      final r = TaskParser.parse('call tues', projects, now: now);
      expect(r.dueDate!.day, 19);
    });

    test('wed → this wednesday', () {
      // Tue May 19 → Wed May 20
      final r = TaskParser.parse('shop wed', projects, now: now);
      expect(r.dueDate!.day, 20);
    });

    test('thu → this thursday', () {
      // Tue May 19 → Thu May 21
      final r = TaskParser.parse('plan thu', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('thur → thursday', () {
      final r = TaskParser.parse('plan thur', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('thurs → thursday', () {
      final r = TaskParser.parse('plan thurs', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('fri → this friday', () {
      // Tue May 19 → Fri May 22
      final r = TaskParser.parse('party fri', projects, now: now);
      expect(r.dueDate!.day, 22);
    });

    test('sat → this saturday', () {
      // Tue May 19 → Sat May 23
      final r = TaskParser.parse('rest sat', projects, now: now);
      expect(r.dueDate!.day, 23);
    });

    test('sun → this sunday', () {
      // Tue May 19 → Sun May 24
      final r = TaskParser.parse('brunch sun', projects, now: now);
      expect(r.dueDate!.day, 24);
    });
  });

  group('this <day>', () {
    test('this wed → this wednesday', () {
      // Tue May 19 → Wed May 20
      final r = TaskParser.parse('meet this wed', projects, now: now);
      expect(r.dueDate!.day, 20);
    });

    test('this thu → this thursday', () {
      // Tue May 19 → Thu May 21
      final r = TaskParser.parse('plan this thu', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('this mon → next monday', () {
      // Tue May 19 → next Mon May 25
      final r = TaskParser.parse('ship this mon', projects, now: now);
      expect(r.dueDate!.day, 25);
    });

    test('this with full name', () {
      final r = TaskParser.parse('test this friday', projects, now: now);
      expect(r.dueDate!.day, 22);
    });
  });

  group('Extra keyword aliases', () {
    test('tod → today', () {
      final r = TaskParser.parse('buy milk tod', projects, now: now);
      expect(r.hasDueDate, true);
      expect(r.dueDate!.day, now.day);
      expect(r.dueDate!.hour, now.hour);
    });

    test('tmw → tomorrow', () {
      final r = TaskParser.parse('call tmw', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('2moro → tomorrow', () {
      final r = TaskParser.parse('party 2moro', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('2morrow → tomorrow', () {
      final r = TaskParser.parse('meet 2morrow', projects, now: now);
      expect(r.dueDate!.day, now.day + 1);
    });
  });

  group('Numeric date DD/MM', () {
    test('21/05 → 21st May', () {
      final r = TaskParser.parse('meet 21/05', projects, now: now);
      expect(r.dueDate!.day, 21);
      expect(r.dueDate!.month, 5);
      expect(r.dueDate!.year, 2026);
    });

    test('21/05 with time → 21st May at given time', () {
      final r = TaskParser.parse('meet 21/05 at 3pm', projects, now: now);
      expect(r.dueDate!.day, 21);
      expect(r.dueDate!.month, 5);
      expect(r.dueDate!.hour, 15);
    });

    test('1/6 → 1st June (in future)', () {
      final r = TaskParser.parse('event 1/6', projects, now: now);
      expect(r.dueDate!.day, 1);
      expect(r.dueDate!.month, 6);
      expect(r.dueDate!.year, 2026);
    });

    test('1/1 → 1st January (in past, advances to next year)', () {
      final r = TaskParser.parse('party 1/1', projects, now: now);
      expect(r.dueDate!.day, 1);
      expect(r.dueDate!.month, 1);
      expect(r.dueDate!.year, 2027);
    });

    test('21/05/2026 with explicit year', () {
      final r = TaskParser.parse('launch 21/05/2026', projects, now: now);
      expect(r.dueDate!.day, 21);
      expect(r.dueDate!.month, 5);
      expect(r.dueDate!.year, 2026);
    });

    test('21/05/26 with 2-digit year', () {
      final r = TaskParser.parse('launch 21/05/26', projects, now: now);
      expect(r.dueDate!.year, 2026);
    });

    test('invalid month ignored', () {
      final r = TaskParser.parse('version 13/13', projects, now: now);
      expect(r.hasDueDate, false);
      expect(r.title, 'version 13/13');
    });

    test('invalid day ignored', () {
      final r = TaskParser.parse('day 32/05', projects, now: now);
      expect(r.hasDueDate, false);
    });
  });

  group('Text date (month DD / DD month)', () {
    test('may 21 → 21st May', () {
      final r = TaskParser.parse('meet may 21', projects, now: now);
      expect(r.dueDate!.day, 21);
      expect(r.dueDate!.month, 5);
    });

    test('21 may → 21st May', () {
      final r = TaskParser.parse('meet 21 may', projects, now: now);
      expect(r.dueDate!.day, 21);
      expect(r.dueDate!.month, 5);
    });

    test('may 21st with ordinal suffix', () {
      final r = TaskParser.parse('party may 21st', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('21st may with ordinal suffix reversed', () {
      final r = TaskParser.parse('party 21st may', projects, now: now);
      expect(r.dueDate!.day, 21);
    });

    test('jun 1 → 1st June', () {
      final r = TaskParser.parse('start jun 1', projects, now: now);
      expect(r.dueDate!.day, 1);
      expect(r.dueDate!.month, 6);
    });

    test('1 jan → 1st January (past → next year)', () {
      final r = TaskParser.parse('resolution 1 jan', projects, now: now);
      expect(r.dueDate!.day, 1);
      expect(r.dueDate!.month, 1);
      expect(r.dueDate!.year, 2027);
    });

    test('august 15', () {
      final r = TaskParser.parse('holiday august 15', projects, now: now);
      expect(r.dueDate!.day, 15);
      expect(r.dueDate!.month, 8);
    });
  });

  group('Default reminder', () {
    test('hasDueDate sets defaultReminderMinutes = 0', () {
      final r = TaskParser.parse('task tomorrow', projects, now: now);
      expect(r.defaultReminderMinutes, 0);
    });

    test('no dueDate leaves defaultReminderMinutes null', () {
      final r = TaskParser.parse('just a task', projects, now: now);
      expect(r.defaultReminderMinutes, isNull);
    });
  });

  group('Relative time — minutes/hours', () {
    group('in N minutes', () {
      test('in 5 min → now + 5 min', () {
        final r = TaskParser.parse('break in 5 min', projects, now: now);
        expect(r.dueDate!.minute, 35);
        expect(r.dueDate!.hour, 14);
        expect(r.title, 'break');
      });

      test('in 10 mins → now + 10 min', () {
        final r = TaskParser.parse('break in 10 mins', projects, now: now);
        expect(r.dueDate!.minute, 40);
      });

      test('in 1 minute → now + 1 min', () {
        final r = TaskParser.parse('do in 1 minute', projects, now: now);
        expect(r.dueDate!.minute, 31);
      });

      test('in 30 minutes → now + 30 min', () {
        final r = TaskParser.parse('wait in 30 minutes', projects, now: now);
        expect(r.dueDate!.minute, 0);
        expect(r.dueDate!.hour, 15);
      });
    });

    group('in N hours', () {
      test('in 2 hour → now + 2 hours', () {
        final r = TaskParser.parse('meeting in 2 hour', projects, now: now);
        expect(r.dueDate!.hour, 16);
        expect(r.dueDate!.minute, 30);
      });

      test('in 3 hours → now + 3 hours', () {
        final r = TaskParser.parse('done in 3 hours', projects, now: now);
        expect(r.dueDate!.hour, 17);
      });

      test('in 1 hr → now + 1 hour', () {
        final r = TaskParser.parse('call in 1 hr', projects, now: now);
        expect(r.dueDate!.hour, 15);
      });

      test('in 5 hrs → now + 5 hours', () {
        final r = TaskParser.parse('late in 5 hrs', projects, now: now);
        expect(r.dueDate!.hour, 19);
      });
    });

    group('in a / in an', () {
      test('in a minute → now + 1 min', () {
        final r = TaskParser.parse('soon in a minute', projects, now: now);
        expect(r.dueDate!.minute, 31);
      });

      test('in an hour → now + 1 hour', () {
        final r = TaskParser.parse('later in an hour', projects, now: now);
        expect(r.dueDate!.hour, 15);
        expect(r.dueDate!.minute, 30);
      });

      test('in a min → now + 1 min', () {
        final r = TaskParser.parse('brb in a min', projects, now: now);
        expect(r.dueDate!.minute, 31);
      });

      test('in an hr → now + 1 hour', () {
        final r = TaskParser.parse('soon in an hr', projects, now: now);
        expect(r.dueDate!.hour, 15);
      });
    });

    group('no space between amount and unit', () {
      test('in 2min → now + 2 min', () {
        final r = TaskParser.parse('break in 2min', projects, now: now);
        expect(r.dueDate!.minute, 32);
      });

      test('in 3hours → now + 3 hours', () {
        final r = TaskParser.parse('wait in 3hours', projects, now: now);
        expect(r.dueDate!.hour, 17);
      });
    });
  });

  group('Decimal time separator', () {
    test('at 3.27 → 3:27 resolved to 15:27', () {
      final r = TaskParser.parse('meet at 3.27', projects, now: now);
      expect(r.dueDate!.hour, 15);
      expect(r.dueDate!.minute, 27);
    });

    test('at 3.27pm → 15:27', () {
      final r = TaskParser.parse('meet at 3.27pm', projects, now: now);
      expect(r.dueDate!.hour, 15);
      expect(r.dueDate!.minute, 27);
    });

    test('at 9.05am → 09:05', () {
      final early = DateTime(2026, 5, 19, 10, 0);
      final r = TaskParser.parse('early at 9.05am', projects, now: early);
      expect(r.dueDate!.hour, 9);
      expect(r.dueDate!.minute, 5);
    });

    test('bare 3.27 without at → not a time', () {
      final r = TaskParser.parse('version 3.27', projects, now: now);
      expect(r.hasDueDate, false);
      expect(r.title, 'version 3.27');
    });

    test('at 5.00 → 5:00 resolved to 17:00', () {
      final r = TaskParser.parse('meet at 5.00', projects, now: now);
      expect(r.dueDate!.hour, 17);
      expect(r.dueDate!.minute, 0);
    });
  });

  group('Recurrence', () {
    test('every day → daily|1 + dueDate today', () {
      final r = TaskParser.parse('buy milk every day', projects, now: now);
      expect(r.recurrence, 'daily|1');
      expect(r.dueDate, isNotNull);
      expect(r.dueDate!.year, now.year);
      expect(r.dueDate!.month, now.month);
      expect(r.dueDate!.day, now.day);
      expect(r.title, 'buy milk');
    });

    test('every week → weekly|1', () {
      final r = TaskParser.parse('standup every week', projects, now: now);
      expect(r.recurrence, 'weekly|1');
      expect(r.title, 'standup');
    });

    test('every month → monthly|1', () {
      final r = TaskParser.parse('review every month', projects, now: now);
      expect(r.recurrence, 'monthly|1');
    });

    test('every year → yearly|1', () {
      final r = TaskParser.parse('audit every year', projects, now: now);
      expect(r.recurrence, 'yearly|1');
    });

    test('every 2 days → daily|2', () {
      final r = TaskParser.parse('water plants every 2 days', projects, now: now);
      expect(r.recurrence, 'daily|2');
    });

    test('every 3 weeks → weekly|3', () {
      final r = TaskParser.parse('report every 3 weeks', projects, now: now);
      expect(r.recurrence, 'weekly|3');
    });

    test('every day with explicit date → date wins', () {
      final r = TaskParser.parse('every day tomorrow', projects, now: now);
      expect(r.recurrence, 'daily|1');
      expect(r.dueDate, isNotNull);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('bare every without day/week etc → not parsed', () {
      final r = TaskParser.parse('every single thing', projects, now: now);
      expect(r.recurrence, isNull);
      expect(r.title, 'every single thing');
    });

    test('every day with p1 priority', () {
      final r = TaskParser.parse('p1 every day', projects, now: now);
      expect(r.priority, TaskPriority.high);
      expect(r.recurrence, 'daily|1');
    });

    test('every day does not set hasDueDate when no explicit date', () {
      final r = TaskParser.parse('brush teeth every day', projects, now: now);
      expect(r.recurrence, 'daily|1');
      expect(r.dueDate, isNotNull);
      expect(r.hasDueDate, true);
    });
  });

  group('Weekday recurrence', () {
    test('every weekday → weekly|1|weekdays', () {
      final r = TaskParser.parse('standup every weekday', projects, now: now);
      expect(r.recurrence, 'weekly|1|weekdays');
      expect(r.dueDate, isNotNull);
      expect(r.title, 'standup');
    });

    test('every weekdays (plural) → weekly|1|weekdays', () {
      final r = TaskParser.parse('standup every weekdays', projects, now: now);
      expect(r.recurrence, 'weekly|1|weekdays');
    });

    test('every mon/wed/fri → weekly|1|mon,wed,fri', () {
      final r = TaskParser.parse('meeting every mon/wed/fri', projects, now: now);
      expect(r.recurrence, 'weekly|1|mon,wed,fri');
      expect(r.title, 'meeting');
    });

    test('every mon/wed (two days)', () {
      final r = TaskParser.parse('call every mon/wed', projects, now: now);
      expect(r.recurrence, 'weekly|1|mon,wed');
    });

    test('every monday (full name) → weekly|1|mon', () {
      final r = TaskParser.parse('review every monday', projects, now: now);
      expect(r.recurrence, 'weekly|1|mon');
      expect(r.title, 'review');
    });

    test('every wed (short name) → weekly|1|wed', () {
      final r = TaskParser.parse('deploy every wed', projects, now: now);
      expect(r.recurrence, 'weekly|1|wed');
    });

    test('every tues → tue (canonical short form)', () {
      final r = TaskParser.parse('sync every tues', projects, now: now);
      expect(r.recurrence, 'weekly|1|tue');
    });

    test('every thurs → thu (canonical short form)', () {
      final r = TaskParser.parse('sync every thurs', projects, now: now);
      expect(r.recurrence, 'weekly|1|thu');
    });

    test('weekday without every → not parsed', () {
      final r = TaskParser.parse('monday meeting', projects, now: now);
      expect(r.recurrence, isNull);
      // "monday" gets parsed as a keyword date, so title is just "meeting"
    });

    test('every weekday with explicit date → date wins', () {
      final r = TaskParser.parse('standup every weekday tomorrow', projects, now: now);
      expect(r.recurrence, 'weekly|1|weekdays');
      expect(r.dueDate, isNotNull);
      expect(r.dueDate!.day, now.day + 1);
    });

    test('every weekend → not a valid pattern, not parsed', () {
      // "every weekend" is not supported, should fall through to interval parser
      // "weekend" doesn't match day names, so nothing should match
      final r = TaskParser.parse('relax every weekend', projects, now: now);
      expect(r.recurrence, isNull);
      expect(r.title, 'relax every weekend');
    });

    test('every weekday with p1 priority', () {
      final r = TaskParser.parse('p1 standup every weekday', projects, now: now);
      expect(r.priority, TaskPriority.high);
      expect(r.recurrence, 'weekly|1|weekdays');
    });

    test('every weekday does not match everyday as one word', () {
      final r = TaskParser.parse('my everyday routine', projects, now: now);
      expect(r.recurrence, isNull);
    });
  });

  group('Edge cases', () {
    test('empty input returns title as-is', () {
      final r = TaskParser.parse('', projects, now: now);
      expect(r.title, '');
      expect(r.priority, isNull);
      expect(r.hasDueDate, false);
    });

    test('whitespace input', () {
      final r = TaskParser.parse('   ', projects, now: now);
      expect(r.title, '   ');
    });

    test('no special tokens returns input as title', () {
      final r = TaskParser.parse('write some code', projects, now: now);
      expect(r.title, 'write some code');
      expect(r.priority, isNull);
      expect(r.projectId, isNull);
      expect(r.hasDueDate, false);
    });

    test('@ symbol not followed by word ignored', () {
      final r = TaskParser.parse('buy milk @ 2pm', projects, now: now);
      expect(r.projectId, isNull);
      expect(r.dueDate, isNotNull); // still parses time
    });

    test('single digit 1-5 not treated as time', () {
      final r = TaskParser.parse('step 1 done', projects, now: now);
      expect(r.hasDueDate, false);
      expect(r.title, 'step 1 done');
    });
  });
}
