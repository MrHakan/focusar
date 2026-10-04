import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/desk_calibration.dart';
import 'package:focusar/domain/motion_guard.dart';
import 'package:focusar/state/calibration_controller.dart';

import 'support/fake_session.dart';

void main() {
  late FakeSensorFeed feed;
  late RecordingAlerts alerts;
  late ManualClock clock;
  late CalibrationController calibration;

  setUp(() {
    feed = FakeSensorFeed();
    alerts = RecordingAlerts();
    clock = ManualClock();
    calibration = CalibrationController(
      feed: feed,
      alerts: alerts,
      clock: clock.call,
    )..start();
  });

  tearDown(() => calibration.dispose());

  /// Feeds still samples every 20 ms for [duration].
  Future<void> hold(Duration duration) async {
    for (var ms = 0; ms < duration.inMilliseconds; ms += 20) {
      await feed.emit(FakeSensorFeed.still);
      clock.advance(const Duration(milliseconds: 20));
    }
    await feed.emit(FakeSensorFeed.still);
  }

  test('waits for the phone to lie face-down', () async {
    await feed.emit(FakeSensorFeed.lifted);

    expect(calibration.stage, CalibrationStage.waiting);
    expect(alerts.starts, 0);
  });

  test('starts recording once the phone settles, and buzzes', () async {
    await hold(CalibrationController.settleDelay);

    expect(calibration.stage, CalibrationStage.measuring);
    expect(alerts.starts, 1);
  });

  test('finishes after the recording and suggests a level', () async {
    await hold(CalibrationController.settleDelay);
    await hold(DeskCalibration.duration);

    expect(calibration.stage, CalibrationStage.done);
    expect(calibration.progress, 1);
    expect(calibration.result!.recommended, Sensitivity.strict);
    expect(alerts.finishes, 1);
  });

  test('turning the phone over early starts again', () async {
    await hold(CalibrationController.settleDelay);
    await hold(const Duration(seconds: 3));

    await feed.emit(FakeSensorFeed.lifted);

    expect(calibration.stage, CalibrationStage.waiting);
    expect(calibration.pickedUpEarly, isTrue);
    expect(calibration.progress, 0);

    await hold(CalibrationController.settleDelay);
    expect(calibration.stage, CalibrationStage.measuring);
    expect(calibration.pickedUpEarly, isFalse);
  });

  test('restart throws the result away', () async {
    await hold(CalibrationController.settleDelay);
    await hold(DeskCalibration.duration);

    calibration.restart();

    expect(calibration.stage, CalibrationStage.waiting);
    expect(calibration.result, isNull);
  });

  test('disposing releases the sensor feed', () async {
    final localFeed = FakeSensorFeed();
    CalibrationController(feed: localFeed, alerts: alerts)
      ..start()
      ..dispose();
    await Future<void>.delayed(Duration.zero);

    expect(localFeed.disposed, isTrue);
  });
}
