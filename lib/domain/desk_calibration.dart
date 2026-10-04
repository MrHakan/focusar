import 'dart:math' as math;

import 'motion_guard.dart';
import 'motion_sample.dart';

/// What a few seconds of a phone lying on a working desk say about that desk.
class CalibrationResult {
  const CalibrationResult({
    required this.recommended,
    required this.falseAlarms,
    required this.faceDownShare,
    required this.peakAcceleration,
    required this.peakRotation,
  });

  /// The strictest level that sat through the recording without a false
  /// alarm, or `null` when the phone was not lying face-down long enough to
  /// say anything.
  final Sensitivity? recommended;

  /// Pick-ups each level would have wrongly called during the recording.
  final Map<Sensitivity, int> falseAlarms;

  /// 0..1, how much of the recording the phone spent face-down.
  final double faceDownShare;

  /// The worst jolt seen, m/s² with gravity removed.
  final double peakAcceleration;

  /// The fastest turn seen, rad/s.
  final double peakRotation;

  bool get isValid => recommended != null;

  /// Even the most forgiving level would have alarmed on this desk.
  bool get tooShaky =>
      recommended == Sensitivity.relaxed &&
      falseAlarms[Sensitivity.relaxed]! > 0;
}

/// Records a phone lying face-down on a desk while the person works, then
/// replays the recording through every [Sensitivity] to find the strictest
/// one that would not have alarmed.
///
/// The replay uses the very [MotionGuard] and [PickupDetector] a session
/// uses, so the recommendation is about this desk rather than a rule of thumb.
/// Each sample is replayed a little harder than it was recorded, so a level
/// that only just coped is not recommended.
class DeskCalibration {
  DeskCalibration();

  /// How long to listen. Long enough to catch some typing.
  static const Duration duration = Duration(seconds: 8);

  /// Headroom: the replay scales movement up by this much.
  static const double headroom = 1.25;

  /// Below this share of face-down samples the recording is not a desk.
  static const double minFaceDownShare = 0.9;

  final List<({DateTime at, MotionSample sample})> _samples = [];

  int get sampleCount => _samples.length;

  void add(MotionSample sample, DateTime at) =>
      _samples.add((at: at, sample: sample));

  void clear() => _samples.clear();

  CalibrationResult evaluate() {
    final falseAlarms = {
      for (final level in Sensitivity.values) level: _replay(level),
    };
    final faceDownShare = _faceDownShare();

    Sensitivity? recommended;
    if (_samples.isNotEmpty && faceDownShare >= minFaceDownShare) {
      recommended = Sensitivity.relaxed;
      for (final level in Sensitivity.values) {
        if (falseAlarms[level] == 0) {
          recommended = level;
          break;
        }
      }
    }

    return CalibrationResult(
      recommended: recommended,
      falseAlarms: falseAlarms,
      faceDownShare: faceDownShare,
      peakAcceleration: _samples.fold(
          0.0, (peak, s) => math.max(peak, s.sample.userAcceleration)),
      peakRotation: _samples.fold(
          0.0, (peak, s) => math.max(peak, s.sample.rotationRate)),
    );
  }

  int _replay(Sensitivity level) {
    final guard = MotionGuard.forSensitivity(level);
    final detector = PickupDetector(guard.thresholds);
    var alarms = 0;
    for (final entry in _samples) {
      final sample = entry.sample;
      final reading = guard.evaluate(
        x: sample.x,
        y: sample.y,
        z: sample.z,
        rotationRate: sample.rotationRate * headroom,
        userAcceleration: sample.userAcceleration * headroom,
      );
      if (detector.observe(reading, entry.at)) alarms += 1;
    }
    return alarms;
  }

  double _faceDownShare() {
    if (_samples.isEmpty) return 0;
    const guard = MotionGuard(thresholds: MotionThresholds.relaxed);
    final faceDown =
        _samples.where((entry) => guard.read(entry.sample).faceDown).length;
    return faceDown / _samples.length;
  }
}
