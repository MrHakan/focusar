import 'coupon.dart';
import 'credit_rules.dart';
import 'json_reader.dart';
import 'session_record.dart';

/// The whole savings account, as one immutable value.
///
/// Every rule that moves credits lives here, so the economy can be tested
/// without touching storage or the widget tree.
class WalletSnapshot {
  const WalletSnapshot({
    this.balance = 0,
    this.lifetimeEarned = 0,
    this.lifetimeFocus = Duration.zero,
    this.sessionsCompleted = 0,
    this.streakDays = 0,
    this.lastSessionDay,
    this.coupons = const [],
  });

  static const WalletSnapshot empty = WalletSnapshot();

  /// Coupons older than this are dropped from the ledger.
  static const int couponHistoryLimit = 20;

  /// Credits available to spend.
  final double balance;

  /// Credits ever earned, spent or not.
  final double lifetimeEarned;

  final Duration lifetimeFocus;
  final int sessionsCompleted;

  /// Consecutive days with at least one finished session.
  final int streakDays;

  /// Midnight of the last day a session landed.
  final DateTime? lastSessionDay;

  final List<Coupon> coupons;

  /// The balance expressed the way the focus card shows it.
  Duration get screenTime => CreditRules.screenTimeFor(balance);

  bool canAfford(Duration amount) =>
      balance + 1e-9 >= CreditRules.costOf(amount);

  List<Coupon> activeCoupons(DateTime now) =>
      coupons.where((coupon) => coupon.isRedeemable(now)).toList(growable: false);

  /// Folds a finished session into the balance, totals, and day streak.
  WalletSnapshot recording(SessionRecord record) {
    final day = _dayOf(record.startedAt);
    return copyWith(
      balance: balance + record.creditsEarned,
      lifetimeEarned: lifetimeEarned + record.creditsEarned,
      lifetimeFocus: lifetimeFocus + record.focused,
      sessionsCompleted: sessionsCompleted + 1,
      streakDays: _streakAfter(day),
      lastSessionDay: day,
    );
  }

  /// Spends credits on a screen-time coupon. Returns `null` if the balance is
  /// short, so callers never have to re-check the price themselves.
  WalletSnapshot? redeeming(Duration amount, DateTime now) {
    if (amount <= Duration.zero || !canAfford(amount)) return null;
    final cost = CreditRules.costOf(amount);
    final issued = Coupon(issuedAt: now, amount: amount, cost: cost);
    final next = [issued, ...coupons];
    return copyWith(
      balance: balance - cost,
      coupons: next.take(couponHistoryLimit).toList(growable: false),
    );
  }

  /// Marks a coupon used. Unknown coupons leave the wallet untouched.
  WalletSnapshot marking(Coupon coupon, {bool spent = true}) {
    final index = coupons.indexOf(coupon);
    if (index < 0) return this;
    final next = [...coupons];
    next[index] = coupon.copyWith(spent: spent);
    return copyWith(coupons: next);
  }

  /// Drops coupons that expired without being used.
  WalletSnapshot pruned(DateTime now) {
    final kept = coupons
        .where((coupon) => coupon.spent || !coupon.isExpired(now))
        .toList(growable: false);
    return kept.length == coupons.length ? this : copyWith(coupons: kept);
  }

  int _streakAfter(DateTime day) {
    final last = lastSessionDay;
    if (last == null) return 1;
    final gap = day.difference(last).inDays;
    if (gap <= 0) return streakDays == 0 ? 1 : streakDays;
    if (gap == 1) return streakDays + 1;
    return 1;
  }

  static DateTime _dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  WalletSnapshot copyWith({
    double? balance,
    double? lifetimeEarned,
    Duration? lifetimeFocus,
    int? sessionsCompleted,
    int? streakDays,
    DateTime? lastSessionDay,
    List<Coupon>? coupons,
  }) =>
      WalletSnapshot(
        balance: balance ?? this.balance,
        lifetimeEarned: lifetimeEarned ?? this.lifetimeEarned,
        lifetimeFocus: lifetimeFocus ?? this.lifetimeFocus,
        sessionsCompleted: sessionsCompleted ?? this.sessionsCompleted,
        streakDays: streakDays ?? this.streakDays,
        lastSessionDay: lastSessionDay ?? this.lastSessionDay,
        coupons: coupons ?? this.coupons,
      );

  Map<String, dynamic> toJson() => {
        'balance': balance,
        'lifetimeEarned': lifetimeEarned,
        'lifetimeFocusSeconds': lifetimeFocus.inSeconds,
        'sessionsCompleted': sessionsCompleted,
        'streakDays': streakDays,
        'lastSessionDay': lastSessionDay?.toIso8601String(),
        'coupons': coupons.map((coupon) => coupon.toJson()).toList(),
      };

  static WalletSnapshot fromJson(Map<String, dynamic> json) => WalletSnapshot(
        balance: json.readDouble('balance'),
        lifetimeEarned: json.readDouble('lifetimeEarned'),
        lifetimeFocus: json.readDuration('lifetimeFocusSeconds'),
        sessionsCompleted: json.readInt('sessionsCompleted'),
        streakDays: json.readInt('streakDays'),
        lastSessionDay: json.readDate('lastSessionDay'),
        coupons: json
            .readObjects('coupons')
            .map(Coupon.fromJson)
            .toList(growable: false),
      );
}
