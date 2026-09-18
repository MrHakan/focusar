import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/app.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:focusar/state/wallet_scope.dart';
import 'package:focusar/theme/app_theme.dart';
import 'package:focusar/ui/screens/wallet_screen.dart';
import 'package:focusar/ui/widgets/focus_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Lays the test out on a phone. The default 800x600 test window is wider
  /// than it is tall, which is the one shape this app never runs in.
  void usePhoneSurface(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<WalletController> openWallet() async {
    SharedPreferences.setMockInitialValues({});
    return WalletController(store: await FocusStore.open());
  }

  SessionRecord record(double credits) => SessionRecord(
        startedAt: DateTime(2026, 9, 14, 9),
        focused: const Duration(minutes: 45),
        creditsEarned: credits,
        interruptions: 0,
        mode: FocusMode.timed,
        method: PlacementMethod.motionOnly,
        completed: true,
      );

  group('home screen', () {
    testWidgets('offers both session types and both ways to start',
        (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(FocusArApp(wallet: await openWallet()));

      expect(find.text('FocusAR'), findsOneWidget);
      expect(find.text(FocusMode.timed.label), findsOneWidget);
      expect(find.text(FocusMode.openEnded.label), findsOneWidget);
      expect(find.text('Start with motion sensor'), findsOneWidget);
      expect(find.text('Place AR focus zone'), findsOneWidget);
    });

    testWidgets('shows the focus lengths only for a timed block',
        (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(FocusArApp(wallet: await openWallet()));

      expect(find.text('25 min'), findsOneWidget);

      await tester.tap(find.text(FocusMode.openEnded.label));
      await tester.pumpAndSettle();

      expect(find.text('25 min'), findsNothing);
    });

    testWidgets('carries the balance in the header', (tester) async {
      usePhoneSurface(tester);
      final wallet = await openWallet();
      await wallet.commit(record(798));

      await tester.pumpWidget(FocusArApp(wallet: wallet));

      expect(find.text('798.00'), findsOneWidget);
    });

    testWidgets('opens the wallet from the balance pill', (tester) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(FocusArApp(wallet: await openWallet()));

      await tester.tap(find.text('0.00'));
      await tester.pumpAndSettle();

      expect(find.byType(WalletScreen), findsOneWidget);
      await tester.scrollUntilVisible(find.text('SPEND CREDITS'), 120);
      expect(find.text('SPEND CREDITS'), findsOneWidget);
    });
  });

  group('wallet screen', () {
    Future<void> pumpWallet(WidgetTester tester, WalletController wallet) async {
      await tester.pumpWidget(
        WalletScope(
          controller: wallet,
          child: MaterialApp(
            theme: buildFocusTheme(),
            home: const WalletScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('prompts for a first session when the log is empty',
        (tester) async {
      usePhoneSurface(tester);
      await pumpWallet(tester, await openWallet());

      expect(find.byType(FocusCard), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Nothing here yet'),
        120,
      );
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
    });

    testWidgets('lists a banked session', (tester) async {
      usePhoneSurface(tester);
      final wallet = await openWallet();
      await wallet.commit(record(45));

      await pumpWallet(tester, wallet);
      await tester.scrollUntilVisible(find.text('+45.0'), 120);

      expect(find.text('+45.0'), findsOneWidget);
      expect(find.text('No pick-ups'), findsOneWidget);
    });

    testWidgets('spends credits on a coupon', (tester) async {
      usePhoneSurface(tester);
      final wallet = await openWallet();
      await wallet.commit(record(120));

      await pumpWallet(tester, wallet);
      await tester.scrollUntilVisible(find.text('30m'), 120);
      await tester.tap(find.text('30m'));
      await tester.pumpAndSettle();

      expect(wallet.balance, closeTo(90, 1e-9));
      expect(find.text('READY TO USE'), findsOneWidget);
      expect(find.text('30m of screen time'), findsOneWidget);
    });

    testWidgets('says no when the balance is short', (tester) async {
      usePhoneSurface(tester);
      final wallet = await openWallet();
      await wallet.commit(record(5));

      await pumpWallet(tester, wallet);
      await tester.scrollUntilVisible(find.text('15m'), 120);
      await tester.tap(find.text('15m'));
      await tester.pumpAndSettle();

      expect(wallet.balance, 5);
      expect(find.text('READY TO USE'), findsNothing);
    });
  });

  group('focus card', () {
    testWidgets('reads the balance as credits and screen time', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 320, child: FocusCard(credits: 798)),
            ),
          ),
        ),
      );

      expect(find.text('798.00'), findsOneWidget);
      expect(find.text('credits'), findsOneWidget);
      expect(find.text('13h 18m screen time'), findsOneWidget);
      expect(find.text('FOCUS CARD'), findsOneWidget);
    });

    testWidgets('folds a running session into the balance', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: FocusCard(credits: 100, pending: 25),
              ),
            ),
          ),
        ),
      );

      expect(find.text('125.00'), findsOneWidget);
      expect(find.text('+ 2h 5m screen time'), findsOneWidget);
    });
  });
}
