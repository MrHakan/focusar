import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/motion_guard.dart';

void main() {
  const guard = MotionGuard();

  MotionReading read({
    double x = 0,
    double y = 0,
    double z = -9.81,
    double rotationRate = 0.1,
    double userAcceleration = 0.1,
  }) =>
      guard.evaluate(
        x: x,
        y: y,
        z: z,
        rotationRate: rotationRate,
        userAcceleration: userAcceleration,
      );

  test('accepts a still phone lying on its face', () {
    final reading = read();

    expect(reading.faceDown, isTrue);
    expect(reading.settled, isTrue);
    expect(reading.disturbed, isFalse);
    expect(reading.sudden, isFalse);
    expect(reading.tiltDegrees, closeTo(0, 1e-6));
    expect(reading.stability, greaterThan(0.9));
  });

  test('tolerates a phone resting on a slightly uneven surface', () {
    final reading = read(x: 2.0, z: -9.6);

    expect(reading.faceDown, isTrue);
    expect(reading.settled, isTrue);
  });

  test('rejects a phone tipped past the limit', () {
    final reading = read(x: 7.0, z: -6.9);

    expect(reading.tiltDegrees, greaterThan(34));
    expect(reading.faceDown, isFalse);
    expect(reading.disturbed, isTrue);
  });

  test('calls a face-up phone disturbed', () {
    final reading = read(z: 9.81);

    expect(reading.tiltDegrees, closeTo(180, 1e-6));
    expect(reading.faceDown, isFalse);
    expect(reading.settled, isFalse);
    expect(reading.disturbed, isTrue);
  });

  test('flags a snatch as sudden even while still face-down', () {
    final reading = read(userAcceleration: 3.8);

    expect(reading.faceDown, isTrue);
    expect(reading.sudden, isTrue);
    expect(reading.disturbed, isTrue);
    expect(reading.settled, isFalse);
  });

  test('flags a fast twist as sudden', () {
    final reading = read(rotationRate: 2.4);

    expect(reading.sudden, isTrue);
    expect(reading.settled, isFalse);
  });

  test('treats a nudge as disturbed but not sudden', () {
    final reading = read(userAcceleration: 1.9);

    expect(reading.disturbed, isTrue);
    expect(reading.sudden, isFalse);
  });

  test('stability falls as the phone is handled', () {
    final calm = read().stability;
    final jostled = read(rotationRate: 1.4, userAcceleration: 2.0).stability;

    expect(jostled, lessThan(calm));
    expect(jostled, inInclusiveRange(0, 1));
  });

  test('survives a dead accelerometer without dividing by zero', () {
    final reading = read(z: 0);

    expect(reading.tiltDegrees, 180);
    expect(reading.faceDown, isFalse);
  });

  test('honours a custom threshold set', () {
    const strict = MotionGuard(thresholds: MotionThresholds(maxTiltDegrees: 5));
    final reading = strict.evaluate(
      x: 2.0,
      y: 0,
      z: -9.6,
      rotationRate: 0.1,
      userAcceleration: 0.1,
    );

    expect(reading.faceDown, isFalse);
  });
}
