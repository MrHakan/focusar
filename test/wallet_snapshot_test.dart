import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/coupon.dart';
import 'package:focusar/domain/credit_rules.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/domain/wallet_snapshot.dart';

SessionRecord record({
  required DateTime at,
  double credits = 10,
  Duration focused = const Duration(minutes: 10),
  int interruptions = 0,
}) =>
    SessionRecord(
      startedAt: at,
      focused: focused,
      creditsEarned: credits,
      interruptions: interruptions,
      mode: FocusMode.timed,
      method: PlacementMethod.motionOnly,
      completed: true,
    );

void main() {
  final monday = DateTime(2026, 9, 14, 9);

  group('banking a session', () {
    test('adds credits, focus time, and a session', () {
      final wallet = WalletSnapshot.empty.recording(record(at: monday));

      expect(wallet.balance, 10);
      expect(wallet.lifetimeEarned, 10);
      expect(wallet.lifetimeFocus, const Duration(minutes: 10));
      expect(wallet.sessionsCompleted, 1);
      expect(wallet.streakDays, 1);
    });

    test('extends the streak on the next day', () {
      final wallet = WalletSnapshot.empty
          .recording(record(at: monday))
          .recording(record(at: monday.add(const Duration(days: 1))));

      expect(wallet.streakDays, 2);
    });

    test('keeps the streak flat for a second session the same day', () {
      final wallet = WalletSnapshot.empty
          .recording(record(at: monday))
          .recording(record(at: monday.add(const Duration(hours: 6))));

      expect(wallet.streakDays, 1);
      expect(wallet.sessionsCompleted, 2);
    });

    test('resets the streak after a missed day', () {
      final wallet = WalletSnapshot.empty
          .recording(record(at: monday))
          .recording(record(at: monday.add(const Duration(days: 3))));

      expect(wallet.streakDays, 1);
    });
  });

  group('redeeming', () {
    final wallet = WalletSnapshot.empty.recording(record(at: monday, credits: 120));

    test('spends credits and issues a coupon', () {
      final next = wallet.redeeming(const Duration(hours: 1), monday);

      expect(next, isNotNull);
      expect(next!.balance, closeTo(60, 1e-9));
      expect(next.coupons.single.amount, const Duration(hours: 1));
      expect(next.coupons.single.cost, 60);
    });

    test('refuses a redemption the balance cannot cover', () {
      expect(wallet.redeeming(const Duration(hours: 5), monday), isNull);
      expect(wallet.redeeming(Duration.zero, monday), isNull);
    });

    test('allows spending the balance down to exactly zero', () {
      final next = wallet.redeeming(const Duration(minutes: 120), monday);

      expect(next, isNotNull);
      expect(next!.balance, closeTo(0, 1e-9));
      expect(next.canAfford(const Duration(minutes: 1)), isFalse);
    });

    test('keeps only the most recent coupons', () {
      var current = WalletSnapshot.empty.recording(record(at: monday, credits: 5000));
      for (var i = 0; i < WalletSnapshot.couponHistoryLimit + 6; i++) {
        current = current.redeeming(const Duration(minutes: 15), monday)!;
      }

      expect(current.coupons.length, WalletSnapshot.couponHistoryLimit);
    });
  });

  group('coupons', () {
    final wallet = WalletSnapshot.empty
        .recording(record(at: monday, credits: 120))
        .redeeming(const Duration(hours: 1), monday)!;

    test('is usable while fresh', () {
      expect(wallet.activeCoupons(monday), hasLength(1));
    });

    test('lapses once its validity runs out', () {
      final later = monday.add(Coupon.validity);

      expect(wallet.activeCoupons(later), isEmpty);
      expect(wallet.pruned(later).coupons, isEmpty);
    });

    test('drops out of the active list once marked used', () {
      final used = wallet.marking(wallet.coupons.single);

      expect(used.activeCoupons(monday), isEmpty);
      expect(used.coupons.single.spent, isTrue);
    });

    test('keeps spent coupons through a prune', () {
      final used = wallet.marking(wallet.coupons.single);

      expect(used.pruned(monday.add(Coupon.validity)).coupons, hasLength(1));
    });

    test('ignores a coupon it does not hold', () {
      final stranger = Coupon(
        issuedAt: monday,
        amount: const Duration(minutes: 5),
        cost: 5,
      );

      expect(wallet.marking(stranger), same(wallet));
    });
  });

  group('persistence', () {
    test('round-trips through json', () {
      final wallet = WalletSnapshot.empty
          .recording(record(at: monday, credits: 120))
          .redeeming(const Duration(hours: 1), monday)!;
      final restored = WalletSnapshot.fromJson(wallet.toJson());

      expect(restored.balance, wallet.balance);
      expect(restored.streakDays, wallet.streakDays);
      expect(restored.lifetimeFocus, wallet.lifetimeFocus);
      expect(restored.lastSessionDay, wallet.lastSessionDay);
      expect(restored.coupons.single.amount, const Duration(hours: 1));
    });

    test('survives junk in the stored payload', () {
      final restored = WalletSnapshot.fromJson(const {
        'balance': 'lots',
        'streakDays': null,
        'coupons': 'none',
      });

      expect(restored.balance, 0);
      expect(restored.streakDays, 0);
      expect(restored.coupons, isEmpty);
    });
  });

  test('screen time tracks the balance', () {
    final wallet = WalletSnapshot.empty.recording(record(at: monday, credits: 798));

    expect(wallet.screenTime, CreditRules.screenTimeFor(798));
    expect(wallet.screenTime, const Duration(minutes: 798));
  });
}
