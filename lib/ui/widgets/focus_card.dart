import 'package:flutter/material.dart';

import '../../domain/credit_rules.dart';
import '../../domain/focus_clock.dart';
import '../../theme/app_theme.dart';

/// The crimson card that carries the balance: what you have earned, and how
/// much screen time it buys back.
class FocusCard extends StatelessWidget {
  const FocusCard({
    required this.credits,
    super.key,
    this.pending = 0,
    this.compact = false,
  });

  /// Credits already banked.
  final double credits;

  /// Credits earned in the session that is running right now, shown as a
  /// live addition to the balance.
  final double pending;

  /// A shorter card for the session screen, where space is tight.
  final bool compact;

  double get _total => credits + pending;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: compact ? 2.35 : 1.62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 16 : 22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [FocusPalette.card, FocusPalette.cardDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: FocusPalette.card.withValues(alpha: 0.34),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 16 : 22),
          child: CustomPaint(
            painter: const _ChevronPainter(),
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    color: Colors.white,
                    size: compact ? 20 : 26,
                  ),
                  const Spacer(),
                  _Balance(total: _total, compact: compact),
                  SizedBox(height: compact ? 2 : 5),
                  Text(
                    '${pending > 0 ? '+ ' : ''}'
                    '${formatSpan(CreditRules.screenTimeFor(_total))} screen time',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: compact ? 11.5 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'FOCUS CARD',
                        style: kEyebrow.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: compact ? 9 : 11,
                        ),
                      ),
                      const Spacer(),
                      _Chip(compact: compact),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.total, required this.compact});

  final double total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            CreditRules.formatCredits(total),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 26 : 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'credits',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The little contact plate every card has.
class _Chip extends StatelessWidget {
  const _Chip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 24 : 32,
      height: compact ? 18 : 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.92),
            Colors.white.withValues(alpha: 0.55),
          ],
        ),
      ),
    );
  }
}

/// The repeating chevron watermark across the card face.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.085)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    const step = 22.0;
    const wing = 9.0;
    for (var y = -wing; y < size.height + wing; y += step) {
      for (var x = -wing; x < size.width + wing; x += step) {
        canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..lineTo(x + wing, y + wing)
            ..lineTo(x, y + wing * 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}
