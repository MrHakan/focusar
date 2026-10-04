import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/motion_guard.dart';
import 'package:focusar/domain/motion_sample.dart';

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
    final reading = read(userAcceleration: 5.5);

    expect(reading.faceDown, isTrue);
    expect(reading.sudden, isTrue);
    expect(reading.disturbed, isTrue);
    expect(reading.settled, isFalse);
  });

  test('flags a fast twist as sudden', () {
    final reading = read(rotationRate: 2.6);

    expect(reading.sudden, isTrue);
    expect(reading.settled, isFalse);
  });

  test('treats a nudge as disturbed but not sudden', () {
    final reading = read(userAcceleration: 2.6);

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

  group('shaking and displacement', () {
    test('a jolt that leaves the phone face-down is a shake', () {
      final reading = read(userAcceleration: 2.6);

      expect(reading.shaken, isTrue);
      expect(reading.displaced, isFalse);
      expect(reading.disturbed, isTrue);
    });

    test('a turned or tilted phone is displaced, never merely shaken', () {
      final turning = read(rotationRate: 1.4, userAcceleration: 2.6);
      final tipped = read(x: 7.0, z: -6.9, userAcceleration: 2.6);

      expect(turning.displaced, isTrue);
      expect(turning.shaken, isFalse);
      expect(tipped.displaced, isTrue);
      expect(tipped.shaken, isFalse);
    });

    test('reads a sample the same as its raw values', () {
      const sample = MotionSample(
        x: 1,
        y: 0,
        z: -9.7,
        rotationRate: 0.3,
        userAcceleration: 0.4,
      );

      final reading = guard.read(sample);

      expect(reading.tiltDegrees, read(x: 1, z: -9.7).tiltDegrees);
      expect(reading.settled, isTrue);
    });
  });

  group('sensitivity presets', () {
    test('the plain thresholds are the balanced level', () {
      final balanced = MotionThresholds.forSensitivity(Sensitivity.balanced);

      expect(balanced.disturbedAcceleration,
          const MotionThresholds().disturbedAcceleration);
      expect(balanced.shakeGrace, const MotionThresholds().shakeGrace);
    });

    test('loosen in order from strict to relaxed', () {
      final levels =
          Sensitivity.values.map(MotionThresholds.forSensitivity).toList();

      for (var i = 1; i < levels.length; i++) {
        final tighter = levels[i - 1];
        final looser = levels[i];
        expect(looser.disturbedAcceleration,
            greaterThan(tighter.disturbedAcceleration));
        expect(
            looser.suddenAcceleration, greaterThan(tighter.suddenAcceleration));
        expect(looser.suddenRotation, greaterThan(tighter.suddenRotation));
        expect(looser.shakeGrace, greaterThan(tighter.shakeGrace));
        expect(looser.disturbanceGrace, greaterThan(tighter.disturbanceGrace));
      }
    });

    test('every level forgives a shake longer than a turn', () {
      for (final level in Sensitivity.values) {
        final thresholds = MotionThresholds.forSensitivity(level);
        expect(thresholds.shakeGrace,
            greaterThanOrEqualTo(thresholds.disturbanceGrace));
      }
    });

    test('a knock that alarms a strict guard is only a shake when relaxed', () {
      final strict = MotionGuard.forSensitivity(Sensitivity.strict);
      final relaxed = MotionGuard.forSensitivity(Sensitivity.relaxed);

      MotionReading knock(MotionGuard guard) => guard.evaluate(
            x: 0,
            y: 0,
            z: -9.81,
            rotationRate: 0.2,
            userAcceleration: 4.5,
          );

      expect(knock(strict).sudden, isTrue);
      expect(knock(relaxed).sudden, isFalse);
      expect(knock(relaxed).shaken, isTrue);
    });
  });

  group('pick-up detector', () {
    final start = DateTime(2026, 9, 14, 9);
    DateTime at(int milliseconds) =>
        start.add(Duration(milliseconds: milliseconds));

    test('a sudden reading alarms at once', () {
      final detector = PickupDetector(const MotionThresholds());

      expect(detector.observe(read(userAcceleration: 6), start), isTrue);
    });

    test('a turned phone alarms after the short grace', () {
      const thresholds = MotionThresholds();
      final detector = PickupDetector(thresholds);
      final lifted = read(z: 9.81);
      final grace = thresholds.disturbanceGrace.inMilliseconds;

      expect(detector.observe(lifted, at(0)), isFalse);
      expect(detector.observe(lifted, at(grace - 10)), isFalse);
      expect(detector.observe(lifted, at(grace)), isTrue);
    });

    test('a shaking desk gets the longer grace', () {
      const thresholds = MotionThresholds();
      final detector = PickupDetector(thresholds);
      final shake = read(userAcceleration: 2.6);

      expect(detector.observe(shake, at(0)), isFalse);
      expect(
        detector.observe(
            shake, at(thresholds.disturbanceGrace.inMilliseconds * 2)),
        isFalse,
      );
      expect(detector.observe(shake, at(thresholds.shakeGrace.inMilliseconds)),
          isTrue);
    });

    test('an on-and-off buzz never adds up to a pick-up', () {
      final detector = PickupDetector(const MotionThresholds());
      final buzz = read(userAcceleration: 2.6);
      final calm = read();
      var alarms = 0;

      for (var ms = 0; ms < 10000; ms += 20) {
        final reading = (ms ~/ 200).isEven ? buzz : calm;
        if (detector.observe(reading, at(ms))) alarms++;
      }

      expect(alarms, 0);
    });

    test('a shake that turns into a tilt alarms on the short grace', () {
      const thresholds = MotionThresholds();
      final detector = PickupDetector(thresholds);

      detector.observe(read(userAcceleration: 2.6), at(0));
      final alarmed = detector.observe(
        read(x: 7.0, z: -6.9),
        at(thresholds.disturbanceGrace.inMilliseconds),
      );

      expect(alarmed, isTrue);
    });
  });
}
