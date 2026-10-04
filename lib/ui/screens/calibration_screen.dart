import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/sensor_feed.dart';
import '../../domain/desk_calibration.dart';
import '../../domain/motion_guard.dart';
import '../../state/calibration_controller.dart';
import '../../state/session_alerts.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_ring.dart';

/// Listens to the desk for a few seconds and suggests a sensitivity.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, this.feed, this.alerts, this.clock});

  /// Overrides for tests, which drive the recording from a fake feed.
  @visibleForTesting
  final SensorFeed? feed;
  @visibleForTesting
  final SessionAlerts? alerts;
  @visibleForTesting
  final DateTime Function()? clock;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  late final CalibrationController _calibration;

  @override
  void initState() {
    super.initState();
    _calibration = CalibrationController(
      feed: widget.feed ?? DeviceSensorFeed(),
      alerts: widget.alerts ?? const PlatformAlerts(),
      clock: widget.clock,
    )..start();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _calibration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate'),
        backgroundColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.2,
            colors: FocusPalette.restingGradient,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: AnimatedBuilder(
              animation: _calibration,
              builder: (context, _) => _FillOrScroll(
                child: switch (_calibration.stage) {
                  CalibrationStage.waiting => _Waiting(
                      pickedUpEarly: _calibration.pickedUpEarly,
                    ),
                  CalibrationStage.measuring => _Measuring(
                      progress: _calibration.progress,
                    ),
                  CalibrationStage.done => _Result(
                      result: _calibration.result!,
                      onRetry: _calibration.restart,
                      onUse: _apply,
                    ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply(Sensitivity level) async {
    await WalletScope.of(context).setSensitivity(level);
    if (mounted) Navigator.of(context).pop();
  }
}

/// Fills the screen so the spacers can centre the content, and scrolls
/// instead of overflowing on a short phone.
class _FillOrScroll extends StatelessWidget {
  const _FillOrScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.pickedUpEarly});

  final bool pickedUpEarly;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        const StatusRing(
          icon: Icons.screen_lock_portrait_rounded,
          color: FocusPalette.focusSoft,
        ),
        const SizedBox(height: 28),
        Text(
          pickedUpEarly ? 'Turned over too early' : 'Put the phone face-down',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          pickedUpEarly
              ? 'Put it back down to start again. It buzzes when it is done.'
              : 'Lay it where it sits during a session and keep working — '
                  'type, write, set your cup down. Recording starts once it '
                  'settles and takes ${DeskCalibration.duration.inSeconds} '
                  'seconds. It buzzes when it is done.',
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        const Spacer(),
      ],
    );
  }
}

class _Measuring extends StatelessWidget {
  const _Measuring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        StatusRing(
          icon: Icons.graphic_eq_rounded,
          color: FocusPalette.focusSoft,
          progress: progress,
          caption: 'Listening',
        ),
        const SizedBox(height: 28),
        Text(
          'Keep working as usual',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        const Text(
          'Turning the phone over now starts the recording again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        const Spacer(),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.result,
    required this.onRetry,
    required this.onUse,
  });

  final CalibrationResult result;
  final VoidCallback onRetry;
  final ValueChanged<Sensitivity> onUse;

  @override
  Widget build(BuildContext context) {
    final recommended = result.recommended;
    final title = recommended == null
        ? 'That was not a desk'
        : 'Suggested: ${recommended.label}';
    final body = recommended == null
        ? 'The phone spent too much of the recording off its face. Lay it '
            'face-down and leave it there until it buzzes.'
        : result.tooShaky
            ? 'Even the most forgiving level would have alarmed here. Relaxed '
                'is the best fit, but a steadier spot will save you false '
                'alarms.'
            : '${recommended.label} is the strictest level that stayed quiet '
                'on this desk, with room to spare.';

    return Column(
      children: [
        const Spacer(),
        StatusRing(
          icon:
              recommended == null ? Icons.replay_rounded : Icons.check_rounded,
          color: recommended == null ? FocusPalette.alarm : FocusPalette.done,
          progress: 1,
        ),
        const SizedBox(height: 26),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        if (recommended != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('FALSE ALARMS ON THIS DESK', style: kEyebrow),
                ),
                const SizedBox(height: 8),
                for (final level in Sensitivity.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Text(
                          level.label,
                          style: TextStyle(
                            fontWeight: level == recommended
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _alarms(result.falseAlarms[level] ?? 0),
                          style: TextStyle(
                            color: (result.falseAlarms[level] ?? 0) == 0
                                ? FocusPalette.done
                                : Colors.white54,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const Spacer(),
        if (recommended != null)
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: () => onUse(recommended),
              child: Text('Use ${recommended.label}'),
            ),
          ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Try again'),
        ),
      ],
    );
  }

  static String _alarms(int count) => switch (count) {
        0 => 'None',
        1 => '1 alarm',
        _ => '$count alarms',
      };
}
