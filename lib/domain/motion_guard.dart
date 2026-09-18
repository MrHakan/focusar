import 'dart:math' as math;

/// Tunable limits for [MotionGuard]. Kept separate so tests can tighten or
/// loosen the guard without touching the classification itself.
class MotionThresholds {
  const MotionThresholds({
    this.maxTiltDegrees = 34,
    this.gravityToleranceSettled = 1.4,
    this.gravityToleranceResting = 2.2,
    this.settledRotation = 0.55,
    this.settledAcceleration = 0.8,
    this.disturbedRotation = 0.9,
    this.disturbedAcceleration = 1.6,
    this.suddenRotation = 2.0,
    this.suddenAcceleration = 3.5,
  });

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
}

/// One classified sensor sample.
class MotionReading {
  const MotionReading({
    required this.faceDown,
    required this.settled,
    required this.disturbed,
    required this.sudden,
    required this.tiltDegrees,
    required this.stability,
  });

  /// The screen is pointing at the table.
  final bool faceDown;

  /// Face-down *and* still enough to start or resume a session.
  final bool settled;

  /// Moved, lifted, or tilted past what a resting phone does.
  final bool disturbed;

  /// A snatch or a swing — worth alarming on without waiting for debounce.
  final bool sudden;

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

  static const double gravity = 9.81;

  final MotionThresholds thresholds;

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
    final disturbed = !faceDown ||
        gravityError > thresholds.gravityToleranceResting ||
        rotationRate > thresholds.disturbedRotation ||
        userAcceleration > thresholds.disturbedAcceleration;

    return MotionReading(
      faceDown: faceDown,
      settled: settled,
      disturbed: disturbed,
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
