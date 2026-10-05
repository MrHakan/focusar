import 'dart:math' as math;

import 'motion_sample.dart';

/// How readily the guard calls a pick-up.
///
/// Desks shake — typing, a mug set down, a phone buzzing next to this one.
/// None of that turns the phone over, so every level treats shaking more
/// patiently than turning or tilting; the levels differ in how much shaking
/// they sit through before they alarm.
enum Sensitivity {
  /// Alarms on the slightest knock. For a quiet, solid desk.
  strict,

  /// Rides out typing and set-down cups. The default.
  balanced,

  /// For a wobbly table, a train, or a desk shared with a keyboard warrior.
  relaxed,
}

extension SensitivityLabels on Sensitivity {
  String get label => switch (this) {
        Sensitivity.strict => 'Strict',
        Sensitivity.balanced => 'Balanced',
        Sensitivity.relaxed => 'Relaxed',
      };

  String get blurb => switch (this) {
        Sensitivity.strict =>
          'Alarms on the slightest knock. Best on a solid, quiet desk.',
        Sensitivity.balanced =>
          'Rides out typing and a mug set down next to the phone.',
        Sensitivity.relaxed =>
          'For wobbly tables and busy desks. Still catches a pick-up.',
      };
}

/// Tunable limits for [MotionGuard]. Kept separate so tests can tighten or
/// loosen the guard without touching the classification itself. The plain
/// constructor is the [Sensitivity.balanced] set.
class MotionThresholds {
  const MotionThresholds({
    this.maxTiltDegrees = 36,
    this.gravityToleranceSettled = 1.6,
    this.gravityToleranceResting = 2.8,
    this.settledRotation = 0.6,
    this.settledAcceleration = 1.0,
    this.disturbedRotation = 1.0,
    this.disturbedAcceleration = 2.2,
    this.suddenRotation = 2.4,
    this.suddenAcceleration = 5.0,
    this.disturbanceGrace = const Duration(milliseconds: 250),
    this.shakeGrace = const Duration(milliseconds: 900),
  });

  /// The preset behind each [Sensitivity].
  factory MotionThresholds.forSensitivity(Sensitivity sensitivity) =>
      switch (sensitivity) {
        Sensitivity.strict => strict,
        Sensitivity.balanced => balanced,
        Sensitivity.relaxed => relaxed,
      };

  static const MotionThresholds strict = MotionThresholds(
    maxTiltDegrees: 34,
    gravityToleranceSettled: 1.4,
    gravityToleranceResting: 2.2,
    settledRotation: 0.55,
    settledAcceleration: 0.8,
    disturbedRotation: 0.9,
    disturbedAcceleration: 1.6,
    suddenRotation: 2.0,
    suddenAcceleration: 3.5,
    disturbanceGrace: Duration(milliseconds: 160),
    shakeGrace: Duration(milliseconds: 160),
  );

  static const MotionThresholds balanced = MotionThresholds();

  static const MotionThresholds relaxed = MotionThresholds(
    maxTiltDegrees: 40,
    gravityToleranceSettled: 2.0,
    gravityToleranceResting: 3.6,
    settledRotation: 0.7,
    settledAcceleration: 1.3,
    disturbedRotation: 1.2,
    disturbedAcceleration: 3.0,
    suddenRotation: 3.0,
    suddenAcceleration: 8.0,
    disturbanceGrace: Duration(milliseconds: 400),
    shakeGrace: Duration(seconds: 2),
  );

  /// How far the phone may lean from flat-on-its-face and still count.
  final double maxTiltDegrees;

  /// Allowed drift of the measured gravity magnitude from 9.81 m/s².
  final double gravityToleranceSettled;
  final double gravityToleranceResting;

  /// Ceilings for "it is genuinely still".
  final double settledRotation;
  final double settledAcceleration;

  /// Ceilings for "it has not been touched".
  final double disturbedRotation;
  final double disturbedAcceleration;

  /// Floors for "that was a grab, alarm immediately".
  final double suddenRotation;
  final double suddenAcceleration;

  /// How long the phone may stay turned or tilted before it is a pick-up.
  final Duration disturbanceGrace;

  /// How long it may shake in place — still face-down, not turning — before
  /// it is a pick-up. Vibration from the desk lives here.
  final Duration shakeGrace;
}

/// One classified sensor sample.
class MotionReading {
  const MotionReading({
    required this.faceDown,
    required this.settled,
    required this.displaced,
    required this.shaken,
    required this.sudden,
    required this.tiltDegrees,
    required this.stability,
  });

