import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/app.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/focus_preferences.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:focusar/state/wallet_scope.dart';
import 'package:focusar/theme/app_theme.dart';
import 'package:focusar/ui/screens/session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WalletController wallet;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    wallet = WalletController(store: await FocusStore.open());
  });

  void usePhone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Quick start opens a real session, which listens to the real sensors.
  /// Give their channels something to talk to.
  void silenceSensors(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final name in ['accelerometer', 'user_accel', 'gyroscope']) {
      final channel = EventChannel('dev.fluttercommunity.plus/sensors/$name');
      messenger.setMockStreamHandler(channel, MockStreamHandler.inline(onListen: (_, __) {}));
      addTearDown(() => messenger.setMockStreamHandler(channel, null));
    }
    const method = MethodChannel('dev.fluttercommunity.plus/sensors/method');
    messenger.setMockMethodCallHandler(method, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(method, null));
  }

  test('the last config round-trips with the preferences', () {
    const config = SessionConfig(
      mode: FocusMode.openEnded,
      method: PlacementMethod.arZone,
      target: Duration(minutes: 45),
    );
    const preferences = FocusPreferences(lastConfig: config);

    final restored = FocusPreferences.fromJson(preferences.toJson());

    expect(restored.lastConfig, config);
    expect(FocusPreferences.fromJson(const {}).lastConfig, isNull);
  });

  testWidgets('a first launch has nothing to quick start', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(FocusArApp(wallet: wallet));

    expect(find.text('Quick start'), findsNothing);
  });

  testWidgets('starting a session remembers its settings', (tester) async {
    usePhone(tester);
    const config = SessionConfig(
      mode: FocusMode.timed,
      method: PlacementMethod.motionOnly,
      target: Duration(minutes: 45),
    );
    final ticker = FakeTicker();
    addTearDown(ticker.close);

    await tester.pumpWidget(
      WalletScope(
        controller: wallet,
        child: MaterialApp(
          theme: buildFocusTheme(),
          home: SessionScreen(
            config: config,
            feed: FakeSensorFeed(),
            ticker: ticker.call,
            alerts: RecordingAlerts(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(wallet.preferences.lastConfig, config);
    expect(
      WalletController(store: await FocusStore.open()).preferences.lastConfig,
      config,
    );
  });

  testWidgets('home offers the last settings and restores them on screen',
      (tester) async {
    usePhone(tester);
    await wallet.rememberConfig(
      const SessionConfig(
        mode: FocusMode.timed,
        method: PlacementMethod.motionOnly,
        target: Duration(minutes: 45),
      ),
    );

    await tester.pumpWidget(FocusArApp(wallet: wallet));

    expect(find.text('Quick start'), findsOneWidget);
    expect(find.text('Deep block · 45 min · Motion sensor'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '45 min'));
    expect(chip.selected, isTrue);
  });

  testWidgets('an open-ended AR session is summarised without a length',
      (tester) async {
    usePhone(tester);
    await wallet.rememberConfig(
      const SessionConfig(mode: FocusMode.openEnded, method: PlacementMethod.arZone),
    );

    await tester.pumpWidget(FocusArApp(wallet: wallet));

    expect(find.text('Earn screen time · AR zone'), findsOneWidget);
  });

  testWidgets('one tap starts the session', (tester) async {
    usePhone(tester);
    silenceSensors(tester);
    const config = SessionConfig(
      mode: FocusMode.timed,
      method: PlacementMethod.motionOnly,
      target: Duration(minutes: 60),
    );
    await wallet.rememberConfig(config);
    await tester.pumpWidget(FocusArApp(wallet: wallet));

    await tester.tap(find.text('Quick start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final session = tester.widget<SessionScreen>(find.byType(SessionScreen));
    expect(session.config, config);
    expect(find.text('Ready when you are'), findsOneWidget);

    // Leave the session screen so its timers stop with the test.
    await tester.pumpWidget(const SizedBox());
  });
}
