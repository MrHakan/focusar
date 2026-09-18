import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/focus_zone.dart';
import '../domain/session_record.dart';
import '../domain/wallet_snapshot.dart';

/// Everything FocusAR keeps between launches: the credit balance, the recent
/// session log, and the size the focus zone was last left at.
class FocusStore {
  FocusStore(this._prefs);

  static const String _walletKey = 'focusar.wallet.v1';
  static const String _historyKey = 'focusar.history.v1';
  static const String _zoneKey = 'focusar.zone.v1';

  /// Sessions kept in the log. Older ones fall off the end.
  static const int historyLimit = 30;

  final SharedPreferences _prefs;

  static Future<FocusStore> open() async =>
      FocusStore(await SharedPreferences.getInstance());

  WalletSnapshot readWallet() {
    final decoded = _readMap(_walletKey);
    return decoded == null ? WalletSnapshot.empty : WalletSnapshot.fromJson(decoded);
  }

  Future<void> writeWallet(WalletSnapshot wallet) =>
      _prefs.setString(_walletKey, jsonEncode(wallet.toJson()));

  List<SessionRecord> readHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SessionRecord.fromJson)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  /// Puts [record] at the front of the log and trims it to [historyLimit].
  Future<List<SessionRecord>> appendSession(SessionRecord record) async {
    final next = [record, ...readHistory()].take(historyLimit).toList(growable: false);
    await _prefs.setString(
      _historyKey,
      jsonEncode(next.map((entry) => entry.toJson()).toList()),
    );
    return next;
  }

  ZoneTransform readZone() {
    final decoded = _readMap(_zoneKey);
    return decoded == null ? ZoneTransform.initial : ZoneTransform.fromJson(decoded);
  }

  Future<void> writeZone(ZoneTransform zone) =>
      _prefs.setString(_zoneKey, jsonEncode(zone.toJson()));

  /// Wipes the balance, the log, and the saved zone.
  Future<void> clear() async {
    await _prefs.remove(_walletKey);
    await _prefs.remove(_historyKey);
    await _prefs.remove(_zoneKey);
  }

  /// Decodes a stored object, treating corrupt data as "nothing saved yet".
  Map<String, dynamic>? _readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
