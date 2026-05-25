import '../../features/tasks/models/task.dart';
import '../../features/projects/models/project.dart';

class TaskParseResult {
  final String title;
  final TaskPriority? priority;
  final String? projectId;
  final DateTime? dueDate;
  final bool hasDueDate;
  final int? defaultReminderMinutes;
  final String? recurrence;

  TaskParseResult({
    required this.title,
    this.priority,
    this.projectId,
    this.dueDate,
    this.hasDueDate = false,
    this.defaultReminderMinutes,
    this.recurrence,
  });
}

class TaskParser {
  static TaskParseResult parse(
    String input,
    List<Project> projects, {
    DateTime? now,
  }) {
    final nowDt = now ?? DateTime.now();
    var text = input.trim();
    if (text.isEmpty) {
      return TaskParseResult(title: input);
    }

    TaskPriority? priority;
    String? projectId;
    DateTime? dueDate;
    bool hasDueDate = false;

    text = _extractPriority(text, (p) => priority = p);
    text = _extractProject(text, projects, (id) => projectId = id);

    String? recurrence;
    text = _extractRecurrence(text, (r) => recurrence = r);

    final dateTimeResult = _extractDateTime(text, nowDt);
    text = dateTimeResult.remaining;
    if (dateTimeResult.dueDate != null) {
      dueDate = dateTimeResult.dueDate;
      hasDueDate = true;
    }

    if (recurrence != null && dueDate == null) {
      dueDate = nowDt;
      hasDueDate = true;
    }

    final title = text.trim().isEmpty ? input.trim() : text.trim();

    return TaskParseResult(
      title: title,
      priority: priority,
      projectId: projectId,
      dueDate: dueDate,
      hasDueDate: hasDueDate,
      defaultReminderMinutes: hasDueDate ? 0 : null,
      recurrence: recurrence,
    );
  }

  // ── Priority ────────────────────────────────────────────────────────

  static String _extractPriority(
    String text,
    void Function(TaskPriority) set,
  ) {
    final m = RegExp(
      r'(?:^|\s)(p[01234]|!(?:critical|high|medium|low|none))(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return text;

    final setPriority = switch (m.group(1)!.toLowerCase()) {
      'p0' || '!critical' => TaskPriority.critical,
      'p1' || '!high' => TaskPriority.high,
      'p2' || '!medium' => TaskPriority.medium,
      'p3' || '!low' => TaskPriority.low,
      _ => TaskPriority.none,
    };
    set(setPriority);
    return text.replaceFirst(m.group(0)!, '').trim();
  }

  // ── Project ─────────────────────────────────────────────────────────

  static String _extractProject(
    String text,
    List<Project> projects,
    void Function(String) set,
  ) {
    if (projects.isEmpty) return text;
    final m = RegExp(r'@(\w+)', caseSensitive: false).firstMatch(text);
    if (m == null) return text;

    final matched = projects.where(
      (p) => p.name.toLowerCase() == m.group(1)!.toLowerCase(),
    );
    if (matched.isEmpty) return text;

    set(matched.first.id);
    return text.replaceFirst(m.group(0)!, '').trim();
  }

  // ── Recurrence ──────────────────────────────────────────────────────

  static String _extractRecurrence(
    String text,
    void Function(String) set,
  ) {
    // Check weekday-specific patterns first (before the generic interval pattern)
    final weekdayRe = RegExp(
      r'\bevery\s+(?:'
      r'(weekdays?)'
      r')\b',
      caseSensitive: false,
    );
    var m = weekdayRe.firstMatch(text);
    if (m != null) {
      set('weekly|1|weekdays');
      return text.replaceFirst(m.group(0)!, '').trim();
    }

    // Multi-day: every mon/wed/fri, every monday/tuesday
    final multiDayRe = RegExp(
      r'\bevery\s+'
      r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
      r'(?:\s*/\s*'
      r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday))+'
      r'\b',
      caseSensitive: false,
    );
    m = multiDayRe.firstMatch(text);
    if (m != null) {
      // Split the full match on '/' to extract all days
      final full = m.group(0)!;
      final parts = full.substring(6).split('/'); // skip "every "
      final days = parts
          .map((d) => _toShortDay(d.trim()))
          .where((d) => d != null)
          .cast<String>()
          .toList();
      if (days.isNotEmpty) {
        set('weekly|1|${days.join(',')}');
        return text.replaceFirst(m.group(0)!, '').trim();
      }
    }

