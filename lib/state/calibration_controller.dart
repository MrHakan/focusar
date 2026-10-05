import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sensor_feed.dart';
import '../domain/desk_calibration.dart';
import '../domain/motion_guard.dart';
import 'session_alerts.dart';

enum CalibrationStage {
  /// Waiting for the phone to be put face-down on the desk.
  waiting,

  /// Recording the desk while the person works.
  measuring,

  /// The recording is in and a level has been suggested.
  done,
}

/// Runs one desk calibration: waits for the phone to go face-down, records
/// [DeskCalibration.duration] of the desk, and buzzes when it is done so the
/// person knows to turn the phone back over.
class CalibrationController extends ChangeNotifier {
  CalibrationController({
    required SensorFeed feed,
    SessionAlerts alerts = const PlatformAlerts(),
    DateTime Function()? clock,
  })  : _feed = feed,
        _alerts = alerts,
        _now = clock ?? DateTime.now;

  /// How long the phone has to lie face-down before recording starts, so the
  /// act of putting it down is not part of the recording.
  static const Duration settleDelay = Duration(seconds: 1);

  /// The most forgiving guard decides what counts as lying face-down here:
  /// the desk being measured may well be a shaky one.
  static const MotionGuard _placement =
      MotionGuard(thresholds: MotionThresholds.relaxed);

  final SensorFeed _feed;
  final SessionAlerts _alerts;
  final DateTime Function() _now;
  final DeskCalibration _calibration = DeskCalibration();

  StreamSubscription<MotionSample>? _samples;
  CalibrationStage _stage = CalibrationStage.waiting;
  DateTime? _faceDownSince;
  DateTime? _measuringSince;
  double _progress = 0;
  bool _pickedUpEarly = false;
  CalibrationResult? _result;

  CalibrationStage get stage => _stage;

  /// 0..1 through the recording.
  double get progress => _progress;

  /// The phone was turned over before the recording finished, and it
  /// started again.
  bool get pickedUpEarly => _pickedUpEarly;

  CalibrationResult? get result => _result;

  void start() {
    _samples ??= _feed.samples.listen(_onSample);
  }

  /// Throws the result away and waits for the phone again.
  void restart() {
    _calibration.clear();
    _stage = CalibrationStage.waiting;
    _faceDownSince = null;
    _measuringSince = null;
    _progress = 0;
    _pickedUpEarly = false;
    _result = null;
    notifyListeners();
  }

  void _onSample(MotionSample sample) {
    final now = _now();
    switch (_stage) {
      case CalibrationStage.waiting:
        final reading = _placement.read(sample);
        if (!reading.faceDown || reading.displaced) {
          _faceDownSince = null;
          return;
        }
        final since = _faceDownSince ??= now;
        if (now.difference(since) < settleDelay) return;
        _stage = CalibrationStage.measuring;
        _measuringSince = now;
        _pickedUpEarly = false;
        _alerts.started();
        notifyListeners();
      case CalibrationStage.measuring:
        if (!_placement.read(sample).faceDown) {
          _calibration.clear();
          _stage = CalibrationStage.waiting;
          _faceDownSince = null;
          _progress = 0;
          _pickedUpEarly = true;
          notifyListeners();
          return;
        }
        _calibration.add(sample, now);
        final elapsed = now.difference(_measuringSince ?? now);
        final progress =
            (elapsed.inMilliseconds / DeskCalibration.duration.inMilliseconds)
                .clamp(0.0, 1.0);
        if (progress >= 1) {
          _finish();
        } else if ((progress - _progress) >= 0.02) {
          _progress = progress;
          notifyListeners();
        }
      case CalibrationStage.done:
        break;
    }
  }

  void _finish() {
    _progress = 1;
    _result = _calibration.evaluate();
    _stage = CalibrationStage.done;
    _alerts.finished();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_samples?.cancel());
    unawaited(_feed.dispose());
    super.dispose();
  }
}
