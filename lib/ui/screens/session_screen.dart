import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/sensor_feed.dart';
import '../../domain/focus_clock.dart';
import '../../domain/session_mode.dart';
import '../../domain/session_record.dart';
import '../../state/session_alerts.dart';
import '../../state/session_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/focus_card.dart';
import '../widgets/status_ring.dart';

/// The guarded session: the phone goes face-down, the clock runs, and credits
/// accrue for as long as it stays there.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    required this.config,
    super.key,
    this.feed,
    this.alerts,
    this.ticker,
    this.clock,
  });

  final SessionConfig config;

  /// Overrides for tests, which drive the session from a fake feed and a
  /// hand-advanced heartbeat instead of the device.
  @visibleForTesting
  final SensorFeed? feed;
  @visibleForTesting
  final SessionAlerts? alerts;
  @visibleForTesting
  final TickSource? ticker;
  @visibleForTesting
  final DateTime Function()? clock;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  late final SessionController _session;
  WalletController? _wallet;
  SessionRecord? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = SessionController(
      config: widget.config,
      feed: widget.feed ?? DeviceSensorFeed(),
      alerts: widget.alerts ?? const PlatformAlerts(),
      ticker: widget.ticker ?? defaultTickSource,
      clock: widget.clock,
      onComplete: _onComplete,
    )..start();
    WakelockPlus.enable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wallet = WalletScope.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _session.reportLeftApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _session.dispose();
    super.dispose();
  }

  /// The controller has already notified by the time this runs, so the summary
  /// needs a frame of its own to appear.
  void _onComplete(SessionRecord record) {
    final wallet = _wallet;
    if (wallet != null) unawaited(wallet.commit(record));
    if (mounted) setState(() => _result = record);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        final stage = _session.stage;
        final complete = stage == SessionStage.complete;
        final copy = _SessionCopy.of(stage, widget.config.mode);

        return PopScope(
          canPop: complete,
          child: Scaffold(
            body: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 1.2,
                  colors: _gradientFor(stage),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  child: Column(
                    children: [
                      _TopBar(
                        config: widget.config,
                        onExit: complete ? _leave : _confirmExit,
                        complete: complete,
                      ),
                      if (_couponWaiting) const _CouponBanner(),
                      const Spacer(),
                      Text(copy.title, style: _titleStyle(context)),
                      const SizedBox(height: 8),
                      Text(
                        copy.body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _SessionBody(session: _session, stage: stage),
                      const Spacer(),
                      _Footer(
                        session: _session,
                        wallet: _wallet,
                        result: _result,
                        onDone: _leave,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _couponWaiting {
    final wallet = _wallet;
    return wallet != null &&
        wallet.activeCoupons.isNotEmpty &&
        _session.stage != SessionStage.complete;
  }

  TextStyle? _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800);

  List<Color> _gradientFor(SessionStage stage) => switch (stage) {
        SessionStage.arming => FocusPalette.restingGradient,
        SessionStage.focusing => widget.config.isTimed
            ? FocusPalette.lockedGradient
            : FocusPalette.earningGradient,
        SessionStage.interrupted => FocusPalette.alarmGradient,
        SessionStage.paused => FocusPalette.restingGradient,
        SessionStage.complete => FocusPalette.doneGradient,
      };

  void _leave() => Navigator.of(context).popUntil((route) => route.isFirst);

  Future<void> _confirmExit() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'You keep the credits you have already earned, but the run stops here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep focusing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;
    _session.stop();
  }
}

/// The wording for each stage, kept in one place so the states read as one voice.
class _SessionCopy {
  const _SessionCopy(this.title, this.body);

  final String title;
  final String body;

  static _SessionCopy of(SessionStage stage, FocusMode mode) => switch (stage) {
        SessionStage.arming => const _SessionCopy(
            'Ready when you are',
            'Place the phone face-down and let it settle.',
          ),
        SessionStage.focusing => mode == FocusMode.timed
            ? const _SessionCopy('Locked in', 'Keep your phone still.')
            : const _SessionCopy(
                'Earning screen time',
                'Every minute here buys a minute back.',
              ),
        SessionStage.interrupted => const _SessionCopy(
            'No phone allowed',
            "You're not done. Get back to work.",
          ),
        SessionStage.paused => const _SessionCopy(
            'Paused',
            'Nothing is counting. Resume when you are ready.',
          ),
        SessionStage.complete => const _SessionCopy(
            'Focus complete',
            'You stayed with it. Nice work.',
          ),
      };
}

/// The clock, the ring, and the card — whichever the stage calls for.
class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.session, required this.stage});

  final SessionController session;
  final SessionStage stage;

  @override
  Widget build(BuildContext context) {
    if (stage == SessionStage.focusing && !session.config.isTimed) {
      return Column(
        children: [
          Text(session.display, style: _clockStyle(60)),
          const SizedBox(height: 6),
          Text(
            'Earning screen time...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          _LiveCard(session: session),
        ],
      );
    }

    return Column(
      children: [
        StatusRing(
          icon: _iconFor(stage),
          color: _ringColor(stage),
          progress: stage == SessionStage.arming ? 0 : session.progress,
          caption: stage == SessionStage.interrupted ? 'Keep me still' : null,
          pulse: stage == SessionStage.interrupted ? 1.04 : 1,
        ),
        if (stage != SessionStage.arming) ...[
          const SizedBox(height: 26),
          Text(session.display, style: _clockStyle(52)),
        ],
        if (stage == SessionStage.interrupted) ...[
          const SizedBox(height: 8),
          const Text(
            'TIMER PAUSED',
            style: TextStyle(letterSpacing: 2.4, color: Colors.white54, fontSize: 12),
          ),
        ],
      ],
    );
  }

  TextStyle _clockStyle(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w300,
        letterSpacing: -1,
        color: Colors.white,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static IconData _iconFor(SessionStage stage) => switch (stage) {
        SessionStage.arming => Icons.screen_lock_portrait_rounded,
        SessionStage.focusing => Icons.lock_rounded,
        SessionStage.interrupted => Icons.vibration_rounded,
        SessionStage.paused => Icons.pause_rounded,
        SessionStage.complete => Icons.check_rounded,
      };

  static Color _ringColor(SessionStage stage) => switch (stage) {
        SessionStage.interrupted => FocusPalette.alarm,
        SessionStage.complete => FocusPalette.done,
        SessionStage.paused => Colors.white54,
        SessionStage.arming || SessionStage.focusing => FocusPalette.focusSoft,
      };
}

/// The focus card with this session's earnings folded into the balance.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: FocusCard(
        credits: wallet.balance,
        pending: session.earnedCredits,
        compact: true,
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.config,
    required this.onExit,
    required this.complete,
  });

  final SessionConfig config;
  final VoidCallback onExit;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                config.usesAr ? Icons.view_in_ar_rounded : Icons.sensors_rounded,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                config.usesAr ? 'AR + SENSOR' : 'MOTION SENSOR',
                style: kEyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.3),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onExit,
          tooltip: complete ? 'Close' : 'End session',
          icon: const Icon(Icons.close_rounded, color: Colors.white38),
        ),
      ],
    );
  }
}

