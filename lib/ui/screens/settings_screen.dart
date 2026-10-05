import 'package:flutter/material.dart';

import '../../domain/desk_calibration.dart';
import '../../domain/motion_guard.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'calibration_screen.dart';

/// Motion sensitivity, and the desk calibration that suggests one.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final current = wallet.preferences.sensitivity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor'),
        backgroundColor: Colors.transparent,
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.5,
            colors: [Color(0xFF1E3B7A), FocusPalette.ink],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          children: [
            const Text('MOTION SENSITIVITY', style: kEyebrow),
            const SizedBox(height: 11),
            for (final level in Sensitivity.values) ...[
              _SensitivityTile(
                level: level,
                selected: level == current,
                onTap: () => wallet.setSensitivity(level),
              ),
              const SizedBox(height: 9),
            ],
            const SizedBox(height: 4),
            const Text(
              'Every level lets the desk shake longer than it lets the phone '
              'turn or tilt — vibration does not flip a phone over, a hand '
              'does. A change applies from the next session.',
              style: TextStyle(
                  color: Colors.white38, fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 22),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: FocusPalette.focusSoft),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Calibrate on this desk',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lay the phone face-down where you work and carry on for '
                    '${DeskCalibration.duration.inSeconds} seconds. FocusAR replays what it felt '
                    'through each level and suggests the strictest one that '
                    'stays quiet.',
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CalibrationScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.sensors_rounded),
                      label: const Text('Start calibration'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensitivityTile extends StatelessWidget {
  const _SensitivityTile({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final Sensitivity level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
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
                _iconFor(level),
                size: 21,
                color: selected ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.blurb,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: FocusPalette.focusSoft,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(Sensitivity level) => switch (level) {
        Sensitivity.strict => Icons.gpp_good_rounded,
        Sensitivity.balanced => Icons.balance_rounded,
        Sensitivity.relaxed => Icons.waves_rounded,
      };
}
