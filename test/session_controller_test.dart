import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/credit_rules.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/state/session_controller.dart';

import 'support/fake_session.dart';

void main() {
  late FakeSensorFeed feed;
  late FakeTicker ticker;
  late RecordingAlerts alerts;
  late ManualClock clock;
  late List<SessionRecord> completed;

  setUp(() {
    feed = FakeSensorFeed();
    ticker = FakeTicker();
    alerts = RecordingAlerts();
    clock = ManualClock();
    completed = [];
  });

  SessionController build({
    FocusMode mode = FocusMode.timed,
    Duration target = const Duration(seconds: 5),
  }) {
    return SessionController(
      config: SessionConfig(
        mode: mode,
        method: PlacementMethod.motionOnly,
        target: target,
      ),
      feed: feed,
      alerts: alerts,
      ticker: ticker.call,
      clock: clock.call,
      onComplete: completed.add,
    )..start();
  }

  /// Puts the phone down and holds it still long enough to arm the session.
  Future<void> settle(SessionController session) async {
    await feed.emit(FakeSensorFeed.still);
    clock.advance(SessionController.armDelay + const Duration(milliseconds: 1));
    await feed.emit(FakeSensorFeed.still);
  }

  group('arming', () {
    test('waits for the phone before it starts counting', () async {
      final session = build();

      expect(session.stage, SessionStage.arming);
      await feed.emit(FakeSensorFeed.still);
      expect(session.stage, SessionStage.arming);

      await ticker.tick();
      expect(session.focused, Duration.zero);

      session.dispose();
    });

    test('starts once the phone has been still long enough', () async {
      final session = build();
      await settle(session);

      expect(session.stage, SessionStage.focusing);
      expect(alerts.starts, 1);

      session.dispose();
    });

    test('restarts the wait if the phone is disturbed mid-settle', () async {
      final session = build();
      await feed.emit(FakeSensorFeed.still);
      clock.advance(const Duration(milliseconds: 900));
      await feed.emit(FakeSensorFeed.lifted);
      clock.advance(const Duration(milliseconds: 900));
      await feed.emit(FakeSensorFeed.still);

      expect(session.stage, SessionStage.arming);

      session.dispose();
    });
  });

  group('counting', () {
    test('advances the clock and banks credits every second', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      await ticker.tick(60);

      expect(session.focused, const Duration(seconds: 60));
      expect(session.earnedCredits, closeTo(1.0, 1e-9));
      expect(session.earnedScreenTime, const Duration(minutes: 1));

      session.dispose();
    });

    test('finishes when the countdown runs out', () async {
      final session = build(target: const Duration(seconds: 3));
      await settle(session);

      await ticker.tick(3);

      expect(session.stage, SessionStage.complete);
      expect(alerts.finishes, 1);
      expect(completed.single.completed, isTrue);
      expect(completed.single.focused, const Duration(seconds: 3));

      session.dispose();
    });

    test('an open session keeps counting past any target', () async {
      final session = build(mode: FocusMode.openEnded);
      await settle(session);

      await ticker.tick(120);

      expect(session.stage, SessionStage.focusing);
      expect(session.display, '02:00');

      session.dispose();
    });

    test('stops the clock dead once complete', () async {
      final session = build(target: const Duration(seconds: 2));
      await settle(session);
      await ticker.tick(2);

      await ticker.tick(5);

      expect(session.focused, const Duration(seconds: 2));
      expect(completed, hasLength(1));

      session.dispose();
    });
  });

  group('interruptions', () {
    test('a snatch alarms immediately', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      await feed.emit(FakeSensorFeed.grabbed);

      expect(session.stage, SessionStage.interrupted);
      expect(session.interruptions, 1);
      expect(alerts.warnings, 1);

      session.dispose();
    });

    test('a brief wobble is forgiven', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      await feed.emit(FakeSensorFeed.lifted);

      expect(session.stage, SessionStage.focusing);

      session.dispose();
    });

    test('sustained movement alarms after the grace period', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      await feed.emit(FakeSensorFeed.lifted);
      clock.advance(SessionController.disturbanceGrace + const Duration(milliseconds: 1));
      await feed.emit(FakeSensorFeed.lifted);

      expect(session.stage, SessionStage.interrupted);

      session.dispose();
    });

    test('the clock and the credits hold while interrupted', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await ticker.tick(10);
      final banked = session.earnedCredits;

      await feed.emit(FakeSensorFeed.grabbed);
      await ticker.tick(10);

      expect(session.focused, const Duration(seconds: 10));
      expect(session.earnedCredits, banked);

      session.dispose();
    });

    test('the alarm repeats for as long as the phone is away', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await feed.emit(FakeSensorFeed.grabbed);

      await ticker.tick(4);

      expect(alerts.warnings, 5);

      session.dispose();
    });

    test('putting it back resumes the session', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await feed.emit(FakeSensorFeed.grabbed);

      await feed.emit(FakeSensorFeed.still);
      clock.advance(SessionController.resumeDelay + const Duration(milliseconds: 1));
      await feed.emit(FakeSensorFeed.still);

      expect(session.stage, SessionStage.focusing);

      await ticker.tick(5);
      expect(session.focused, const Duration(seconds: 5));

      session.dispose();
    });

    test('a pick-up costs the multiplier streak', () async {
      final session = build(target: const Duration(hours: 2));
      await settle(session);
      await ticker.tick(26 * 60);
      expect(session.tier.multiplier, 1.25);

      await feed.emit(FakeSensorFeed.grabbed);

      expect(session.tier.multiplier, 1.0);
      expect(session.unbrokenRun, Duration.zero);

      session.dispose();
    });

    test('leaving the app counts as a pick-up', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      session.reportLeftApp();

      expect(session.stage, SessionStage.interrupted);
      expect(session.interruptions, 1);

      session.dispose();
    });
  });

  group('multipliers', () {
    test('an unbroken run earns faster over time', () async {
      final session = build(target: const Duration(hours: 2));
      await settle(session);

      await ticker.tick(25 * 60);
      final firstStretch = session.earnedCredits;
      await ticker.tick(25 * 60);
      final secondStretch = session.earnedCredits - firstStretch;

      expect(firstStretch, closeTo(25, 1e-6));
      expect(secondStretch, closeTo(25 * 1.25, 1e-6));
      expect(session.tier.multiplier, 1.5);

      session.dispose();
    });
  });

  group('pausing', () {
    test('holds everything and silences the alarm', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await ticker.tick(5);

      session.pause();
      await ticker.tick(10);

      expect(session.stage, SessionStage.paused);
      expect(session.focused, const Duration(seconds: 5));
      expect(alerts.warnings, 0);

      session.dispose();
    });

    test('ignores the sensors while paused', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      session.pause();

      await feed.emit(FakeSensorFeed.grabbed);

      expect(session.stage, SessionStage.paused);
      expect(session.interruptions, 0);

      session.dispose();
    });

    test('resuming asks for the phone to be put back down', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      session.pause();
      session.resume();

      expect(session.stage, SessionStage.arming);

      await settle(session);
      expect(session.stage, SessionStage.focusing);

      session.dispose();
    });

    test('pausing an interrupted session stops the alarm', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await feed.emit(FakeSensorFeed.grabbed);
      final warnings = alerts.warnings;

      session.pause();
      await ticker.tick(3);

      expect(alerts.warnings, warnings);

      session.dispose();
    });
  });

  group('stopping', () {
    test('keeps the credits earned so far', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await ticker.tick(90);

      session.stop();

      expect(session.stage, SessionStage.complete);
      expect(completed.single.completed, isFalse);
      expect(completed.single.focused, const Duration(seconds: 90));
      expect(
        completed.single.creditsEarned,
        closeTo(CreditRules.baseCreditsPerMinute * 1.5, 1e-9),
      );
      expect(alerts.finishes, 0);

      session.dispose();
    });

    test('reports the session only once', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);

      session.stop();
      session.stop();

      expect(completed, hasLength(1));

      session.dispose();
    });

    test('counts the pick-ups it saw', () async {
      final session = build(target: const Duration(minutes: 5));
      await settle(session);
      await feed.emit(FakeSensorFeed.grabbed);
      await feed.emit(FakeSensorFeed.still);
      clock.advance(SessionController.resumeDelay + const Duration(milliseconds: 1));
      await feed.emit(FakeSensorFeed.still);
      await feed.emit(FakeSensorFeed.grabbed);

      session.stop();

      expect(completed.single.interruptions, 2);
      expect(completed.single.clean, isFalse);

      session.dispose();
    });
  });

  test('disposing releases the sensor feed', () async {
    final session = build();
    session.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(feed.disposed, isTrue);
  });

  tearDown(() async => ticker.close());
}
