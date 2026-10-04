import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/app.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:focusar/state/wallet_scope.dart';
import 'package:focusar/theme/app_theme.dart';
import 'package:focusar/ui/screens/progress_screen.dart';
import 'package:focusar/ui/widgets/week_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ManualClock starts on Monday 14 September 2026, 09:00.
  late ManualClock clock;
  late WalletController wallet;

  SessionRecord session(DateTime at, Duration focused, {int interruptions = 0}) =>
      SessionRecord(
        startedAt: at,
        focused: focused,
        creditsEarned: focused.inSeconds / 60,
        interruptions: interruptions,
        mode: FocusMode.timed,
        method: PlacementMethod.motionOnly,
        completed: true,
      );

  setUp(() async {
    clock = ManualClock()..advance(const Duration(days: 2)); // Wednesday
    SharedPreferences.setMockInitialValues({});
    wallet = WalletController(store: await FocusStore.open(), clock: clock.call);
  });

  void usePhone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpProgress(WidgetTester tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      WalletScope(
        controller: wallet,
        child: MaterialApp(theme: buildFocusTheme(), home: const ProgressScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows today against the goal and the week in numbers',
      (tester) async {
    await wallet.commit(
      session(DateTime(2026, 9, 14, 9), const Duration(hours: 1, minutes: 10)),
    );
    await wallet.commit(
      session(clock(), const Duration(minutes: 25), interruptions: 2),
    );
    await wallet.commit(
      session(DateTime(2026, 9, 7, 9), const Duration(minutes: 30)),
    );

    await pumpProgress(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('of 1h goal'), findsOneWidget);
    expect(find.textContaining('35m to go'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('Sep 14 – 20'), findsOneWidget);
    expect(find.text('1h 35m'), findsOneWidget);
    expect(find.text('+1h 5m vs week before'), findsOneWidget);
    expect(find.text('1/7'), findsOneWidget);
    expect(find.byType(WeekChart), findsOneWidget);
  });

  testWidgets('steps back a week and no further than the records go',
      (tester) async {
    await wallet.commit(session(DateTime(2026, 9, 9, 9), const Duration(minutes: 30)));
    await pumpProgress(tester);

    await tester.tap(find.byTooltip('Previous week'));
    await tester.pump();

    expect(find.text('LAST WEEK'), findsOneWidget);
    expect(find.text('Sep 7 – 13'), findsOneWidget);
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('changing the daily goal is saved', (tester) async {
    await pumpProgress(tester);

    await tester.scrollUntilVisible(find.text('2h'), 120);
    await tester.ensureVisible(find.text('2h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2h'));
    await tester.pump();

    expect(wallet.preferences.dailyGoal, const Duration(hours: 2));
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('of 2h goal'), findsOneWidget);
  });

  testWidgets('the home screen shows today and opens progress', (tester) async {
    usePhone(tester);
    await wallet.commit(session(clock(), const Duration(minutes: 20)));

    await tester.pumpWidget(FocusArApp(wallet: wallet));
    await tester.pump();

    expect(find.text('20m of 1h'), findsOneWidget);
    await tester.tap(find.text('20m of 1h'));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressScreen), findsOneWidget);
  });
}