  /// The screen is pointing at the table.
  final bool faceDown;

  /// Face-down *and* still enough to start or resume a session.
  final bool settled;

  /// Turned over, tilted, or rotating — what a hand does to a phone.
  final bool displaced;

  /// Still face-down and not turning, but jolting about. What a desk does to
  /// a phone. Never set together with [displaced].
  final bool shaken;

  /// A snatch or a swing — worth alarming on without waiting for debounce.
  final bool sudden;

  /// Moved, lifted, or tilted past what a resting phone does.
  bool get disturbed => displaced || shaken;

  /// Angle between the measured gravity vector and straight-down-through-the-
  /// screen, in degrees. 0 is perfectly face-down.
  final double tiltDegrees;

  /// 0..1, how calm the sample is. Drives the ring in the session UI.
  final double stability;
}

/// Turns raw accelerometer, gyroscope, and linear-acceleration values into a
/// verdict on whether the phone is still lying face-down and untouched.
class MotionGuard {
  const MotionGuard({this.thresholds = const MotionThresholds()});

  MotionGuard.forSensitivity(Sensitivity sensitivity)
      : thresholds = MotionThresholds.forSensitivity(sensitivity);

  static const double gravity = 9.81;

  final MotionThresholds thresholds;

  MotionReading read(MotionSample sample) => evaluate(
        x: sample.x,
        y: sample.y,
        z: sample.z,
        rotationRate: sample.rotationRate,
        userAcceleration: sample.userAcceleration,
      );

  MotionReading evaluate({
    required double x,
    required double y,
    required double z,
    required double rotationRate,
    required double userAcceleration,
  }) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    final gravityError = (magnitude - gravity).abs();
    final tilt = _tiltDegrees(z, magnitude);

    final faceDown = tilt <= thresholds.maxTiltDegrees;
    final settled = faceDown &&
        gravityError < thresholds.gravityToleranceSettled &&
        rotationRate < thresholds.settledRotation &&
        userAcceleration < thresholds.settledAcceleration;
    final sudden = userAcceleration > thresholds.suddenAcceleration ||
        rotationRate > thresholds.suddenRotation;
    final displaced = !faceDown || rotationRate > thresholds.disturbedRotation;
    final shaken = !displaced &&
        (gravityError > thresholds.gravityToleranceResting ||
            userAcceleration > thresholds.disturbedAcceleration);

    return MotionReading(
      faceDown: faceDown,
      settled: settled,
      displaced: displaced,
      shaken: shaken,
      sudden: sudden,
      tiltDegrees: tilt,
      stability: _stability(rotationRate, userAcceleration, tilt),
    );
  }

  /// A face-down phone reads roughly (0, 0, -9.81), so the angle between the
  /// measured vector and -Z is the whole story about orientation.
  double _tiltDegrees(double z, double magnitude) {
    if (magnitude < 0.001) return 180;
    final cosine = (-z / magnitude).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  double _stability(double rotationRate, double userAcceleration, double tilt) {
    final rotationLoad = rotationRate / thresholds.suddenRotation;
    final accelerationLoad = userAcceleration / thresholds.suddenAcceleration;
    final tiltLoad = tilt / thresholds.maxTiltDegrees;
    final worst = math.max(rotationLoad, math.max(accelerationLoad, tiltLoad));
    return (1 - worst).clamp(0.0, 1.0);
  }
}

/// Decides, sample by sample, when a resting phone has been picked up.
///
/// A sudden reading alarms at once. Anything else has to last: a turned or
/// tilted phone for [MotionThresholds.disturbanceGrace], a phone that only
/// shakes in place for the longer [MotionThresholds.shakeGrace]. A single calm
/// sample forgives everything before it, which is what lets the on-and-off
/// buzz of a vibrating desk pass.
class PickupDetector {
  PickupDetector(this.thresholds);

  final MotionThresholds thresholds;

  DateTime? _disturbedSince;

  /// Returns `true` when [reading], taken at [now], completes a pick-up.
  bool observe(MotionReading reading, DateTime now) {
    if (reading.sudden) {
      reset();
      return true;
    }
    if (!reading.disturbed) {
      reset();
      return false;
    }
    final since = _disturbedSince ??= now;
    final grace =
        reading.displaced ? thresholds.disturbanceGrace : thresholds.shakeGrace;
    if (now.difference(since) < grace) return false;
    reset();
    return true;
  }

  void reset() => _disturbedSince = null;
}
