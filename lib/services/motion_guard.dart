import 'dart:math' as math;

class MotionReading {
  const MotionReading({
    required this.faceDown,
    required this.settled,
    required this.pickedUp,
    required this.suddenMotion,
  });

  final bool faceDown;
  final bool settled;
  final bool pickedUp;
  final bool suddenMotion;
}

class MotionGuard {
  static const _gravity = 9.81;

  MotionReading evaluate({
    required double x,
    required double y,
    required double z,
    required double rotationRate,
    required double userAcceleration,
  }) {
    final measuredGravity = math.sqrt(x * x + y * y + z * z);
    final gravityError = (measuredGravity - _gravity).abs();
    final faceDown = z < -6.5 && x.abs() < 5.5 && y.abs() < 5.5;
    final settled = faceDown &&
        gravityError < 1.4 &&
        rotationRate < 0.55 &&
        userAcceleration < 0.8;
    final suddenMotion = userAcceleration > 3.5 || rotationRate > 2.0;
    final pickedUp = !faceDown ||
        gravityError > 2.2 ||
        rotationRate > 0.9 ||
        userAcceleration > 1.6;

    return MotionReading(
      faceDown: faceDown,
      settled: settled,
      pickedUp: pickedUp,
      suddenMotion: suddenMotion,
    );
  }
}
