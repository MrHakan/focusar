import 'package:flutter/material.dart';

import '../widgets/glass_card.dart';
import 'ar_placement_screen.dart';
import 'focus_session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _durations = [25, 45, 60, 90];
  int _minutes = 25;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.8),
            radius: 1.45,
            colors: [Color(0xFF243B74), Color(0xFF071427)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B7CFF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.lock_rounded),
                    ),
                    const SizedBox(width: 13),
                    const Text('FocusAR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
                const Spacer(),
                Text(
                  'Put your phone down.\nPick your focus up.',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 47, height: 1.02),
                ),
                const SizedBox(height: 16),
                Text(
                  'Start instantly with motion sensors, or place an optional AR focus zone.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70, height: 1.45),
                ),
                const SizedBox(height: 34),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FOCUS LENGTH', style: TextStyle(fontSize: 12, letterSpacing: 1.7, color: Colors.white60)),
                      const SizedBox(height: 15),
                      Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: _durations.map((value) {
                          final selected = value == _minutes;
                          return ChoiceChip(
                            selected: selected,
                            onSelected: (_) => setState(() => _minutes = value),
                            label: Text('$value min'),
                            selectedColor: const Color(0xFF5B7CFF),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            side: BorderSide(color: selected ? Colors.transparent : Colors.white12),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 62,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FocusSessionScreen(
                          duration: Duration(minutes: _minutes),
                          method: FocusMethod.sensors,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.sensors_rounded),
                    label: const Text('Start with motion sensor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5B7CFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArPlacementScreen(duration: Duration(minutes: _minutes)),
                      ),
                    ),
                    icon: const Icon(Icons.view_in_ar_rounded),
                    label: const Text('Place AR focus zone'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
