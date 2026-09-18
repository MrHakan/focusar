import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sensor_feed.dart';
import '../domain/credit_rules.dart';
import '../domain/focus_clock.dart';
import '../domain/motion_guard.dart';
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
  })  : _feed = feed,
        _guard = guard,
        _alerts = alerts,
        _ticker = ticker,
        _tickInterval = tickInterval,
        _now = clock ?? DateTime.now,
        _timer = config.isTimed
            ? FocusClock.countdown(config.target)
            : FocusClock.countUp();

  /// How long the phone must sit still before the clock starts.
  static const Duration armDelay = Duration(milliseconds: 1200);

  /// How long it must sit still again to shake off an interruption.
  static const Duration resumeDelay = Duration(seconds: 1);

  /// Brief movement is forgiven for this long before the alarm starts.
  static const Duration disturbanceGrace = Duration(milliseconds: 160);

  final SessionConfig config;

  /// Called once, with the session's record, when it ends.
  final void Function(SessionRecord record)? onComplete;

  final SensorFeed _feed;
  final MotionGuard _guard;
  final SessionAlerts _alerts;
  final TickSource _ticker;
  final Duration _tickInterval;
  final DateTime Function() _now;
  final FocusClock _timer;

  StreamSubscription<MotionSample>? _samples;
  StreamSubscription<void>? _ticks;

  SessionStage _stage = SessionStage.arming;
  DateTime? _startedAt;
  DateTime? _stableSince;
  DateTime? _disturbedSince;
  int _unbrokenSeconds = 0;
  int _interruptions = 0;
  double _earned = 0;
  double _stability = 0;
  bool _finished = false;

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

  /// Starts listening to the sensors. Call once.
  void start() {
    if (_samples != null) return;
    _startedAt = _now();
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
    _stableSince = null;
    _disturbedSince = null;
    notifyListeners();
  }

  /// Returns to waiting-for-the-phone. The clock keeps whatever it had.
  void resume() {
    if (_stage != SessionStage.paused) return;
    _stage = SessionStage.arming;
    _stableSince = null;
    _disturbedSince = null;
    notifyListeners();
  }

  /// The app went to the background mid-session, which counts as a pick-up.
  void reportLeftApp() {
    if (_stage == SessionStage.focusing) _interrupt();
  }

  /// Ends the session early but keeps what was earned.
  void stop() => _finish(completed: false);

  void _onSample(MotionSample sample) {
    if (_stage == SessionStage.complete) return;

    final reading = _guard.evaluate(
      x: sample.x,
      y: sample.y,
      z: sample.z,
      rotationRate: sample.rotationRate,
      userAcceleration: sample.userAcceleration,
    );
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

  /// Waits for [delay] of uninterrupted stillness, then runs [onSettled].
  void _awaitPlacement(MotionReading reading, Duration delay, VoidCallback onSettled) {
    if (!reading.settled) {
      _stableSince = null;
      return;
    }
    final now = _now();
    final since = _stableSince ??= now;
    if (now.difference(since) >= delay) onSettled();
  }

  void _watchForPickup(MotionReading reading) {
    if (reading.sudden) {
      _interrupt();
      return;
    }
    if (!reading.disturbed) {
      _disturbedSince = null;
      return;
    }
    final now = _now();
    final since = _disturbedSince ??= now;
    if (now.difference(since) >= disturbanceGrace) _interrupt();
  }

  void _begin() {
    _stage = SessionStage.focusing;
    _stableSince = null;
    _disturbedSince = null;
    _alerts.started();
    notifyListeners();
  }

  void _recover() {
    _stage = SessionStage.focusing;
    _stableSince = null;
    _disturbedSince = null;
    _alerts.started();
    notifyListeners();
  }

  void _interrupt() {
    if (_stage != SessionStage.focusing) return;
    _stage = SessionStage.interrupted;
    _interruptions += 1;
    _unbrokenSeconds = 0;
    _stableSince = null;
    _disturbedSince = null;
    _alerts.warn();
    notifyListeners();
  }

  void _onTick() {
    switch (_stage) {
      case SessionStage.focusing:
        _earned += CreditRules.creditsForSecond(unbrokenRun);
        _unbrokenSeconds += 1;
        _timer.tick();
        if (_timer.isComplete) {
          _finish(completed: true);
        } else {
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
    _stableSince = null;
    _disturbedSince = null;
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

  /// Rebuilding on every raw sample would repaint ~50 times a second, so the
  /// ring only redraws when the reading moves a visible amount.
  bool _updateStability(double value) {
    if ((value - _stability).abs() < 0.05) return false;
    _stability = value;
    return true;
  }

  Future<void> _stopListening() async {
    await _samples?.cancel();
    await _ticks?.cancel();
    _samples = null;
    _ticks = null;
  }

  @override
  void dispose() {
    unawaited(_stopListening());
    unawaited(_feed.dispose());
    super.dispose();
  }
}
