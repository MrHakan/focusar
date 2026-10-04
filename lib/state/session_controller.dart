import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sensor_feed.dart';
import '../domain/credit_rules.dart';
import '../domain/focus_clock.dart';
import '../domain/motion_guard.dart';
import '../domain/session_checkpoint.dart';
import '../domain/session_mode.dart';
import '../domain/session_record.dart';
import 'session_alerts.dart';

/// Produces the heartbeat that advances the clock. Injectable so tests can
/// step a session forward without waiting in real time.
typedef TickSource = Stream<void> Function(Duration interval);

/// The real heartbeat: one beat a second, off the event loop.
Stream<void> defaultTickSource(Duration interval) =>
    Stream<void>.periodic(interval, (_) {});

/// Runs one focus session: watches the sensors, decides when the phone counts
/// as put down, moves the clock, and accrues credits.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.config,
    required SensorFeed feed,
    MotionGuard guard = const MotionGuard(),
    SessionAlerts alerts = const PlatformAlerts(),
    TickSource ticker = defaultTickSource,
    Duration tickInterval = const Duration(seconds: 1),
    DateTime Function()? clock,
    this.onComplete,
    this.onCheckpoint,
  })  : _feed = feed,
        _guard = guard,
        _alerts = alerts,
        _ticker = ticker,
        _tickInterval = tickInterval,
        _now = clock ?? DateTime.now,
        _timer = config.isTimed
            ? FocusClock.countdown(config.target)
            : FocusClock.countUp(),
        _pickup = PickupDetector(guard.thresholds);

  /// How long the phone must sit still before the clock starts.
  static const Duration armDelay = Duration(milliseconds: 1200);

  /// How long it must sit still again to shake off an interruption.
  static const Duration resumeDelay = Duration(seconds: 1);

  /// Focused time between two checkpoints — the most a killed app can lose.
  static const Duration checkpointEvery = Duration(seconds: 10);

  /// A heartbeat this late means the app was frozen — suspended by the OS
  /// without a lifecycle callback, or starved. Nobody watched the phone in
  /// that gap, so none of it is paid for.
  static const Duration maxHeartbeatGap = Duration(seconds: 5);

  final SessionConfig config;

  /// Called once, with the session's record, when it ends.
  final void Function(SessionRecord record)? onComplete;

  /// Called with the session's progress whenever it is worth saving: every
  /// [checkpointEvery] of focus, and whenever the session stops counting.
  final void Function(SessionCheckpoint checkpoint)? onCheckpoint;

  final SensorFeed _feed;
  final MotionGuard _guard;
  final SessionAlerts _alerts;
  final TickSource _ticker;
  final Duration _tickInterval;
  final DateTime Function() _now;
  final FocusClock _timer;
  final PickupDetector _pickup;

  StreamSubscription<MotionSample>? _samples;
  StreamSubscription<void>? _ticks;

  SessionStage _stage = SessionStage.arming;
  DateTime? _startedAt;
  DateTime? _stableSince;
  DateTime? _unsettledSince;
  int _unbrokenSeconds = 0;
  int _interruptions = 0;
  double _earned = 0;
  double _stability = 0;
  bool _finished = false;
  bool _away = false;
  DateTime? _awaySince;
  DateTime? _lastBeat;
  Duration _lastAbsence = Duration.zero;

  SessionStage get stage => _stage;
  bool get isRunning => _stage == SessionStage.focusing;
  bool get isArming => _stage == SessionStage.arming;
  bool get isInterrupted => _stage == SessionStage.interrupted;
  bool get isPaused => _stage == SessionStage.paused;
  bool get isComplete => _stage == SessionStage.complete;

  /// Time that actually counted.
  Duration get focused => _timer.elapsed;

  /// The number on the big clock: counting down, or counting up.
  String get display => formatClock(_timer.displaySeconds);

  double get progress => _timer.progress;

  /// Credits banked so far this session.
  double get earnedCredits => _earned;

  /// Screen time those credits are worth.
  Duration get earnedScreenTime => CreditRules.screenTimeFor(_earned);

  /// The multiplier band the current unbroken run has reached.
  CreditTier get tier => CreditRules.tierFor(Duration(seconds: _unbrokenSeconds));

  Duration get unbrokenRun => Duration(seconds: _unbrokenSeconds);

  int get interruptions => _interruptions;

  /// 0..1 calmness of the last sample, for the status ring.
  double get stability => _stability;

  /// `true` while the app is out of sight — locked, backgrounded, or covered by
  /// another app. Nothing counts and nothing resumes until it comes back.
  bool get isAway => _away;

  /// How long the app was last out of sight. That time was never counted.
  Duration get lastAbsence => _lastAbsence;

  /// The progress so far, in the shape that survives the app being killed.
  /// `null` before [start].
  SessionCheckpoint? get checkpoint {
    final startedAt = _startedAt;
    if (startedAt == null) return null;
    return SessionCheckpoint(
      config: config,
      startedAt: startedAt,
      savedAt: _now(),
      focused: _timer.elapsed,
      creditsEarned: _earned,
      interruptions: _interruptions,
    );
  }

  /// Starts listening to the sensors. Call once.
  void start() {
    if (_samples != null) return;
    _startedAt = _now();
    _lastBeat = _startedAt;
    _samples = _feed.samples.listen(_onSample);
    _ticks = _ticker(_tickInterval).listen((_) => _onTick());
  }

  /// Steps the phone out of the session on purpose. No alarm, no credits, and
  /// the phone has to be put back down before the clock moves again.
  void pause() {
    if (_stage != SessionStage.focusing && _stage != SessionStage.interrupted) {
      return;
    }
    _stage = SessionStage.paused;
    _resetWatch();
    _saveCheckpoint();
    notifyListeners();
  }

  /// Returns to waiting-for-the-phone. The clock keeps whatever it had.
  void resume() {
    if (_stage != SessionStage.paused) return;
    _stage = SessionStage.arming;
    _resetWatch();
    notifyListeners();
  }

  /// The app went out of sight: the screen was locked, another app came to
  /// the front, or the app was sent to the background. Mid-focus that counts
  /// as a pick-up. Either way the session holds still until [reportReturned]:
  /// the sensors cannot resume it and the alarm stays quiet, so a phone that
  /// keeps reporting from a pocket or a lock screen earns nothing.
  void reportLeftApp() {
    if (_stage == SessionStage.complete || _away) return;
    _away = true;
    _awaySince = _now();
    _resetWatch();
    if (_stage == SessionStage.focusing) {
      _interrupt();
    } else {
      _saveCheckpoint();
      notifyListeners();
    }
  }

  /// The app is back in front. If it was focusing when it left, the phone has
  /// to be put back down before the clock moves again.
  void reportReturned() {
    if (!_away) return;
    _away = false;
    final since = _awaySince;
    _lastAbsence = since == null ? Duration.zero : _now().difference(since);
    _awaySince = null;
    _resetWatch();
    _lastBeat = _now();
    notifyListeners();
  }

  /// Ends the session early but keeps what was earned.
  void stop() => _finish(completed: false);

  void _onSample(MotionSample sample) {
    if (_stage == SessionStage.complete || _away) return;

    final reading = _guard.read(sample);
    final stabilityChanged = _updateStability(reading.stability);

    switch (_stage) {
      case SessionStage.arming:
        _awaitPlacement(reading, armDelay, _begin);
      case SessionStage.focusing:
        _watchForPickup(reading);
      case SessionStage.interrupted:
        _awaitPlacement(reading, resumeDelay, _recover);
      case SessionStage.paused:
      case SessionStage.complete:
        break;
    }

    if (stabilityChanged) notifyListeners();
  }

  /// Waits for [delay] of stillness, then runs [onSettled]. A turned or
  /// tilted phone restarts the wait at once; a jolt from the desk only does if
  /// it outlasts the shake grace, so a busy desk can still arm a session.
  void _awaitPlacement(MotionReading reading, Duration delay, VoidCallback onSettled) {
    final now = _now();
    if (!reading.settled) {
      if (reading.displaced) {
        _stableSince = null;
        _unsettledSince = null;
        return;
      }
      final unsettled = _unsettledSince ??= now;
      if (now.difference(unsettled) > _guard.thresholds.shakeGrace) {
        _stableSince = null;
      }
      return;
    }
    _unsettledSince = null;
    final since = _stableSince ??= now;
    if (now.difference(since) >= delay) onSettled();
  }

  void _watchForPickup(MotionReading reading) {
    if (_pickup.observe(reading, _now())) _interrupt();
  }

  void _begin() {
    _stage = SessionStage.focusing;
    _resetWatch();
    _alerts.started();
    notifyListeners();
  }

  void _recover() {
    _stage = SessionStage.focusing;
    _resetWatch();
    _alerts.started();
    notifyListeners();
  }

  void _interrupt() {
    if (_stage != SessionStage.focusing) return;
    _stage = SessionStage.interrupted;
    _interruptions += 1;
    _unbrokenSeconds = 0;
    _resetWatch();
    _alerts.warn();
    _saveCheckpoint();
    notifyListeners();
  }

  void _onTick() {
    final now = _now();
    final last = _lastBeat;
    _lastBeat = now;
    if (_away) return;
    if (last != null && now.difference(last) > maxHeartbeatGap) {
      // Frozen without being told: treat it like leaving the app, and do not
      // pay for this beat.
      if (_stage == SessionStage.focusing) _interrupt();
      return;
    }

    switch (_stage) {
      case SessionStage.focusing:
        _earned += CreditRules.creditsForSecond(unbrokenRun);
        _unbrokenSeconds += 1;
        _timer.tick();
        if (_timer.isComplete) {
          _finish(completed: true);
        } else {
          if (_timer.elapsedSeconds % checkpointEvery.inSeconds == 0) {
            _saveCheckpoint();
          }
          notifyListeners();
        }
      case SessionStage.interrupted:
        _alerts.warn();
        notifyListeners();
      case SessionStage.arming:
      case SessionStage.paused:
      case SessionStage.complete:
        break;
    }
  }

  void _finish({required bool completed}) {
    if (_finished) return;
    _finished = true;
    _stage = SessionStage.complete;
    _resetWatch();
    if (completed) _alerts.finished();

    unawaited(_stopListening());

    final record = SessionRecord(
      startedAt: _startedAt ?? _now(),
      focused: _timer.elapsed,
      creditsEarned: _earned,
      interruptions: _interruptions,
      mode: config.mode,
      method: config.method,
      completed: completed,
    );
    notifyListeners();
    onComplete?.call(record);
  }

  void _resetWatch() {
    _stableSince = null;
    _unsettledSince = null;
    _pickup.reset();
  }

  void _saveCheckpoint() {
    final callback = onCheckpoint;
    final snapshot = checkpoint;
    if (callback == null || snapshot == null || _finished) return;
    callback(snapshot);
  }

  /// Rebuilding on every raw sample would repaint ~50 times a second, so the
  /// ring only redraws when the reading moves a visible amount.
  bool _updateStability(double value) {
    if ((value - _stability).abs() < 0.05) return false;
    _stability = value;
    return true;
  }

  /// Cancels both subscriptions at once, so the heartbeat stops the moment
  /// the session does rather than after the sensor feed has wound down.
  Future<void> _stopListening() async {
    final samples = _samples;
    final ticks = _ticks;
    _samples = null;
    _ticks = null;
    await Future.wait([
      if (samples != null) samples.cancel(),
      if (ticks != null) ticks.cancel(),
    ]);
  }

  @override
  void dispose() {
    unawaited(_stopListening());
    unawaited(_feed.dispose());
    super.dispose();
  }
}
