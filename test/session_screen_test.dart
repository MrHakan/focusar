import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/state/session_controller.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:focusar/state/wallet_scope.dart';
import 'package:focusar/theme/app_theme.dart';
import 'package:focusar/ui/screens/session_screen.dart';
import 'package:focusar/ui/widgets/focus_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSensorFeed feed;
  late FakeTicker ticker;
  late ManualClock clock;
  late WalletController wallet;

  setUp(() async {
    feed = FakeSensorFeed();
    ticker = FakeTicker();
    clock = ManualClock();
    SharedPreferences.setMockInitialValues({});
    wallet = WalletController(store: await FocusStore.open());
  });

  tearDown(() async => ticker.close());

  Future<void> pumpSession(
    WidgetTester tester, {
    FocusMode mode = FocusMode.timed,
    Duration target = const Duration(minutes: 25),
  }) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      WalletScope(
        controller: wallet,
        child: MaterialApp(
          theme: buildFocusTheme(),
          home: SessionScreen(
            config: SessionConfig(
              mode: mode,
              method: PlacementMethod.motionOnly,
              target: target,
            ),
            feed: feed,
            ticker: ticker.call,
            clock: clock.call,
            alerts: RecordingAlerts(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Puts the phone down and lets the arming delay elapse.
  Future<void> settle(WidgetTester tester) async {
    feed.add(FakeSensorFeed.still);
    await tester.pump();
    clock.advance(SessionController.armDelay + const Duration(milliseconds: 1));
    feed.add(FakeSensorFeed.still);
    await tester.pump();
  }

  Future<void> run(WidgetTester tester, int seconds) async {
    ticker.beat(seconds);
    await tester.pump();
  }

  testWidgets('asks for the phone before it starts', (tester) async {
    await pumpSession(tester);

    expect(find.text('Ready when you are'), findsOneWidget);
    expect(find.text('MOTION SENSOR'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
  });

  testWidgets('locks in once the phone settles', (tester) async {
    await pumpSession(tester);
    await settle(tester);

    expect(find.text('Locked in'), findsOneWidget);
    expect(find.text('Keep your phone still.'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('an open block earns screen time on the card', (tester) async {
    await pumpSession(tester, mode: FocusMode.openEnded);
    await settle(tester);
    await run(tester, 60);

    expect(find.text('Earning screen time'), findsOneWidget);
    expect(find.text('Earning screen time...'), findsOneWidget);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.byType(FocusCard), findsOneWidget);
    expect(find.text('1.00'), findsOneWidget);
    expect(find.text('+ 1m screen time'), findsOneWidget);
  });

  testWidgets('scolds a picked-up phone', (tester) async {
    await pumpSession(tester);
    await settle(tester);
    feed.add(FakeSensorFeed.grabbed);
    await tester.pump();

    expect(find.text('No phone allowed'), findsOneWidget);
    expect(find.text("You're not done. Get back to work."), findsOneWidget);
    expect(find.text('Keep me still'), findsOneWidget);
    expect(find.text('TIMER PAUSED'), findsOneWidget);
  });

  testWidgets('pause holds the clock and resume asks for the phone again',
      (tester) async {
    await pumpSession(tester);
    await settle(tester);
    await run(tester, 5);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Paused'), findsOneWidget);

    await run(tester, 10);
    expect(find.text('24:55'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.text('Ready when you are'), findsOneWidget);
  });

  testWidgets('shows the summary and banks the credits when it finishes',
      (tester) async {
    await pumpSession(tester, target: const Duration(minutes: 1));
    await settle(tester);
    await run(tester, 60);
    await tester.pumpAndSettle();

    expect(find.text('Focus complete'), findsOneWidget);
    expect(find.text('FOCUSED'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    expect(wallet.balance, closeTo(1.0, 1e-9));
    expect(wallet.sessionsCompleted, 1);
    expect(wallet.history, hasLength(1));
  });

  testWidgets('flags a coupon that is already waiting', (tester) async {
    await wallet.commit(
      SessionRecord(
        startedAt: clock(),
        focused: const Duration(minutes: 60),
        creditsEarned: 60,
        interruptions: 0,
        mode: FocusMode.timed,
        method: PlacementMethod.motionOnly,
        completed: true,
      ),
    );
    await wallet.redeem(const Duration(minutes: 15));

    await pumpSession(tester);

    expect(find.textContaining('Your coupon is waiting'), findsOneWidget);
  });
}
