import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/data/focus_store.dart';
import 'package:focusar/domain/focus_zone.dart';
import 'package:focusar/domain/session_mode.dart';
import 'package:focusar/domain/session_record.dart';
import 'package:focusar/domain/wallet_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionRecord recordAt(DateTime at, {double credits = 4}) => SessionRecord(
      startedAt: at,
      focused: const Duration(minutes: 4),
      creditsEarned: credits,
      interruptions: 1,
      mode: FocusMode.openEnded,
      method: PlacementMethod.arZone,
      completed: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day = DateTime(2026, 9, 14);

  Future<FocusStore> openStore([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return FocusStore.open();
  }

  test('reads empty state on a fresh install', () async {
    final store = await openStore();

    expect(store.readWallet().balance, 0);
    expect(store.readHistory(), isEmpty);
    expect(store.readZone(), ZoneTransform.initial);
  });

  test('round-trips the wallet through storage', () async {
    final store = await openStore();
    final wallet = WalletSnapshot.empty
        .recording(recordAt(day, credits: 42))
        .redeeming(const Duration(minutes: 30), day)!;

    await store.writeWallet(wallet);
    final restored = store.readWallet();

    expect(restored.balance, closeTo(wallet.balance, 1e-9));
    expect(restored.sessionsCompleted, 1);
    expect(restored.streakDays, 1);
    expect(restored.coupons.single.amount, const Duration(minutes: 30));
  });

  test('round-trips a session log', () async {
    final store = await openStore();

    await store.appendSession(recordAt(day, credits: 7));
    final restored = store.readHistory().single;

    expect(restored.creditsEarned, 7);
    expect(restored.mode, FocusMode.openEnded);
    expect(restored.method, PlacementMethod.arZone);
    expect(restored.interruptions, 1);
    expect(restored.completed, isFalse);
  });

  test('keeps the newest sessions at the front and trims the tail', () async {
    final store = await openStore();
    for (var i = 0; i < FocusStore.historyLimit + 5; i++) {
      await store.appendSession(
        recordAt(day.add(Duration(days: i)), credits: i.toDouble()),
      );
    }

    final history = store.readHistory();

    expect(history, hasLength(FocusStore.historyLimit));
    expect(history.first.creditsEarned, (FocusStore.historyLimit + 4).toDouble());
  });

  test('round-trips the saved zone', () async {
    final store = await openStore();
    final zone = ZoneTransform.initial.scaledBy(1.6).rotatedBy(0.4);

    await store.writeZone(zone);

    expect(store.readZone(), zone);
  });

  test('treats unreadable stored data as nothing saved', () async {
    final store = await openStore({
      'focusar.wallet.v1': 'not json',
      'focusar.history.v1': '{"not":"a list"}',
      'focusar.zone.v1': '[]',
    });

    expect(store.readWallet().balance, 0);
    expect(store.readHistory(), isEmpty);
    expect(store.readZone(), ZoneTransform.initial);
  });

  test('skips log entries that will not decode', () async {
    final store = await openStore({
      'focusar.history.v1': '[{"creditsEarned":"lots"},"junk",{"creditsEarned":3}]',
    });

    final history = store.readHistory();

    expect(history, hasLength(2));
    expect(history.first.creditsEarned, 0);
    expect(history.last.creditsEarned, 3);
  });

  test('clear wipes everything', () async {
    final store = await openStore();
    await store.writeWallet(WalletSnapshot.empty.recording(recordAt(day)));
    await store.appendSession(recordAt(day));
    await store.writeZone(ZoneTransform.initial.scaledBy(2));

    await store.clear();

    expect(store.readWallet().balance, 0);
    expect(store.readHistory(), isEmpty);
    expect(store.readZone(), ZoneTransform.initial);
  });
}
