import 'package:flutter/material.dart';

class HighlightToken {
  final int start;
  final int end;
  final Color color;

  HighlightToken({
    required this.start,
    required this.end,
    required this.color,
  });

  bool overlaps(int s, int e) => s < end && e > start;
}

class TaskHighlighter {
  static const _priorityColor = Color(0xFFF28B82);
  static const _projectColor = Color(0xFF7C6DF2);
  static const _dateColor = Color(0xFF81C995);
  static const _timeColor = Color(0xFF8AB4F8);

  static final _priorityRe = RegExp(
    r'(?:^|\s)(p[01234]|!(?:critical|high|medium|low|none))(?=\s|$)',
    caseSensitive: false,
  );
  static final _projectRe = RegExp(r'@(\w+)', caseSensitive: false);
  static final _dateRe = RegExp(
    r'\b(?:'
    r'today|tod|tomorrow|tom|tmr|tmw|2moro|2morrow|'
    r'in\s+(?:(\d+)|a(?:n)?)\s*'
    r'(min|mins|minute|minutes|hour|hours|hr|hrs|day|days|week|weeks|month|months)|'
    r'(?:this|next)\s+'
    r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
    r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)|'
    r'(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|'
    r'monday|tuesday|wednesday|thursday|friday|saturday|sunday)|'
    r'every\s+(?:weekdays?|'
    r'(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)(?:\s*/\s*'
    r'(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun))+|'
    r'(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))|'
    r'every\s+(?:\d+\s+)?(?:day|days|week|weeks|month|months|year|years)|'
    r'(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?|'
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
    r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
    r'nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?|'
    r'(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
    r'jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
    r'nov(?:ember)?|dec(?:ember)?)'
    r')\b',
    caseSensitive: false,
  );
  static final _timeRe = RegExp(
    r'(?:at\s+)?\b(\d{1,2})([:.](\d{2}))?\s*(am|pm)?\b',
    caseSensitive: false,
  );

  static List<HighlightToken> scan(String text) {
    final tokens = <HighlightToken>[];

    _addMatches(text, _priorityRe, tokens, _priorityColor);
    _addMatches(text, _projectRe, tokens, _projectColor);
    _addMatches(text, _dateRe, tokens, _dateColor);
    _addMatches(text, _timeRe, tokens, _timeColor);

    tokens.sort((a, b) => a.start.compareTo(b.start));
    return tokens;
  }

  static void _addMatches(
    String text,
    RegExp re,
    List<HighlightToken> tokens,
    Color color,
  ) {
    for (final m in re.allMatches(text)) {
      var s = m.start;
      var e = m.end;

      // Priority regex (?:^|\s) consumes leading space; skip it
      if (identical(re, _priorityRe)) {
        final g0 = m.group(0)!;
        final g1 = m.group(1)!;
        s = m.start + (g0.length - g1.length);
        e = s + g1.length;
      }

      if (tokens.any((t) => t.overlaps(s, e))) continue;

      // Apply same guard as parser for bare times
      if (identical(re, _timeRe)) {
        final full = m.group(0)!.toLowerCase();
        final hasAt = full.startsWith('at ');
        final hasMinute = m.group(2) != null;
        final hasAmPm = m.group(4) != null;
        if (!hasAt && !hasMinute && !hasAmPm) continue;
        if (full.contains('.') && !hasAt) continue;
      }

      tokens.add(HighlightToken(start: s, end: e, color: color));
    }
  }
}