    // Single day: every monday
    final singleDayRe = RegExp(
      r'\bevery\s+'
      r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
      r'\b',
      caseSensitive: false,
    );
    m = singleDayRe.firstMatch(text);
    if (m != null) {
      final short = _toShortDay(m.group(1)!);
      if (short != null) {
        set('weekly|1|$short');
        return text.replaceFirst(m.group(0)!, '').trim();
      }
    }

    // Generic interval: every N days/weeks/months/years
    final intervalRe = RegExp(
      r'\bevery\s+(?:(\d+)\s+)?(day|days|week|weeks|month|months|year|years)\b',
      caseSensitive: false,
    );
    m = intervalRe.firstMatch(text);
    if (m == null) return text;

    final unit = m.group(2)!.toLowerCase();
    final interval = m.group(1) != null ? int.parse(m.group(1)!) : 1;

    final freq = switch (unit) {
      'day' || 'days' => 'daily',
      'week' || 'weeks' => 'weekly',
      'month' || 'months' => 'monthly',
      _ => 'yearly',
    };

    set('$freq|$interval');
    return text.replaceFirst(m.group(0)!, '').trim();
  }

  static String? _toShortDay(String name) {
    const map = {
      'mon': 'mon', 'tue': 'tue', 'tues': 'tue', 'wed': 'wed',
      'thu': 'thu', 'thur': 'thu', 'thurs': 'thu', 'fri': 'fri',
      'sat': 'sat', 'sun': 'sun',
      'monday': 'mon', 'tuesday': 'tue', 'wednesday': 'wed',
      'thursday': 'thu', 'friday': 'fri', 'saturday': 'sat', 'sunday': 'sun',
    };
    return map[name.toLowerCase()];
  }

  // ── Date / Time ─────────────────────────────────────────────────────

  static _DateTimeResult _extractDateTime(String text, DateTime now) {
    var remaining = text;

    // Extract sequentially so each operates on updated remaining text.
    final timeInfo = _extractTime(remaining);
    if (timeInfo != null) {
      remaining = timeInfo.remaining;
    }

    final dateInfo = _extractDate(remaining, now);
    if (dateInfo != null) {
      remaining = dateInfo.remaining;
    }

    DateTime? dueDate;

    if (timeInfo != null && dateInfo != null) {
      dueDate = _combineTimeAndDate(
        timeInfo.hour,
        timeInfo.minute,
        timeInfo.isPm,
        dateInfo.date,
        now,
      );
    } else if (timeInfo != null) {
      dueDate = _resolveTime(timeInfo.hour, timeInfo.minute, timeInfo.isPm, now);
    } else if (dateInfo != null) {
      dueDate = dateInfo.preserveTime
          ? dateInfo.date
          : _sameTime(dateInfo.date, now);
    }

    return _DateTimeResult(remaining: remaining, dueDate: dueDate);
  }

  static _TimeInfo? _extractTime(String text) {
    final re = RegExp(
      r'(?:at\s+)?\b(\d{1,2})([:.](\d{2}))?\s*(am|pm)?\b',
      caseSensitive: false,
    );
    for (final m in re.allMatches(text)) {
      final full = m.group(0)!.toLowerCase();
      final hasAt = full.startsWith('at ');
      final hasMinute = m.group(2) != null;
      final hasAmPm = m.group(4) != null;
      if (!hasAt && !hasMinute && !hasAmPm) continue;

      // Decimal "." separator requires "at" prefix
      if (full.contains('.') && !hasAt) continue;

      final hour = int.parse(m.group(1)!);
      final minute = m.group(2) != null ? int.parse(m.group(3)!) : 0;
      if (minute < 0 || minute > 59) continue;

      final ap = m.group(4)?.toLowerCase();
      bool? isPm;
      if (ap == 'pm') {
        isPm = true;
      } else if (ap == 'am') {
        isPm = false;
      }

      return _TimeInfo(
        remaining: text.replaceFirst(m.group(0)!, '').trim(),
        hour: hour,
        minute: minute,
        isPm: isPm,
      );
    }
    return null;
  }

  static _DateInfo? _extractDate(String text, DateTime now) {
    final keywordResult = _extractKeywordDate(text, now);
    if (keywordResult != null) return keywordResult;

    final numericResult = _extractNumericDate(text, now);
    if (numericResult != null) return numericResult;

    return _extractTextDate(text, now);
  }

  static _DateInfo? _extractKeywordDate(String text, DateTime now) {
    final m = RegExp(
      r'\b(?:'
      r'today|tod|tomorrow|tom|tmr|tmw|2moro|2morrow|'
      r'in\s+(?:(\d+)|a(?:n)?)\s*'
      r'(min|mins|minute|minutes|hour|hours|hr|hrs|day|days|week|weeks|month|months)|'
      r'(?:this|next)\s+'
      r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)|'
      r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
      r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
      r')\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;

    final keyword = m.group(0)!.toLowerCase();
    DateTime date;

    if (keyword == 'today' || keyword == 'tod') {
      date = now;
    } else if (keyword == 'tomorrow' || keyword == 'tom' || keyword == 'tmr' ||
        keyword == 'tmw' || keyword == '2moro' || keyword == '2morrow') {
      date = now.add(const Duration(days: 1));
    } else if (keyword.startsWith('in ')) {
      final amount = m.group(1) != null ? int.parse(m.group(1)!) : 1;
      final unit = m.group(2)!.toLowerCase();
      switch (unit) {
        case 'min' || 'mins' || 'minute' || 'minutes':
          date = now.add(Duration(minutes: amount));
        case 'hour' || 'hours' || 'hr' || 'hrs':
          date = now.add(Duration(hours: amount));
        case 'day' || 'days':
          date = now.add(Duration(days: amount));
        case 'week' || 'weeks':
          date = now.add(Duration(days: amount * 7));
        case 'month' || 'months':
          date = now.add(Duration(days: amount * 30));
        default:
          date = now;
      }
    } else {
      final skipToday = keyword.startsWith('next ');
      final dayName = skipToday ? keyword.substring(5) : keyword;
      if (dayName.startsWith('this ')) {
        final inner = dayName.substring(5);
        final target = _dayIndex(inner);
        if (target == null) return null;
        date = _nextWeekday(now, target, skipToday: false);
      } else {
        final target = _dayIndex(dayName);
        if (target == null) return null;
        date = _nextWeekday(now, target, skipToday: skipToday);
      }
    }

    final isTimeRelative = keyword.startsWith('in ') &&
        switch (m.group(2)!.toLowerCase()) {
          'min' || 'mins' || 'minute' || 'minutes' || 'hour' || 'hours' || 'hr' || 'hrs' => true,
          _ => false,
        };

    return _DateInfo(
      remaining: text.replaceFirst(m.group(0)!, '').trim(),
      date: date,
      isToday: keyword == 'today' || keyword == 'tod',
      preserveTime: isTimeRelative,
    );
  }

  static _DateInfo? _extractNumericDate(String text, DateTime now) {
    final m = RegExp(
      r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b',
    ).firstMatch(text);
    if (m == null) return null;

    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    if (day < 1 || day > 31 || month < 1 || month > 12) return null;

    var year = now.year;
    if (m.group(3) != null) {
      final y = int.parse(m.group(3)!);
      year = y < 100 ? 2000 + y : y;
    }

    var date = DateTime(year, month, day);
    if (date.isBefore(DateTime(now.year, now.month, now.day))) {
      date = DateTime(year + 1, month, day);
    }

    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return _DateInfo(
      remaining: text.replaceFirst(m.group(0)!, '').trim(),
      date: date,
      isToday: isToday,
    );
  }

  static _DateInfo? _extractTextDate(String text, DateTime now) {
    final m = RegExp(
      r'\b('
      r'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
      r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
      r'nov(?:ember)?|dec(?:ember)?'
      r')\s+(\d{1,2})(?:st|nd|rd|th)?'
      r'|'
      r'(\d{1,2})(?:st|nd|rd|th)?\s+('
      r'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
      r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
      r'nov(?:ember)?|dec(?:ember)?'
      r')'
      r'\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;

    int month;
    int day;

    if (m.group(1) != null) {
      final monthIdx = _monthIndex(m.group(1)!);
      if (monthIdx == null) return null;
      month = monthIdx;
      day = int.parse(m.group(2)!);
    } else if (m.group(4) != null) {
      final monthIdx = _monthIndex(m.group(4)!);
      if (monthIdx == null) return null;
      month = monthIdx;
      day = int.parse(m.group(3)!);
    } else {
      return null;
    }

    if (day < 1 || day > 31) return null;

    var date = DateTime(now.year, month, day);
    if (date.isBefore(DateTime(now.year, now.month, now.day))) {
      date = DateTime(now.year + 1, month, day);
    }

    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    return _DateInfo(
      remaining: text.replaceFirst(m.group(0)!, '').trim(),
      date: date,
      isToday: isToday,
    );
  }

  /// Combine parsed time with parsed date.
  ///
  /// Rules:
  ///   - Explicit am/pm → use that time on the date.
  ///   - Ambiguous time + "today" → next-occurrence from now.
  ///   - Ambiguous time + non-today date → default to AM.
  static DateTime _combineTimeAndDate(
    int hour,
    int minute,
    bool? isPm,
    DateTime date,
    DateTime now,
  ) {
    if (isPm != null) {
      final h = _to24Hour(hour, isPm);
      return DateTime(date.year, date.month, date.day, h, minute);
    }

    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    if (isToday) {
      return _resolveTime(hour, minute, null, now);
    }

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Resolve ambiguous time to next occurrence from [now].
  ///
  ///  "7" @ 2pm → 7pm today.  "7" @ 10pm → 7am tomorrow.
  ///  "12" → noon first, then midnight.
  static DateTime _resolveTime(
    int hour,
    int minute,
    bool? isPm,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);

    if (isPm == true) {
      var dt = DateTime(today.year, today.month, today.day, _to24Hour(hour, true), minute);
      return dt.isAfter(now) ? dt : dt.add(const Duration(days: 1));
    }
    if (isPm == false) {
      var dt = DateTime(today.year, today.month, today.day, _to24Hour(hour, false), minute);
      return dt.isAfter(now) ? dt : dt.add(const Duration(days: 1));
    }

    if (hour == 12) {
      var noon = DateTime(today.year, today.month, today.day, 12, minute);
      if (noon.isAfter(now)) return noon;
      var mid = DateTime(today.year, today.month, today.day, 0, minute);
      if (mid.isAfter(now)) return mid;
      return noon.add(const Duration(days: 1));
    }

    var am = DateTime(today.year, today.month, today.day, hour, minute);
    var pm = DateTime(today.year, today.month, today.day, hour + 12, minute);
    if (am.isAfter(now)) return am;
    if (pm.isAfter(now)) return pm;
    return am.add(const Duration(days: 1));
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  static int _to24Hour(int hour, bool isPm) {
    if (isPm) return hour == 12 ? 12 : hour + 12;
    return hour == 12 ? 0 : hour;
  }

  /// Returns a date with same clock time as [now] on [target]'s date.
  static DateTime _sameTime(DateTime target, DateTime now) {
    return DateTime(
      target.year, target.month, target.day,
      now.hour, now.minute, now.second,
    );
  }

  static int? _dayIndex(String name) {
    const days = {
      'monday': 1, 'mon': 1,
      'tuesday': 2, 'tue': 2, 'tues': 2,
      'wednesday': 3, 'wed': 3,
      'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4,
      'friday': 5, 'fri': 5,
      'saturday': 6, 'sat': 6,
      'sunday': 7, 'sun': 7,
    };
    return days[name];
  }

  static int? _monthIndex(String name) {
    const months = {
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };
    return months[name.toLowerCase()];
  }

  static DateTime _nextWeekday(DateTime now, int target, {bool skipToday = false}) {
    var diff = target - now.weekday;
    if (diff < 0 || (diff == 0 && skipToday)) diff += 7;
    return now.add(Duration(days: diff));
  }
}

// ── Internal types ───────────────────────────────────────────────────

class _TimeInfo {
  final String remaining;
  final int hour;
  final int minute;
  final bool? isPm;
  _TimeInfo({
    required this.remaining,
    required this.hour,
    required this.minute,
    this.isPm,
  });
}

class _DateInfo {
  final String remaining;
  final DateTime date;
  final bool isToday;
  final bool preserveTime;
  _DateInfo({
    required this.remaining,
    required this.date,
    required this.isToday,
    this.preserveTime = false,
  });
}

class _DateTimeResult {
  final String remaining;
  final DateTime? dueDate;
  _DateTimeResult({required this.remaining, this.dueDate});
}
