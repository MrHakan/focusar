import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/services/focus_timer.dart';
import 'package:focusar/services/motion_guard.dart';

void main() {
  test('focus clock counts down only while active', () {
    final timer = FocusTimer(const Duration(seconds: 2));

    timer.tick(paused: false);
    expect(timer.remainingSeconds, 1);

    timer.tick(paused: true);
    expect(timer.remainingSeconds, 1);

    timer.tick(paused: false);
    expect(timer.isComplete, isTrue);
  });

  test('clock formatting supports short and long sessions', () {
    expect(formatClock(65), '01:05');
    expect(formatClock(3661), '01:01:01');
  });

  group('motion guard', () {
    final guard = MotionGuard();

    test('accepts a still face-down phone', () {
      final reading = guard.evaluate(
        x: 0,
        y: 0,
        z: -9.81,
        rotationRate: 0.1,
        userAcceleration: 0.2,
      );

      expect(reading.faceDown, isTrue);
      expect(reading.settled, isTrue);
      expect(reading.pickedUp, isFalse);
    });

    test('detects a face-down phone being accelerated', () {
      final reading = guard.evaluate(
        x: 0,
        y: 0,
        z: -9.81,
        rotationRate: 0.2,
        userAcceleration: 3.8,
      );

      expect(reading.settled, isFalse);
      expect(reading.pickedUp, isTrue);
      expect(reading.suddenMotion, isTrue);
    });

    test('detects a phone that is no longer face-down', () {
      final reading = guard.evaluate(
        x: 9.81,
        y: 0,
        z: 0,
        rotationRate: 0.1,
        userAcceleration: 0.1,
      );

      expect(reading.faceDown, isFalse);
      expect(reading.pickedUp, isTrue);
    });
  });
}
