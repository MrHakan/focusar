import 'package:flutter/material.dart';

import '../../domain/session_mode.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'ar_placement_screen.dart';
import 'session_screen.dart';
import 'wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<int> _durations = [25, 45, 60, 90];

  FocusMode _mode = FocusMode.timed;
  int _minutes = 25;

  SessionConfig _config(PlacementMethod method) => SessionConfig(
        mode: _mode,
        method: method,
        target: Duration(minutes: _minutes),
      );

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.85),
            radius: 1.5,
            colors: [Color(0xFF1E3B7A), FocusPalette.ink],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: FocusPalette.focus,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'FocusAR',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    _BalancePill(
                      label: wallet.balanceLabel,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  'Put your phone down.\nPick your focus up.',
                  style: text.displaySmall?.copyWith(
                    fontSize: 40,
                    height: 1.06,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Every focused minute earns a credit, and every credit buys a '
                  'minute of screen time back.',
                  style: text.bodyLarge?.copyWith(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 26),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SESSION TYPE', style: kEyebrow),
                      const SizedBox(height: 12),
                      for (final mode in FocusMode.values) ...[
                        _ModeTile(
                          mode: mode,
                          selected: mode == _mode,
                          onTap: () => setState(() => _mode = mode),
                        ),
                        if (mode != FocusMode.values.last) const SizedBox(height: 9),
                      ],
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _mode == FocusMode.timed
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 18),
                                  const Text('FOCUS LENGTH', style: kEyebrow),
                                  const SizedBox(height: 11),
                                  Wrap(
                                    spacing: 9,
                                    runSpacing: 9,
                                    children: [
                                      for (final value in _durations)
                                        ChoiceChip(
                                          selected: value == _minutes,
                                          onSelected: (_) =>
                                              setState(() => _minutes = value),
                                          label: Text('$value min'),
                                          selectedColor: FocusPalette.focus,
                                          backgroundColor:
                                              Colors.white.withValues(alpha: 0.06),
                                          side: BorderSide(
                                            color: value == _minutes
                                                ? Colors.transparent
                                                : Colors.white24,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: () => _open(
                      SessionScreen(config: _config(PlacementMethod.motionOnly)),
                    ),
                    icon: const Icon(Icons.sensors_rounded),
                    label: const Text('Start with motion sensor'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => _open(
                      ArPlacementScreen(config: _config(PlacementMethod.arZone)),
                    ),
                    icon: const Icon(Icons.view_in_ar_rounded),
                    label: const Text('Place AR focus zone'),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    wallet.streakDays > 0
                        ? '${wallet.streakDays} day streak · '
                            '${wallet.sessionsCompleted} sessions banked'
                        : 'Finish a session to start your streak.',
                    style: const TextStyle(color: Colors.white38, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final FocusMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? FocusPalette.focus.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected ? FocusPalette.focus : Colors.white12,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              mode == FocusMode.timed
                  ? Icons.hourglass_bottom_rounded
                  : Icons.all_inclusive_rounded,
              size: 21,
              color: selected ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.blurb,
                    style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 20, color: FocusPalette.focusSoft),
          ],
        ),
      ),
    );
  }
}

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.credit_card_rounded, size: 16, color: FocusPalette.card),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
