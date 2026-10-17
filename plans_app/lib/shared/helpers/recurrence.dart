enum RecurrenceFrequency { daily, weekly, monthly, yearly }

const _dayNames = {
  1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun',
};

const _shortNames = {
  'mon': 1, 'tue': 2, 'tues': 2, 'wed': 3,
  'thu': 4, 'thur': 4, 'thurs': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
  'friday': 5, 'saturday': 6, 'sunday': 7,
};

int? _parseDayName(String s) => _shortNames[s.toLowerCase()];

class Recurrence {
  final RecurrenceFrequency frequency;
  final int interval;
  final List<int>? daysOfWeek;
  final bool isWeekdays;

  const Recurrence({
    required this.frequency,
    this.interval = 1,
    this.daysOfWeek,
    this.isWeekdays = false,
  });

  String toStorage() {
    var s = '${frequency.name}|$interval';
    if (isWeekdays) {
      s += '|weekdays';
    } else if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      s += '|${daysOfWeek!.map((d) => _dayNames[d]!.toLowerCase()).join(',')}';
    }
    return s;
  }

  factory Recurrence.fromStorage(String s) {
    final parts = s.split('|');
    final freq = RecurrenceFrequency.values.firstWhere(
      (e) => e.name == parts[0],
    );
    final interval = parts.length > 1 ? int.parse(parts[1]) : 1;
    List<int>? daysOfWeek;
    var isWeekdays = false;
    if (parts.length > 2 && parts[2].isNotEmpty) {
      if (parts[2] == 'weekdays') {
        isWeekdays = true;
      } else {
        daysOfWeek = parts[2]
            .split(',')
            .map((d) => _parseDayName(d.trim()))
            .where((d) => d != null)
            .cast<int>()
            .toList();
        if (daysOfWeek.isEmpty) daysOfWeek = null;
      }
    }
    return Recurrence(
      frequency: freq,
      interval: interval,
      daysOfWeek: daysOfWeek,
      isWeekdays: isWeekdays,
    );
  }

  DateTime? nextOccurrence(DateTime from) {
    if (daysOfWeek != null || isWeekdays) {
      var next = from.add(const Duration(days: 1));
      for (int i = 0; i < 7; i++) {
        if (isWeekdays && next.weekday <= 5) {
          return DateTime(next.year, next.month, next.day, from.hour, from.minute);
        }
        if (daysOfWeek != null && daysOfWeek!.contains(next.weekday)) {
          return DateTime(next.year, next.month, next.day, from.hour, from.minute);
        }
        next = next.add(const Duration(days: 1));
      }
      return null;
    }

    switch (frequency) {
      case RecurrenceFrequency.daily:
        return from.add(Duration(days: interval));
      case RecurrenceFrequency.weekly:
        return from.add(Duration(days: 7 * interval));
      case RecurrenceFrequency.monthly:
        final totalMonths = from.month - 1 + interval;
        final targetYear = from.year + totalMonths ~/ 12;
        final targetMonth = totalMonths % 12 + 1;
        final day = from.day.clamp(1, _daysInMonth(targetYear, targetMonth));
        return DateTime(targetYear, targetMonth, day, from.hour, from.minute);
      case RecurrenceFrequency.yearly:
        final targetYear = from.year + interval;
        final day = from.day.clamp(1, _daysInMonth(targetYear, from.month));
        return DateTime(targetYear, from.month, day, from.hour, from.minute);
    }
  }

  /// Day 0 of the following month is the last day of [month].
  static int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  String get label {
    if (isWeekdays) return 'Weekdays';
    if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
      final names = daysOfWeek!.map((d) => _dayNames[d]!).toList();
      return names.join('/');
    }

    switch (frequency) {
      case RecurrenceFrequency.daily:
        return interval == 1 ? 'Daily' : 'Every $interval days';
      case RecurrenceFrequency.weekly:
        return interval == 1 ? 'Weekly' : 'Every $interval weeks';
      case RecurrenceFrequency.monthly:
        return interval == 1 ? 'Monthly' : 'Every $interval months';
      case RecurrenceFrequency.yearly:
        return interval == 1 ? 'Yearly' : 'Every $interval years';
    }
  }

  static String? displayLabel(String? storage) {
    if (storage == null) return null;
    return Recurrence.fromStorage(storage).label;
  }
}
