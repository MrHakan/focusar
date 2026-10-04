import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/desk_calibration.dart';
import 'package:focusar/domain/motion_guard.dart';
import 'package:focusar/state/calibration_controller.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:focusar/state/wallet_scope.dart';
import 'package:focusar/theme/app_theme.dart';
import 'package:focusar/ui/screens/calibration_screen.dart';
import 'package:focusar/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WalletController wallet;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    wallet = WalletController(store: await FocusStore.open());
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WalletScope(
        controller: wallet,
        child: MaterialApp(theme: buildFocusTheme(), home: home),
      ),
    );
    await tester.pump();
  }

  testWidgets('defaults to balanced and saves a new choice', (tester) async {
    await pump(tester, const SettingsScreen());

    expect(wallet.preferences.sensitivity, Sensitivity.balanced);
    for (final level in Sensitivity.values) {
      expect(find.text(level.label), findsOneWidget);
    }

    await tester.tap(find.text('Relaxed'));
    await tester.pump();

    expect(wallet.preferences.sensitivity, Sensitivity.relaxed);
    final reloaded = WalletController(store: await FocusStore.open());
    expect(reloaded.preferences.sensitivity, Sensitivity.relaxed);
  });

  testWidgets('a reset keeps the sensitivity', (tester) async {
    await wallet.setSensitivity(Sensitivity.strict);

    await wallet.reset();

    expect(
      WalletController(store: await FocusStore.open()).preferences.sensitivity,
      Sensitivity.strict,
    );
  });

  testWidgets('calibration suggests a level and applies it', (tester) async {
    final feed = FakeSensorFeed();
    final clock = ManualClock();
    await pump(
      tester,
      CalibrationScreen(
          feed: feed, alerts: RecordingAlerts(), clock: clock.call),
    );

    expect(find.text('Put the phone face-down'), findsOneWidget);

    final total = CalibrationController.settleDelay + DeskCalibration.duration;
    for (var ms = 0; ms <= total.inMilliseconds + 40; ms += 20) {
      feed.add(FakeSensorFeed.still);
      await tester.pump();
      clock.advance(const Duration(milliseconds: 20));
    }
    await tester.pump();

    expect(find.text('Suggested: Strict'), findsOneWidget);
    expect(find.text('FALSE ALARMS ON THIS DESK'), findsOneWidget);

    await tester.tap(find.text('Use Strict'));
    await tester.pump();

    expect(wallet.preferences.sensitivity, Sensitivity.strict);
  });
}
