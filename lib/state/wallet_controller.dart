import 'package:flutter/foundation.dart';

import '../data/focus_store.dart';
import '../domain/coupon.dart';
import '../domain/credit_rules.dart';
import '../domain/focus_zone.dart';
import '../domain/session_record.dart';
import '../domain/wallet_snapshot.dart';

/// Owns the saved state: the credit balance, the session log, and the last
/// focus-zone size. Every mutation writes through to [FocusStore].
class WalletController extends ChangeNotifier {
  WalletController({
    required FocusStore store,
    DateTime Function()? clock,
  })  : _store = store,
        _now = clock ?? DateTime.now,
        _wallet = store.readWallet(),
        _history = store.readHistory(),
        _zone = store.readZone();

  final FocusStore _store;
  final DateTime Function() _now;

  WalletSnapshot _wallet;
  List<SessionRecord> _history;
  ZoneTransform _zone;

  WalletSnapshot get wallet => _wallet;
  List<SessionRecord> get history => _history;

  /// The size and heading the focus zone was last left at.
  ZoneTransform get zone => _zone;

  double get balance => _wallet.balance;
  Duration get screenTime => _wallet.screenTime;
  int get streakDays => _wallet.streakDays;
  int get sessionsCompleted => _wallet.sessionsCompleted;
  Duration get lifetimeFocus => _wallet.lifetimeFocus;

  /// Coupons still worth using right now.
  List<Coupon> get activeCoupons => _wallet.activeCoupons(_now());

  bool canAfford(Duration amount) => _wallet.canAfford(amount);

  /// Banks a finished session and appends it to the log.
  Future<void> commit(SessionRecord record) async {
    _history = await _store.appendSession(record);
    await _update(_wallet.recording(record));
  }

  /// Buys a screen-time coupon. Returns `null` when the balance is short.
  Future<Coupon?> redeem(Duration amount) async {
    final now = _now();
    final next = _wallet.pruned(now).redeeming(amount, now);
    if (next == null) return null;
    await _update(next);
    return next.coupons.first;
  }

  /// Marks a coupon as used up.
  Future<void> spend(Coupon coupon) => _update(_wallet.marking(coupon));

  /// Remembers the zone the person shaped in AR so the next session starts
  /// from the same size instead of the default.
  Future<void> saveZone(ZoneTransform zone) async {
    if (zone == _zone) return;
    _zone = zone;
    await _store.writeZone(zone);
    notifyListeners();
  }

  /// Drops coupons that quietly expired since the last launch.
  Future<void> pruneExpired() async {
    final next = _wallet.pruned(_now());
    if (identical(next, _wallet)) return;
    await _update(next);
  }

  /// Wipes everything. Used by the "reset progress" action in the wallet.
  Future<void> reset() async {
    await _store.clear();
    _wallet = WalletSnapshot.empty;
    _history = const [];
    _zone = ZoneTransform.initial;
    notifyListeners();
  }

  /// The balance rendered the way the focus card shows it.
  String get balanceLabel => CreditRules.formatCredits(_wallet.balance);

  Future<void> _update(WalletSnapshot next) async {
    _wallet = next;
    await _store.writeWallet(next);
    notifyListeners();
  }
}
