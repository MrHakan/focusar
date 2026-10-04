import 'package:flutter/material.dart';

import '../../domain/focus_clock.dart';
import '../../domain/focus_preferences.dart';
import '../../domain/progress_log.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/week_chart.dart';

/// Today against the daily goal, and the week behind it.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  /// Weeks back from the current one. 0 is this week.
  int _weeksBack = 0;

  /// The day the chart is showing a value for, 0 = Monday.
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final wallet = WalletScope.of(context);
    final now = wallet.now();
    final goal = wallet.preferences.dailyGoal;
    final thisWeek = ProgressLog.weekStartOf(now);
    final shown = DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7 * _weeksBack);
    final week = wallet.weekOf(shown);
    final previous = wallet.weekOf(DateTime(shown.year, shown.month, shown.day - 7));
    final first = wallet.progress.firstDay;
    final canGoBack = first != null && first.isBefore(shown);
    final todayIndex = _weeksBack == 0 ? now.weekday - 1 : null;
    final selected = _selected ?? todayIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
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
            _TodayCard(today: wallet.today, goal: goal),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _weeksBack == 0
                            ? 'THIS WEEK'
                            : _weeksBack == 1
                                ? 'LAST WEEK'
                                : '$_weeksBack WEEKS AGO',
                        style: kEyebrow,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _rangeLabel(week.start),
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous week',
                  onPressed: canGoBack ? () => _moveWeek(1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Next week',
                  onPressed: _weeksBack > 0 ? () => _moveWeek(-1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'FOCUSED',
                      value: formatSpan(week.focused),
                      detail: _compare(week.focused, previous.focused),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: 'PICK-UPS',
                      value: '${week.interruptions}',
                      detail: _perHour(week.interruptionsPerHour),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: 'GOAL DAYS',
                      value: '${week.daysMeeting(goal)}/7',
                      detail: '${week.sessions} session${week.sessions == 1 ? '' : 's'}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
              child: WeekChart(
                week: week,
                goal: goal,
                today: todayIndex,
                selected: selected,
                onSelect: (index) => setState(() => _selected = index),
              ),
            ),
            const SizedBox(height: 22),
            const Text('DAY BY DAY', style: kEyebrow),
            const SizedBox(height: 8),
            for (var i = 0; i < 7; i++)
              _DayRow(
                tally: week.days[i],
                goal: goal,
                isToday: i == todayIndex,
                isFuture: todayIndex != null && i > todayIndex,
              ),
            const SizedBox(height: 22),
            const Text('DAILY GOAL', style: kEyebrow),
            const SizedBox(height: 11),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final option in FocusPreferences.goalOptions)
                  ChoiceChip(
                    selected: option == goal,
                    onSelected: (_) => wallet.setDailyGoal(option),
                    label: Text(formatSpan(option)),
                    selectedColor: FocusPalette.focus,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: BorderSide(
                      color: option == goal ? Colors.transparent : Colors.white24,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'A session counts on the day it started. Pick-ups are the times '
              'the phone was lifted, turned, or left mid-focus.',
              style: TextStyle(color: Colors.white38, fontSize: 12.5, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  void _moveWeek(int by) => setState(() {
        _weeksBack += by;
        _selected = null;
      });

  static String? _compare(Duration current, Duration previous) {
    if (current == Duration.zero && previous == Duration.zero) return null;
    final delta = current - previous;
    if (delta.inMinutes == 0) return 'same as week before';
    final sign = delta.isNegative ? '−' : '+';
    return '$sign${formatSpan(delta.abs())} vs week before';
  }

  static String? _perHour(double? rate) {
    if (rate == null) return null;
    return '${rate.toStringAsFixed(1)} per hour';
  }
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `Sep 8 – 14`, or `Sep 29 – Oct 5` across a month end.
String _rangeLabel(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  final from = '${_months[start.month - 1]} ${start.day}';
  final to = end.month == start.month
      ? '${end.day}'
      : '${_months[end.month - 1]} ${end.day}';
  return '$from – $to';
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, required this.goal});

  final DayTally today;
  final Duration goal;

  @override
  Widget build(BuildContext context) {
    final share = goal.inSeconds == 0
        ? 0.0
        : (today.focused.inSeconds / goal.inSeconds).clamp(0.0, 1.0);
    final met = today.meets(goal);
    final left = goal - today.focused;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY', style: kEyebrow),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatSpan(today.focused),
                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'of ${formatSpan(goal)} goal',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(FocusPalette.chart),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (met) ...[
                const Icon(Icons.check_circle_rounded, size: 16, color: FocusPalette.done),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  met
                      ? 'Goal met'
                      : '${formatSpan(left)} to go · '
                          '${today.interruptions} pick-up${today.interruptions == 1 ? '' : 's'} so far',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: kEyebrow.copyWith(fontSize: 9.5, letterSpacing: 1.2)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail ?? ' ',
            maxLines: 2,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// One row of the week as text — the chart's table twin.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.tally,
    required this.goal,
    required this.isToday,
    required this.isFuture,
  });

  final DayTally tally;
  final Duration goal;
  final bool isToday;
  final bool isFuture;

  @override
  Widget build(BuildContext context) {
    final met = tally.meets(goal);
    final day = '${_weekdays[tally.day.weekday - 1]} ${tally.day.day}';
    final detail = tally.sessions == 0
        ? (isFuture ? '' : 'No sessions')
        : '${tally.interruptions} pick-up${tally.interruptions == 1 ? '' : 's'} · '
            '${tally.sessions} session${tally.sessions == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              day,
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isFuture ? Colors.white30 : Colors.white,
              ),
            ),
          ),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(color: Colors.white38, fontSize: 12.5),
            ),
          ),
          if (met) ...[
            const Icon(Icons.check_circle_rounded, size: 15, color: FocusPalette.done),
            const SizedBox(width: 5),
          ],
          Text(
            isFuture && tally.sessions == 0 ? '—' : formatSpan(tally.focused),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isFuture ? Colors.white30 : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
