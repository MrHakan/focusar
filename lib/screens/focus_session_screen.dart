import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/focus_timer.dart';

enum SessionStage { waiting, focusing, warning, complete }

class FocusSessionScreen extends StatefulWidget {
  const FocusSessionScreen({required this.duration, super.key});

  final Duration duration;

  @override
  State<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<FocusSessionScreen>
    with WidgetsBindingObserver {
  late final FocusTimer _clock;
  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  Timer? _tickTimer;
  Timer? _alarmTimer;
  DateTime? _stableSince;
  DateTime? _unstableSince;
  SessionStage _stage = SessionStage.waiting;
  bool _faceDown = false;
  double _rotationRate = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = FocusTimer(widget.duration);
    WakelockPlus.enable();
    _accelerometer = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onAccelerometer);
    _gyroscope = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      _rotationRate = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((_stage == SessionStage.focusing || _stage == SessionStage.warning) &&
        state != AppLifecycleState.resumed) {
      _enterWarning();
    }
  }

  void _onAccelerometer(AccelerometerEvent event) {
    if (_stage == SessionStage.complete) return;
    final now = DateTime.now();
    final gravity = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    _faceDown = event.z < -7 && event.x.abs() < 4 && event.y.abs() < 4;
    final still = (gravity - 9.81).abs() < 1.25 && _rotationRate < 0.55;
    final safelyPlaced = _faceDown && still;

    if (_stage == SessionStage.waiting) {
      if (safelyPlaced) {
        _stableSince ??= now;
        if (now.difference(_stableSince!) > const Duration(milliseconds: 1200)) {
          _startFocus();
        }
      } else {
        _stableSince = null;
      }
      return;
    }

    if (_stage == SessionStage.focusing) {
      if (!safelyPlaced) {
        _unstableSince ??= now;
        if (now.difference(_unstableSince!) > const Duration(milliseconds: 220)) {
          _enterWarning();
        }
      } else {
        _unstableSince = null;
      }
      return;
    }

    if (_stage == SessionStage.warning) {
      if (safelyPlaced) {
        _stableSince ??= now;
        if (now.difference(_stableSince!) > const Duration(milliseconds: 1000)) {
          _resumeFocus();
        }
      } else {
        _stableSince = null;
      }
    }
  }

  void _startFocus() {
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = SessionStage.focusing;
      _stableSince = null;
    });
  }

  void _enterWarning() {
    if (!mounted || _stage == SessionStage.complete || _stage == SessionStage.warning) return;
    setState(() {
      _stage = SessionStage.warning;
      _stableSince = null;
    });
    _alert();
    _alarmTimer?.cancel();
    _alarmTimer = Timer.periodic(const Duration(milliseconds: 900), (_) => _alert());
  }

  void _resumeFocus() {
    _alarmTimer?.cancel();
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = SessionStage.focusing;
      _stableSince = null;
      _unstableSince = null;
    });
  }

  void _alert() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  void _tick() {
    if (!mounted || _stage == SessionStage.complete || _stage == SessionStage.waiting) return;
    _clock.tick(paused: _stage == SessionStage.warning);
    if (_clock.isComplete) {
      _alarmTimer?.cancel();
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.alert);
      setState(() => _stage = SessionStage.complete);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelerometer?.cancel();
    _gyroscope?.cancel();
    _tickTimer?.cancel();
    _alarmTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warning = _stage == SessionStage.warning;
    final complete = _stage == SessionStage.complete;
    final waiting = _stage == SessionStage.waiting;

    return PopScope(
      canPop: complete,
      child: Scaffold(
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 1.15,
              colors: warning
                  ? const [Color(0xFF7D2038), Color(0xFF160811)]
                  : complete
                      ? const [Color(0xFF176B58), Color(0xFF061D1B)]
                      : const [Color(0xFF214EA7), Color(0xFF061226)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onLongPress: _confirmEnd,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.close_rounded, color: Colors.white38),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    waiting
                        ? 'Ready when you are'
                        : warning
                            ? 'No phone allowed'
                            : complete
                                ? 'Focus complete'
                                : 'Locked in',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    waiting
                        ? 'Place the phone face-down inside your AR zone.'
                        : warning
                            ? "You're not done. Put the phone back face-down."
                            : complete
                                ? 'You stayed with it. Nice work.'
                                : 'Your timer pauses if the phone is lifted.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 46),
                  _StatusRing(stage: _stage),
                  const SizedBox(height: 42),
                  if (!waiting)
                    Text(
                      formatClock(_clock.remainingSeconds),
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 58,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  if (warning)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('TIMER PAUSED', style: TextStyle(letterSpacing: 2, color: Colors.white70)),
                    ),
                  if (complete) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!complete)
                    const Text(
                      'Long-press × for an emergency exit',
                      style: TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmEnd() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End focus session?'),
        content: const Text('Your unfinished session will not be counted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep focusing')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End session')),
        ],
      ),
    );
    if (end == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

class _StatusRing extends StatelessWidget {
  const _StatusRing({required this.stage});

  final SessionStage stage;

  @override
  Widget build(BuildContext context) {
    final warning = stage == SessionStage.warning;
    final complete = stage == SessionStage.complete;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 184,
      height: 184,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          width: 8,
          color: warning
              ? const Color(0xFFFF668A)
              : complete
                  ? const Color(0xFF64E1BD)
                  : const Color(0xFF9CB0FF),
        ),
        boxShadow: [
          BoxShadow(
            color: (warning ? const Color(0xFFFF426F) : const Color(0xFF5B7CFF)).withValues(alpha: 0.38),
            blurRadius: 38,
          ),
        ],
      ),
      child: Icon(
        warning
            ? Icons.vibration_rounded
            : complete
                ? Icons.check_rounded
                : stage == SessionStage.waiting
                    ? Icons.screen_lock_portrait_rounded
                    : Icons.lock_rounded,
        size: 72,
      ),
    );
  }
}
