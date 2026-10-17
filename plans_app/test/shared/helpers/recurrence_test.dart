import 'package:flutter_test/flutter_test.dart';
import 'package:plans_app/shared/helpers/recurrence.dart';

void main() {
  group('Recurrence', () {
    group('toStorage / fromStorage round-trip', () {
      test('daily', () {
        final r = Recurrence(frequency: RecurrenceFrequency.daily);
        expect(r.toStorage(), 'daily|1');
        expect(Recurrence.fromStorage('daily|1').frequency, RecurrenceFrequency.daily);
        expect(Recurrence.fromStorage('daily|1').interval, 1);
      });

      test('daily|2', () {
        final r = Recurrence(frequency: RecurrenceFrequency.daily, interval: 2);
        expect(r.toStorage(), 'daily|2');
        expect(Recurrence.fromStorage('daily|2').interval, 2);
      });

      test('weekdays', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        expect(r.toStorage(), 'weekly|1|weekdays');
        final loaded = Recurrence.fromStorage('weekly|1|weekdays');
        expect(loaded.isWeekdays, true);
        expect(loaded.daysOfWeek, isNull);
      });

      test('mon/wed/fri', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        expect(r.toStorage(), 'weekly|1|mon,wed,fri');
        final loaded = Recurrence.fromStorage('weekly|1|mon,wed,fri');
        expect(loaded.daysOfWeek, [1, 3, 5]);
        expect(loaded.isWeekdays, false);
      });

      test('single day mon', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1],
        );
        expect(r.toStorage(), 'weekly|1|mon');
        final loaded = Recurrence.fromStorage('weekly|1|mon');
        expect(loaded.daysOfWeek, [1]);
      });

      test('backward compat old format daily|1', () {
        final loaded = Recurrence.fromStorage('daily|1');
        expect(loaded.isWeekdays, false);
        expect(loaded.daysOfWeek, isNull);
        expect(loaded.frequency, RecurrenceFrequency.daily);
        expect(loaded.interval, 1);
      });

      test('backward compat weekly|3', () {
        final loaded = Recurrence.fromStorage('weekly|3');
        expect(loaded.isWeekdays, false);
        expect(loaded.daysOfWeek, isNull);
        expect(loaded.frequency, RecurrenceFrequency.weekly);
        expect(loaded.interval, 3);
      });
    });

    group('nextOccurrence', () {
      test('weekdays: Mon completed → Tue', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        final mon = DateTime(2026, 5, 25, 10, 0); // Monday
        final next = r.nextOccurrence(mon)!;
        expect(next.weekday, 2); // Tuesday
        expect(next.day, 26);
        expect(next.hour, 10);
        expect(next.minute, 0);
      });

      test('weekdays: Fri completed → Mon', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        final fri = DateTime(2026, 5, 22, 14, 30); // Friday
        final next = r.nextOccurrence(fri)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 25);
        expect(next.hour, 14);
        expect(next.minute, 30);
      });

      test('weekdays: Sat completed → Mon', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        final sat = DateTime(2026, 5, 23, 9, 0); // Saturday
        final next = r.nextOccurrence(sat)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 25);
      });

      test('weekdays: Sun completed → Mon', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        final sun = DateTime(2026, 5, 24, 9, 0); // Sunday
        final next = r.nextOccurrence(sun)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 25);
      });

      test('mon/wed/fri: Mon completed → Wed', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        final mon = DateTime(2026, 5, 25, 10, 0); // Monday
        final next = r.nextOccurrence(mon)!;
        expect(next.weekday, 3); // Wednesday
        expect(next.day, 27);
      });

      test('mon/wed/fri: Wed completed → Fri', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        final wed = DateTime(2026, 5, 27, 10, 0); // Wednesday
        final next = r.nextOccurrence(wed)!;
        expect(next.weekday, 5); // Friday
        expect(next.day, 29);
      });

      test('mon/wed/fri: Fri completed → next Mon', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        final fri = DateTime(2026, 5, 29, 10, 0); // Friday
        final next = r.nextOccurrence(fri)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 1); // June 1
        expect(next.month, 6);
      });

      test('mon/wed/fri: Sat completed → Mon', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        final sat = DateTime(2026, 5, 30, 10, 0); // Saturday
        final next = r.nextOccurrence(sat)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 1);
        expect(next.month, 6);
      });

      test('single day mon: Mon completed → next Mon', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1],
        );
        final mon = DateTime(2026, 5, 25, 10, 0); // Monday
        final next = r.nextOccurrence(mon)!;
        expect(next.weekday, 1); // Monday
        expect(next.day, 1); // June 1
      });

      test('preserves original time on weekday recurrence', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        final fri = DateTime(2026, 5, 22, 15, 45); // Friday 3:45 PM
        final next = r.nextOccurrence(fri)!;
        expect(next.hour, 15);
        expect(next.minute, 45);
      });

      test('daily interval unchanged', () {
        final r = Recurrence(frequency: RecurrenceFrequency.daily);
        final d = DateTime(2026, 5, 22, 8, 0);
        final next = r.nextOccurrence(d)!;
        expect(next.day, 23);
        expect(next.hour, 8);
      });

      test('weekly interval unchanged', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, interval: 2);
        final d = DateTime(2026, 5, 22, 8, 0);
        final next = r.nextOccurrence(d)!;
        expect(next.day, 5); // 14 days later = June 5
        expect(next.month, 6);
      });

      test('monthly: Jan 31 → clamped to Feb 28 (non-leap)', () {
        final r = Recurrence(frequency: RecurrenceFrequency.monthly);
        final d = DateTime(2026, 1, 31, 9, 0); // 2026 is not a leap year
        final next = r.nextOccurrence(d)!;
        expect(next.month, 2);
        expect(next.day, 28);
        expect(next.hour, 9);
      });

      test('monthly: Jan 31 → clamped to Feb 29 (leap year)', () {
        final r = Recurrence(frequency: RecurrenceFrequency.monthly);
        final d = DateTime(2024, 1, 31, 9, 0); // 2024 is a leap year
        final next = r.nextOccurrence(d)!;
        expect(next.month, 2);
        expect(next.day, 29);
      });

      test('monthly: Dec 31 → Jan 31 next year (no overflow into March)', () {
        final r = Recurrence(frequency: RecurrenceFrequency.monthly);
        final d = DateTime(2026, 12, 31, 9, 0);
        final next = r.nextOccurrence(d)!;
        expect(next.year, 2027);
        expect(next.month, 1);
        expect(next.day, 31);
      });

      test('yearly: Feb 29 on a leap year → clamped to Feb 28 next year', () {
        final r = Recurrence(frequency: RecurrenceFrequency.yearly);
        final d = DateTime(2024, 2, 29, 9, 0);
        final next = r.nextOccurrence(d)!;
        expect(next.year, 2025);
        expect(next.month, 2);
        expect(next.day, 28);
      });
    });

    group('label', () {
      test('weekdays', () {
        final r = Recurrence(frequency: RecurrenceFrequency.weekly, isWeekdays: true);
        expect(r.label, 'Weekdays');
      });

      test('mon/wed/fri', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1, 3, 5],
        );
        expect(r.label, 'Mon/Wed/Fri');
      });

      test('single mon', () {
        final r = Recurrence(
          frequency: RecurrenceFrequency.weekly,
          daysOfWeek: [1],
        );
        expect(r.label, 'Mon');
      });

      test('daily', () {
        expect(Recurrence(frequency: RecurrenceFrequency.daily).label, 'Daily');
      });

      test('every 2 days', () {
        expect(
          Recurrence(frequency: RecurrenceFrequency.daily, interval: 2).label,
          'Every 2 days',
        );
      });
    });

    group('displayLabel', () {
      test('null input returns null', () {
        expect(Recurrence.displayLabel(null), isNull);
      });

      test('returns label for valid storage', () {
        expect(Recurrence.displayLabel('weekly|1|weekdays'), 'Weekdays');
      });
    });
  });
}
