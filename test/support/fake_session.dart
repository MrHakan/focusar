import 'dart:async';

import 'package:focusar/data/sensor_feed.dart';
import 'package:focusar/state/session_alerts.dart';

/// A sensor feed driven by the test instead of by hardware.
class FakeSensorFeed implements SensorFeed {
  final StreamController<MotionSample> _controller =
      StreamController<MotionSample>.broadcast();

  bool disposed = false;

  @override
  Stream<MotionSample> get samples => _controller.stream;

  /// A phone lying flat and untouched.
  static const MotionSample still = MotionSample(
    x: 0,
    y: 0,
    z: -9.81,
    rotationRate: 0.05,
    userAcceleration: 0.05,
  );

  /// A phone that has been picked up and turned over.
  static const MotionSample lifted = MotionSample(
    x: 0,
    y: 0,
    z: 9.81,
    rotationRate: 0.4,
    userAcceleration: 1.0,
  );

  /// A phone that was snatched off the desk.
  static const MotionSample grabbed = MotionSample(
    x: 0,
    y: 0,
    z: -9.81,
    rotationRate: 0.2,
    userAcceleration: 6.0,
  );

  /// Queues a sample. Listeners see it on the next microtask, so widget tests
  /// follow this with a pump.
  void add(MotionSample sample) => _controller.add(sample);

  /// Queues a sample and waits for it to land. Plain unit tests only — inside
  /// `testWidgets` the clock is faked, so pump the tester instead.
  Future<void> emit(MotionSample sample) async {
    add(sample);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

/// A heartbeat the test advances by hand.
class FakeTicker {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> call(Duration interval) => _controller.stream;

  /// Beats the heartbeat. Widget tests pump the tester afterwards.
  void beat([int times = 1]) {
    for (var i = 0; i < times; i++) {
      _controller.add(null);
    }
  }

  /// Beats and waits for each beat to be handled. Plain unit tests only.
  Future<void> tick([int times = 1]) async {
    for (var i = 0; i < times; i++) {
      _controller.add(null);
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

/// Counts the nudges a session asked for.
class RecordingAlerts extends SessionAlerts {
  int starts = 0;
  int warnings = 0;
  int finishes = 0;

  @override
  void started() => starts++;

  @override
  void warn() => warnings++;

  @override
  void finished() => finishes++;
}

/// A clock the test moves forward, so placement delays need no real waiting.
class ManualClock {
  DateTime _now = DateTime(2026, 9, 14, 9);

  DateTime call() => _now;

  void advance(Duration amount) => _now = _now.add(amount);
}
