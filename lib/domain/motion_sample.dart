/// One combined sample: orientation from the accelerometer, plus the latest
/// movement figures from the gyroscope and the linear accelerometer.
class MotionSample {
  const MotionSample({
    required this.x,
    required this.y,
    required this.z,
    required this.rotationRate,
    required this.userAcceleration,
  });

  /// Gravity-inclusive acceleration, m/s².
  final double x;
  final double y;
  final double z;

  /// Magnitude of the rotation vector, rad/s.
  final double rotationRate;

  /// Magnitude of the acceleration with gravity removed, m/s².
  final double userAcceleration;
}
