import 'json_reader.dart';
import 'session_record.dart';

/// One day's focus, summed over every session that started on it.
class DayTally {
  const DayTally({
    required this.day,
    this.focused = Duration.zero,
    this.interruptions = 0,
    this.sessions = 0,
  });

  /// Local midnight of the day.
  final DateTime day;

  final Duration focused;

  /// Pick-ups across the day's sessions.
  final int interruptions;

  final int sessions;

  bool meets(Duration goal) => goal > Duration.zero && focused >= goal;

  DayTally adding(SessionRecord record) => DayTally(
        day: day,
        focused: focused + record.focused,
        interruptions: interruptions + record.interruptions,
        sessions: sessions + 1,
      );

  Map<String, dynamic> toJson() => {
        'day': ProgressLog.keyOf(day),
        'focusedSeconds': focused.inSeconds,
        'interruptions': interruptions,
        'sessions': sessions,
      };

  static DayTally? fromJson(Map<String, dynamic> json) {
    final key = json.readString('day');
    final day = key == null ? null : DateTime.tryParse(key);
    if (day == null) return null;
    return DayTally(
      day: ProgressLog.dayOf(day),
      focused: json.readDuration('focusedSeconds'),
      interruptions: json.readInt('interruptions'),
      sessions: json.readInt('sessions'),
    );
  }
}

/// A Monday-to-Sunday week of tallies.
class WeekSummary {
  const WeekSummary({required this.start, required this.days});

  /// Monday, local midnight.
  final DateTime start;

  /// Seven tallies, Monday first. Days without a session are empty tallies.
  final List<DayTally> days;

  Duration get focused => days.fold(Duration.zero, (sum, day) => sum + day.focused);

  int get interruptions => days.fold(0, (sum, day) => sum + day.interruptions);

  int get sessions => days.fold(0, (sum, day) => sum + day.sessions);

  int daysMeeting(Duration goal) => days.where((day) => day.meets(goal)).length;

  /// Pick-ups per focused hour, or `null` with nothing focused.
  double? get interruptionsPerHour {
    final hours = focused.inSeconds / 3600;
    return hours <= 0 ? null : interruptions / hours;
  }

  Duration get longestDay => days.fold(
        Duration.zero,
        (longest, day) => day.focused > longest ? day.focused : longest,
      );
}

/// Focus per calendar day, kept long after the session log has trimmed the
/// sessions themselves, so weekly totals stay whole.
///
/// A session counts on the day it started, even if it ran past midnight.
class ProgressLog {
  const ProgressLog([this._days = const {}]);

  static const ProgressLog empty = ProgressLog();

  /// Days kept. Older ones fall off as new ones arrive.
  static const int keepDays = 120;

  final Map<String, DayTally> _days;

  /// `2026-09-14`, the key a day is stored under.
  static String keyOf(DateTime day) {
    final d = dayOf(day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Local midnight of [moment]'s day.
  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// Monday of [moment]'s week. Built from the calendar date rather than by
  /// subtracting hours, so a daylight-saving change cannot shift it.
  static DateTime weekStartOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day - (moment.weekday - 1));

  bool get isEmpty => _days.isEmpty;

  /// The earliest day on record, if any.
  DateTime? get firstDay {
    if (_days.isEmpty) return null;
    return _days.values
        .map((tally) => tally.day)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DayTally dayAt(DateTime moment) =>
      _days[keyOf(moment)] ?? DayTally(day: dayOf(moment));

  WeekSummary weekOf(DateTime moment) {
    final start = weekStartOf(moment);
    return WeekSummary(
      start: start,
      days: [
        for (var i = 0; i < 7; i++)
          dayAt(DateTime(start.year, start.month, start.day + i)),
      ],
    );
  }

  /// Adds [record] to its day and drops days past [keepDays].
  ProgressLog recording(SessionRecord record) {
    final key = keyOf(record.startedAt);
    final next = Map<String, DayTally>.of(_days)
      ..[key] = dayAt(record.startedAt).adding(record);
    final latest = next.values
        .map((tally) => tally.day)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final cutoff = DateTime(latest.year, latest.month, latest.day - keepDays + 1);
    next.removeWhere((_, tally) => tally.day.isBefore(cutoff));
    return ProgressLog(next);
  }

  /// Rebuilds the tallies from a session log, oldest first. Used once, for
  /// installs that banked sessions before the log existed.
  static ProgressLog fromHistory(Iterable<SessionRecord> history) {
    var log = ProgressLog.empty;
    final oldestFirst = history.toList(growable: false).reversed;
    for (final record in oldestFirst) {
      log = log.recording(record);
    }
    return log;
  }

  Map<String, dynamic> toJson() => {
        'days': [for (final tally in _days.values) tally.toJson()],
      };

  static ProgressLog fromJson(Map<String, dynamic> json) {
    final days = <String, DayTally>{};
    for (final entry in json.readObjects('days')) {
      final tally = DayTally.fromJson(entry);
      if (tally != null) days[keyOf(tally.day)] = tally;
    }
    return ProgressLog(days);
  }
}
