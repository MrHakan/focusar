import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/desk_calibration.dart';
import 'package:focusar/domain/motion_guard.dart';
import 'package:focusar/domain/motion_sample.dart';

/// A phone face-down on a desk, jolted by [acceleration] m/s².
MotionSample desk([double acceleration = 0.05, double rotation = 0.03]) =>
    MotionSample(
      x: 0,
      y: 0,
      z: -9.81,
      rotationRate: rotation,
      userAcceleration: acceleration,
    );

void main() {
  final start = DateTime(2026, 9, 14, 9);

  /// Records [DeskCalibration.duration] at 50 Hz, asking [sampleAt] what the
  /// desk felt like at each millisecond offset.
  CalibrationResult record(MotionSample Function(int ms) sampleAt) {
    final calibration = DeskCalibration();
    for (var ms = 0; ms <= DeskCalibration.duration.inMilliseconds; ms += 20) {
      calibration.add(sampleAt(ms), start.add(Duration(milliseconds: ms)));
    }
    return calibration.evaluate();
  }

  test('a quiet desk earns the strictest level', () {
    final result = record((_) => desk());

    expect(result.recommended, Sensitivity.strict);
    expect(result.falseAlarms.values, everyElement(0));
    expect(result.tooShaky, isFalse);
  });

  test('typing next to the phone suggests balanced', () {
    // 200 ms bursts of keyboard thump with 300 ms of quiet between.
    final result = record((ms) => ms % 500 < 200 ? desk(2.0) : desk());

    expect(result.falseAlarms[Sensitivity.strict], greaterThan(0));
    expect(result.falseAlarms[Sensitivity.balanced], 0);
    expect(result.recommended, Sensitivity.balanced);
  });

  test('a desk that never stops shaking needs relaxed', () {
    final result = record((_) => desk(2.0));

    expect(result.falseAlarms[Sensitivity.balanced], greaterThan(0));
    expect(result.falseAlarms[Sensitivity.relaxed], 0);
    expect(result.recommended, Sensitivity.relaxed);
    expect(result.tooShaky, isFalse);
  });

  test('says so when even relaxed would alarm', () {
    final result = record((_) => desk(4.0));

    expect(result.recommended, Sensitivity.relaxed);
    expect(result.tooShaky, isTrue);
  });

  test('replays with headroom, so a near miss does not pass', () {
    // Just under balanced's shake line when recorded, over it when replayed.
    final result = record((_) => desk(2.0));

    expect(result.falseAlarms[Sensitivity.balanced], greaterThan(0));
  });

  test('refuses to judge a phone that was not lying face-down', () {
    final result = record(
      (_) => const MotionSample(
        x: 0,
        y: 0,
        z: 9.81,
        rotationRate: 0.03,
        userAcceleration: 0.05,
      ),
    );

    expect(result.recommended, isNull);
    expect(result.isValid, isFalse);
    expect(result.faceDownShare, 0);
  });

  test('refuses to judge an empty recording', () {
    expect(DeskCalibration().evaluate().recommended, isNull);
  });

  test('reports the worst jolt and turn it felt', () {
    final result = record((ms) => ms == 400 ? desk(1.2, 0.4) : desk());

    expect(result.peakAcceleration, 1.2);
    expect(result.peakRotation, 0.4);
  });
}
