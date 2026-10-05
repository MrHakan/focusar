import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../domain/motion_sample.dart';

export '../domain/motion_sample.dart';

/// The source of motion samples for a session. Abstracted so tests can drive
/// the session machine from a plain stream.
abstract class SensorFeed {
  Stream<MotionSample> get samples;

  /// Releases any platform subscriptions. Safe to call more than once.
  Future<void> dispose();
}

/// Reads the real device sensors.
///
/// The three `sensors_plus` streams tick independently, so the gyroscope and
/// linear-accelerometer values are held and folded into each accelerometer
/// event. That keeps one sample rate — the orientation one — driving the
/// session instead of three racing each other.
class DeviceSensorFeed implements SensorFeed {
  DeviceSensorFeed({Duration? samplingPeriod})
      : _samplingPeriod = samplingPeriod ?? SensorInterval.gameInterval {
    _controller = StreamController<MotionSample>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  final Duration _samplingPeriod;
  late final StreamController<MotionSample> _controller;

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<UserAccelerometerEvent>? _userAccelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;

  double _rotationRate = 0;
  double _userAcceleration = 0;

  @override
  Stream<MotionSample> get samples => _controller.stream;

  void _start() {
    _gyroscope = gyroscopeEventStream(samplingPeriod: _samplingPeriod).listen(
      (event) => _rotationRate = _magnitude(event.x, event.y, event.z),
    );
    _userAccelerometer =
        userAccelerometerEventStream(samplingPeriod: _samplingPeriod).listen(
      (event) => _userAcceleration = _magnitude(event.x, event.y, event.z),
    );
    _accelerometer =
        accelerometerEventStream(samplingPeriod: _samplingPeriod).listen((event) {
      if (_controller.isClosed) return;
      _controller.add(
        MotionSample(
          x: event.x,
          y: event.y,
          z: event.z,
          rotationRate: _rotationRate,
          userAcceleration: _userAcceleration,
        ),
      );
    });
  }

  Future<void> _stop() async {
    await _accelerometer?.cancel();
    await _userAccelerometer?.cancel();
    await _gyroscope?.cancel();
    _accelerometer = null;
    _userAccelerometer = null;
    _gyroscope = null;
  }

  @override
  Future<void> dispose() async {
    await _stop();
    if (!_controller.isClosed) await _controller.close();
  }

  static double _magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);
}
