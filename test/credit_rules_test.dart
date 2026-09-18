import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/credit_rules.dart';
import 'package:focusar/domain/focus_clock.dart';

void main() {
  group('multiplier tiers', () {
    test('starts at the base rate', () {
      expect(CreditRules.multiplierFor(Duration.zero), 1.0);
      expect(CreditRules.multiplierFor(const Duration(minutes: 24)), 1.0);
    });

    test('steps up as an unbroken run gets longer', () {
      expect(CreditRules.multiplierFor(const Duration(minutes: 25)), 1.25);
      expect(CreditRules.multiplierFor(const Duration(minutes: 50)), 1.5);
      expect(CreditRules.multiplierFor(const Duration(minutes: 90)), 2.0);
      expect(CreditRules.multiplierFor(const Duration(hours: 4)), 2.0);
    });

    test('labels the tier the way the session screen shows it', () {
      expect(CreditRules.tierFor(Duration.zero).multiplierLabel, '1x');
      expect(CreditRules.tierFor(const Duration(minutes: 25)).multiplierLabel, '1.25x');
      expect(CreditRules.tierFor(const Duration(minutes: 50)).multiplierLabel, '1.5x');
      expect(CreditRules.tierFor(const Duration(minutes: 90)).multiplierLabel, '2x');
    });
  });

  group('accrual', () {
    test('a base minute is worth one credit', () {
      var earned = 0.0;
      for (var second = 0; second < 60; second++) {
        earned += CreditRules.creditsForSecond(Duration(seconds: second));
      }

      expect(earned, closeTo(1.0, 1e-9));
    });

    test('an unbroken half hour outpaces a broken one', () {
      var unbroken = 0.0;
      for (var second = 0; second < 1800; second++) {
        unbroken += CreditRules.creditsForSecond(Duration(seconds: second));
      }

      expect(unbroken, greaterThan(30.0));
      expect(unbroken, closeTo(30 + 5 * 0.25, 1e-6));
    });
  });

  group('screen time', () {
    test('one credit buys one minute', () {
      expect(CreditRules.screenTimeFor(1), const Duration(minutes: 1));
      expect(CreditRules.costOf(const Duration(minutes: 1)), 1.0);
    });

    test('the reference balance reads as the card shows it', () {
      expect(CreditRules.formatCredits(798), '798.00');
      expect(formatSpan(CreditRules.screenTimeFor(798)), '13h 18m');
    });

    test('a negative or empty balance buys nothing', () {
      expect(CreditRules.screenTimeFor(0), Duration.zero);
      expect(CreditRules.screenTimeFor(-10), Duration.zero);
      expect(CreditRules.costOf(Duration.zero), 0);
    });

    test('round-trips a redemption back to its price', () {
      for (final amount in CreditRules.redemptionOptions) {
        expect(CreditRules.screenTimeFor(CreditRules.costOf(amount)), amount);
      }
    });
  });
}
