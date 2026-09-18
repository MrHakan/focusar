import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/coupon.dart';
import 'package:focusar/domain/focus_zone.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/state/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ManualClock clock;

  SessionRecord record({double credits = 60, int interruptions = 0}) =>
      SessionRecord(
        startedAt: clock(),
        focused: const Duration(minutes: 60),
        creditsEarned: credits,
        interruptions: interruptions,
        mode: FocusMode.timed,
        method: PlacementMethod.motionOnly,
        completed: true,
      );

  Future<WalletController> open() async {
    SharedPreferences.setMockInitialValues({});
    return WalletController(store: await FocusStore.open(), clock: clock.call);
  }

  setUp(() => clock = ManualClock());

  test('starts empty', () async {
    final wallet = await open();

    expect(wallet.balance, 0);
    expect(wallet.streakDays, 0);
    expect(wallet.history, isEmpty);
    expect(wallet.zone, ZoneTransform.initial);
  });

  test('banks a session and notifies listeners', () async {
    final wallet = await open();
    var notifications = 0;
    wallet.addListener(() => notifications++);

    await wallet.commit(record());

    expect(wallet.balance, 60);
    expect(wallet.sessionsCompleted, 1);
    expect(wallet.lifetimeFocus, const Duration(minutes: 60));
    expect(wallet.history.single.creditsEarned, 60);
    expect(notifications, greaterThan(0));
  });

  test('survives a reload with the balance intact', () async {
    final wallet = await open();
    await wallet.commit(record());

    final reloaded = WalletController(
      store: await FocusStore.open(),
      clock: clock.call,
    );

    expect(reloaded.balance, 60);
    expect(reloaded.history, hasLength(1));
  });

  test('redeems screen time when the balance covers it', () async {
    final wallet = await open();
    await wallet.commit(record());

    final coupon = await wallet.redeem(const Duration(minutes: 30));

    expect(coupon, isNotNull);
    expect(coupon!.amount, const Duration(minutes: 30));
    expect(wallet.balance, closeTo(30, 1e-9));
    expect(wallet.activeCoupons, hasLength(1));
  });

  test('refuses a redemption it cannot cover and changes nothing', () async {
    final wallet = await open();
    await wallet.commit(record(credits: 5));

    final coupon = await wallet.redeem(const Duration(hours: 2));

    expect(coupon, isNull);
    expect(wallet.balance, 5);
    expect(wallet.activeCoupons, isEmpty);
  });

  test('a spent coupon leaves the ready list', () async {
    final wallet = await open();
    await wallet.commit(record());
    final coupon = await wallet.redeem(const Duration(minutes: 15));

    await wallet.spend(coupon!);

    expect(wallet.activeCoupons, isEmpty);
    expect(wallet.balance, closeTo(45, 1e-9));
  });

  test('prunes coupons that lapsed while the app was closed', () async {
    final wallet = await open();
    await wallet.commit(record());
    await wallet.redeem(const Duration(minutes: 15));

    clock.advance(Coupon.validity + const Duration(minutes: 1));
    await wallet.pruneExpired();

    expect(wallet.activeCoupons, isEmpty);
    expect(wallet.wallet.coupons, isEmpty);
  });

  test('remembers the zone shaped in AR', () async {
    final wallet = await open();
    final zone = ZoneTransform.initial.scaledBy(1.5).rotatedBy(0.3);

    await wallet.saveZone(zone);

    expect(wallet.zone, zone);
    expect(
      WalletController(store: await FocusStore.open(), clock: clock.call).zone,
      zone,
    );
  });

  test('saving the same zone twice is a no-op', () async {
    final wallet = await open();
    var notifications = 0;
    wallet.addListener(() => notifications++);

    await wallet.saveZone(ZoneTransform.initial);

    expect(notifications, 0);
  });

  test('reset clears the balance, the log, and the zone', () async {
    final wallet = await open();
    await wallet.commit(record());
    await wallet.saveZone(ZoneTransform.initial.scaledBy(2));

    await wallet.reset();

    expect(wallet.balance, 0);
    expect(wallet.history, isEmpty);
    expect(wallet.streakDays, 0);
    expect(wallet.zone, ZoneTransform.initial);
  });

  test('formats the balance the way the card shows it', () async {
    final wallet = await open();
    await wallet.commit(record(credits: 798));

    expect(wallet.balanceLabel, '798.00');
    expect(wallet.screenTime, const Duration(minutes: 798));
  });
}
