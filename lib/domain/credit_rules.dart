/// The economy behind the focus card.
///
/// One credit buys one minute of screen time, so a 798.00 balance reads as
/// 13h 18m. Credits accrue per focused second, and an unbroken run earns them
/// faster — picking the phone up drops you back to the base rate.
class CreditRules {
  const CreditRules._();

  /// Credits earned per focused minute before any multiplier.
  static const double baseCreditsPerMinute = 1.0;

  /// Minutes of screen time one credit is worth.
  static const double minutesPerCredit = 1.0;

  /// Thresholds are checked top-down, so the list stays ordered by minutes.
  static const List<CreditTier> tiers = [
    CreditTier(afterMinutes: 90, multiplier: 2.0, label: 'Marathon'),
    CreditTier(afterMinutes: 50, multiplier: 1.5, label: 'Deep'),
    CreditTier(afterMinutes: 25, multiplier: 1.25, label: 'Warmed up'),
    CreditTier(afterMinutes: 0, multiplier: 1.0, label: 'Base'),
  ];

  /// The tier an unbroken run of [unbroken] has reached.
  static CreditTier tierFor(Duration unbroken) {
    final minutes = unbroken.inMinutes;
    for (final tier in tiers) {
      if (minutes >= tier.afterMinutes) return tier;
    }
    return tiers.last;
  }

  static double multiplierFor(Duration unbroken) => tierFor(unbroken).multiplier;

  /// Credits earned by the next second, given how long the current unbroken
  /// run has already lasted.
  static double creditsForSecond(Duration unbroken) =>
      baseCreditsPerMinute / 60 * multiplierFor(unbroken);

  /// What [credits] are worth as screen time.
  static Duration screenTimeFor(double credits) {
    if (credits <= 0) return Duration.zero;
    return Duration(seconds: (credits * minutesPerCredit * 60).round());
  }

  /// What [screenTime] costs in credits.
  static double costOf(Duration screenTime) {
    if (screenTime <= Duration.zero) return 0;
    return screenTime.inSeconds / 60 / minutesPerCredit;
  }

  /// The balance rendered the way the card shows it: `798.00`.
  static String formatCredits(double credits) => credits.toStringAsFixed(2);

  /// The redemption sizes offered in the wallet.
  static const List<Duration> redemptionOptions = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
  ];
}

/// A multiplier band reached by staying off the phone.
class CreditTier {
  const CreditTier({
    required this.afterMinutes,
    required this.multiplier,
    required this.label,
  });

  final int afterMinutes;
  final double multiplier;
  final String label;

  /// `1x`, `1.25x`, `1.5x` — trailing zeros trimmed.
  String get multiplierLabel {
    final trimmed = multiplier
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '${trimmed}x';
  }
}
