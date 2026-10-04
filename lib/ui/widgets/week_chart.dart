import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/focus_clock.dart';
import '../../domain/progress_log.dart';
import '../../theme/app_theme.dart';

/// Focus per day across one week, as columns against the daily goal.
///
/// One series, one colour. Tapping a column shows its value on the cap; the
/// whole column slot is the hit target, not just the bar. The values are also
/// listed day by day under the chart, so nothing here is tap-only.
class WeekChart extends StatelessWidget {
  const WeekChart({
    required this.week,
    required this.goal,
    required this.onSelect,
    super.key,
    this.today,
    this.selected,
  });

  final WeekSummary week;
  final Duration goal;

  /// Index of today in the week, 0 = Monday, if the week holds it.
  final int? today;

  /// Index of the column whose value is shown.
  final int? selected;

  final ValueChanged<int> onSelect;

  static const double height = 196;

  @override
  Widget build(BuildContext context) {
    final summary = [
      for (final day in week.days)
        '${_dayNames[day.day.weekday - 1]} ${formatSpan(day.focused)}',
    ].join(', ');

    return Semantics(
      label: 'Focus per day, goal ${formatSpan(goal)}: $summary',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _ChartLayout(constraints.maxWidth);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final index = layout.columnAt(details.localPosition.dx);
              if (index != null) onSelect(index);
            },
            child: CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _WeekChartPainter(
                base: DefaultTextStyle.of(context).style,
                week: week,
                goal: goal,
                today: today,
                selected: selected,
                layout: layout,
              ),
            ),
          );
        },
      ),
    );
  }
}

const List<String> _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Where everything goes, shared by the painter and the hit test.
class _ChartLayout {
  _ChartLayout(this.width);

  final double width;

  /// Room above the plot for a value on the tallest cap.
  static const double top = 22;

  /// Room below the plot for the day initials.
  static const double axisBand = 30;

  /// Room on the right for the goal label.
  static const double gutter = 46;

  static const double maxBarWidth = 24;

  double get plotWidth => math.max(0, width - gutter);
  double get plotBottom => WeekChart.height - axisBand;
  double get plotHeight => plotBottom - top;
  double get slot => plotWidth / 7;
  double get barWidth => math.min(maxBarWidth, slot * 0.55);

  double centerOf(int index) => slot * index + slot / 2;

  int? columnAt(double dx) {
    if (dx < 0 || dx > plotWidth || slot <= 0) return null;
    return (dx / slot).floor().clamp(0, 6);
  }
}

class _WeekChartPainter extends CustomPainter {
  _WeekChartPainter({
    required this.base,
    required this.week,
    required this.goal,
    required this.today,
    required this.selected,
    required this.layout,
  });

  /// The surrounding text style, so labels use the app's font.
  final TextStyle base;
  final WeekSummary week;
  final Duration goal;
  final int? today;
  final int? selected;
  final _ChartLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final ceiling = _ceiling();
    double yOf(Duration value) =>
        layout.plotBottom - layout.plotHeight * (value.inSeconds / ceiling);

    // The selected column's slot, faintly, so the tap target reads as one.
    final picked = selected;
    if (picked != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            layout.slot * picked + 2,
            _ChartLayout.top - 6,
            layout.slot - 4,
            layout.plotHeight + 6,
          ),
          const Radius.circular(10),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
    }

    // Bars: square at the baseline, 4px round at the data end.
    final barPaint = Paint()..color = FocusPalette.chart;
    for (var i = 0; i < 7; i++) {
      final focused = week.days[i].focused;
      if (focused <= Duration.zero) continue;
      final x = layout.centerOf(i) - layout.barWidth / 2;
      final y = math.min(yOf(focused), layout.plotBottom - 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(x, y, x + layout.barWidth, layout.plotBottom),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        barPaint,
      );
    }

    // Baseline: a solid hairline.
    canvas.drawLine(
      Offset(0, layout.plotBottom),
      Offset(layout.plotWidth, layout.plotBottom),
      Paint()
        ..color = Colors.white24
        ..strokeWidth = 1,
    );

    // Goal: a dashed threshold, labelled in the gutter.
    if (goal > Duration.zero) {
      final goalY = yOf(goal);
      final dash = Paint()
        ..color = Colors.white54
        ..strokeWidth = 1;
      for (var x = 0.0; x < layout.plotWidth; x += 7) {
        canvas.drawLine(
          Offset(x, goalY),
          Offset(math.min(x + 4, layout.plotWidth), goalY),
          dash,
        );
      }
      _text(
        canvas,
        'Goal\n${formatSpan(goal)}',
        Offset(layout.plotWidth + 8, goalY),
        const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.15),
        alignLeft: true,
      );
    }

    // The selected value, on its cap.
    if (picked != null) {
      final focused = week.days[picked].focused;
      final capY = focused > Duration.zero ? yOf(focused) : layout.plotBottom;
      _text(
        canvas,
        formatSpan(focused),
        Offset(layout.centerOf(picked), capY - 12),
        const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    // Day initials, today in full ink, days to come faded. A goal-met day
    // gets a check, so the state is never colour alone.
    for (var i = 0; i < 7; i++) {
      final future = today != null && i > today!;
      final style = TextStyle(
        color: i == today
            ? Colors.white
            : future
                ? Colors.white24
                : Colors.white54,
        fontSize: 11.5,
        fontWeight: i == today ? FontWeight.w800 : FontWeight.w600,
      );
      _text(canvas, _dayInitials[i], Offset(layout.centerOf(i), layout.plotBottom + 12), style);
      if (week.days[i].meets(goal)) {
        _icon(canvas, Icons.check_rounded, Offset(layout.centerOf(i), layout.plotBottom + 25));
      }
    }
  }

  /// The top of the scale: room above both the goal and the busiest day.
  double _ceiling() {
    final highest = math.max(
      goal.inSeconds * 1.25,
      week.longestDay.inSeconds * 1.1,
    );
    return math.max(highest, const Duration(minutes: 30).inSeconds.toDouble());
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style, {
    bool alignLeft = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: base.merge(style)),
      textDirection: TextDirection.ltr,
      textAlign: alignLeft ? TextAlign.left : TextAlign.center,
    )..layout();
    final dx = alignLeft ? anchor.dx : anchor.dx - painter.width / 2;
    painter.paint(canvas, Offset(dx, anchor.dy - painter.height / 2));
  }

  void _icon(Canvas canvas, IconData icon, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 11,
          color: FocusPalette.done,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_WeekChartPainter old) =>
      old.week != week ||
      old.goal != goal ||
      old.today != today ||
      old.selected != selected ||
      old.layout.width != layout.width;
}