/// A nudge that there is already screen time waiting to be spent.
class _CouponBanner extends StatelessWidget {
  const _CouponBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FocusPalette.card.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FocusPalette.card.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.local_activity_rounded, size: 17, color: FocusPalette.card),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your coupon is waiting. Finish this block before you spend it.',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pause and resume while running; the summary once the session is done.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.session,
    required this.wallet,
    required this.result,
    required this.onDone,
  });

  final SessionController session;
  final WalletController? wallet;
  final SessionRecord? result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final stage = session.stage;

    if (stage == SessionStage.complete) {
      final record = result;
      return Column(
        children: [
          if (record != null) _Summary(record: record),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(onPressed: onDone, child: const Text('Done')),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (stage == SessionStage.focusing || stage == SessionStage.interrupted)
          _PillButton(
            icon: Icons.pause_rounded,
            label: 'Pause',
            onPressed: session.pause,
          )
        else if (stage == SessionStage.paused)
          _PillButton(
            icon: Icons.play_arrow_rounded,
            label: 'Resume',
            onPressed: session.resume,
          ),
        const SizedBox(height: 12),
        Text(
          _hintFor(stage),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white30, fontSize: 12),
        ),
      ],
    );
  }

  String _hintFor(SessionStage stage) => switch (stage) {
        SessionStage.focusing => session.tier.multiplier > 1
            ? '${session.tier.label} — earning ${session.tier.multiplierLabel}'
            : 'Stay unbroken for 25 minutes to earn 1.25x',
        SessionStage.interrupted => 'Put it back face-down to resume.',
        SessionStage.paused => 'Credits are not accruing while paused.',
        SessionStage.arming || SessionStage.complete => '',
      };
}

/// The white pill from the session screen.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: FocusPalette.ink,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(label: 'FOCUSED', value: formatSpan(record.focused)),
          _Stat(
            label: 'EARNED',
            value: record.creditsEarned.toStringAsFixed(1),
          ),
          _Stat(label: 'PICK-UPS', value: '${record.interruptions}'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(label, style: kEyebrow.copyWith(fontSize: 10)),
      ],
    );
  }
}
