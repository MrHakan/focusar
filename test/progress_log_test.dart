import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/progress_log.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';

SessionRecord session(
  DateTime at, {
  Duration focused = const Duration(minutes: 25),
  int interruptions = 0,
}) =>
    SessionRecord(
      startedAt: at,
      focused: focused,
      creditsEarned: focused.inSeconds / 60,
      interruptions: interruptions,
      mode: FocusMode.timed,
      method: PlacementMethod.motionOnly,
      completed: true,
    );

void main() {
  // A Wednesday.
  final wednesday = DateTime(2026, 9, 16, 10);

  test('folds sessions into the day they started', () {
    final log = ProgressLog.empty
        .recording(session(wednesday, interruptions: 2))
        .recording(session(wednesday.add(const Duration(hours: 5)), interruptions: 1));

    final day = log.dayAt(wednesday);

    expect(day.focused, const Duration(minutes: 50));
    expect(day.interruptions, 3);
    expect(day.sessions, 2);
  });

  test('a session past midnight counts on the day it started', () {
    final late = DateTime(2026, 9, 16, 23, 50);
    final log = ProgressLog.empty.recording(session(late, focused: const Duration(minutes: 40)));

    expect(log.dayAt(late).focused, const Duration(minutes: 40));
    expect(log.dayAt(DateTime(2026, 9, 17, 1)).focused, Duration.zero);
  });

  test('a day with nothing is an empty tally, not a gap', () {
    final day = ProgressLog.empty.dayAt(wednesday);

    expect(day.focused, Duration.zero);
    expect(day.day, DateTime(2026, 9, 16));
  });

  group('weeks', () {
    test('run Monday to Sunday', () {
      expect(ProgressLog.weekStartOf(wednesday), DateTime(2026, 9, 14));
      expect(ProgressLog.weekStartOf(DateTime(2026, 9, 14)), DateTime(2026, 9, 14));
      expect(ProgressLog.weekStartOf(DateTime(2026, 9, 20, 23)), DateTime(2026, 9, 14));
    });

    test('cross a month end and a daylight-saving change cleanly', () {
      // Europe and the US both change clocks around these dates.
      expect(ProgressLog.weekStartOf(DateTime(2026, 11, 1, 12)), DateTime(2026, 10, 26));
      expect(ProgressLog.weekStartOf(DateTime(2026, 3, 29, 12)), DateTime(2026, 3, 23));
    });

    test('sum focus, pick-ups, sessions, and goal days', () {
      final log = ProgressLog.empty
          .recording(session(DateTime(2026, 9, 14, 9), focused: const Duration(hours: 1)))
          .recording(session(wednesday, focused: const Duration(minutes: 30), interruptions: 3))
          .recording(session(DateTime(2026, 9, 20, 9), focused: const Duration(hours: 2)))
          // The week before and the week after stay out.
          .recording(session(DateTime(2026, 9, 13, 9)))
          .recording(session(DateTime(2026, 9, 21, 9)));

      final week = log.weekOf(wednesday);

      expect(week.days, hasLength(7));
      expect(week.days.first.day, DateTime(2026, 9, 14));
      expect(week.days.last.day, DateTime(2026, 9, 20));
      expect(week.focused, const Duration(hours: 3, minutes: 30));
      expect(week.interruptions, 3);
      expect(week.sessions, 3);
      expect(week.daysMeeting(const Duration(hours: 1)), 2);
      expect(week.longestDay, const Duration(hours: 2));
      expect(week.interruptionsPerHour, closeTo(3 / 3.5, 1e-9));
    });

    test('an empty week has no pick-up rate', () {
      expect(ProgressLog.empty.weekOf(wednesday).interruptionsPerHour, isNull);
    });
  });

  test('a goal of zero is never met', () {
    final day = ProgressLog.empty.recording(session(wednesday)).dayAt(wednesday);

    expect(day.meets(Duration.zero), isFalse);
    expect(day.meets(const Duration(minutes: 25)), isTrue);
  });

  test('keeps a bounded number of days', () {
    var log = ProgressLog.empty;
    for (var i = 0; i < ProgressLog.keepDays + 10; i++) {
      log = log.recording(session(DateTime(2026, 1, 1 + i, 9)));
    }

    expect(log.dayAt(DateTime(2026, 1, 1)).sessions, 0);
    expect(log.dayAt(DateTime(2026, 1, 11)).sessions, 1);
    expect(log.firstDay, DateTime(2026, 1, 11));
  });

  test('rebuilds itself from a newest-first session log', () {
    final history = [
      session(DateTime(2026, 9, 16, 9), interruptions: 1),
      session(DateTime(2026, 9, 15, 9)),
      session(DateTime(2026, 9, 15, 7)),
    ];

    final log = ProgressLog.fromHistory(history);

    expect(log.dayAt(DateTime(2026, 9, 15)).sessions, 2);
    expect(log.dayAt(DateTime(2026, 9, 16)).interruptions, 1);
  });

  test('round-trips through JSON and skips damaged days', () {
    final log = ProgressLog.empty.recording(session(wednesday, interruptions: 2));
    final json = log.toJson();
    (json['days'] as List).add({'day': 'not a date', 'focusedSeconds': 60});

    final restored = ProgressLog.fromJson(json);

    expect(restored.dayAt(wednesday).focused, const Duration(minutes: 25));
    expect(restored.dayAt(wednesday).interruptions, 2);
    expect(ProgressLog.keyOf(wednesday), '2026-09-16');
  });
}
