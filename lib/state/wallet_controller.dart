import 'package:flutter/foundation.dart';

import '../data/focus_store.dart';
import '../domain/coupon.dart';
import '../domain/credit_rules.dart';
import '../domain/focus_preferences.dart';
import '../domain/focus_zone.dart';
import '../domain/motion_guard.dart';
import '../domain/progress_log.dart';
import '../domain/session_mode.dart';
import '../domain/session_checkpoint.dart';
import '../domain/session_record.dart';
import '../domain/wallet_snapshot.dart';

/// Owns the saved state: the credit balance, the session log, the last
/// focus-zone size, and the preferences. Every mutation writes through to
/// [FocusStore].
class WalletController extends ChangeNotifier {
  WalletController({
    required FocusStore store,
    DateTime Function()? clock,
  })  : _store = store,
        _now = clock ?? DateTime.now,
        _wallet = store.readWallet(),
        _history = store.readHistory(),
        _zone = store.readZone(),
        _preferences = store.readPreferences(),
        _progress = store.readProgress();

  final FocusStore _store;
  final DateTime Function() _now;

  WalletSnapshot _wallet;
  List<SessionRecord> _history;
  ZoneTransform _zone;
  FocusPreferences _preferences;
  ProgressLog? _progress;

  WalletSnapshot get wallet => _wallet;
  List<SessionRecord> get history => _history;

  /// The size and heading the focus zone was last left at.
  ZoneTransform get zone => _zone;

  FocusPreferences get preferences => _preferences;

  /// Focus per day. Rebuilt from the session log on first use after an
  /// update, so sessions banked before the log existed still count.
  ProgressLog get progress => _progress ??= ProgressLog.fromHistory(_history);

  /// Today's tally, against [FocusPreferences.dailyGoal].
  DayTally get today => progress.dayAt(_now());

  WeekSummary weekOf(DateTime moment) => progress.weekOf(moment);

  DateTime now() => _now();

  double get balance => _wallet.balance;
  Duration get screenTime => _wallet.screenTime;
  int get streakDays => _wallet.streakDays;
  int get sessionsCompleted => _wallet.sessionsCompleted;
  Duration get lifetimeFocus => _wallet.lifetimeFocus;

  /// Coupons still worth using right now.
  List<Coupon> get activeCoupons => _wallet.activeCoupons(_now());

  bool canAfford(Duration amount) => _wallet.canAfford(amount);

  SessionRecord? _recovered;

  /// Banks a finished session and appends it to the log.
  ///
  /// The balance is written first: it carries the marker that stops a crash
  /// between these writes from banking the same session twice on recovery.
  Future<void> commit(SessionRecord record) async {
    await _update(_wallet.recording(record));
    final progress = _progress = this.progress.recording(record);
    _history = await _store.appendSession(record);
    await _store.writeProgress(progress);
    await _store.clearCheckpoint();
    notifyListeners();
  }

  /// Saves a running session's progress so a killed app can still bank it.
  /// Skipped once the session is banked, so a late write cannot resurrect it.
  Future<void> saveCheckpoint(SessionCheckpoint checkpoint) async {
    if (_wallet.hasBanked(checkpoint.startedAt)) return;
    await _store.writeCheckpoint(checkpoint);
  }

  /// Banks a session the app was killed in the middle of. Call once at
  /// launch, before any new session can start. Returns the banked record, or
  /// `null` when there was nothing to recover.
  Future<SessionRecord?> recoverUnfinished() async {
    final checkpoint = _store.readCheckpoint();
    if (checkpoint == null) return null;
    if (!checkpoint.hasProgress || _wallet.hasBanked(checkpoint.startedAt)) {
      await _store.clearCheckpoint();
      return null;
    }
    final record = checkpoint.toRecord();
    await commit(record);
    _recovered = record;
    return record;
  }

  /// The session [recoverUnfinished] banked, handed out once so the home
  /// screen can say so.
  SessionRecord? takeRecovered() {
    final record = _recovered;
    _recovered = null;
    return record;
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

  Future<void> setSensitivity(Sensitivity sensitivity) =>
      _updatePreferences(_preferences.copyWith(sensitivity: sensitivity));

  /// Remembers how a session was started, for quick start next time.
  Future<void> rememberConfig(SessionConfig config) =>
      _updatePreferences(_preferences.copyWith(lastConfig: config));

  Future<void> setDailyGoal(Duration goal) {
    if (goal <= Duration.zero) return Future.value();
    return _updatePreferences(_preferences.copyWith(dailyGoal: goal));
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
    _progress = ProgressLog.empty;
    _zone = ZoneTransform.initial;
    notifyListeners();
  }

  /// The balance rendered the way the focus card shows it.
  String get balanceLabel => CreditRules.formatCredits(_wallet.balance);

  Future<void> _updatePreferences(FocusPreferences next) async {
    if (next == _preferences) return;
    _preferences = next;
    await _store.writePreferences(next);
    notifyListeners();
  }

  Future<void> _update(WalletSnapshot next) async {
    _wallet = next;
    await _store.writeWallet(next);
    notifyListeners();
  }
}
