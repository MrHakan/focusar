import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ring at the heart of the session screen: a progress arc, an icon, and
/// an optional line of instruction inside it.
class StatusRing extends StatelessWidget {
  const StatusRing({
    required this.icon,
    required this.color,
    super.key,
    this.progress = 0,
    this.caption,
    this.size = 190,
    this.glow = true,
    this.pulse = 1,
  });

  final IconData icon;
  final Color color;

  /// 0..1 of the arc to draw.
  final double progress;

  /// Small text under the icon, e.g. "Keep me still".
  final String? caption;

  final double size;
  final bool glow;

  /// Scales the ring, so a caller can breathe it in and out.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: pulse,
        child: CustomPaint(
          painter: _RingPainter(progress: progress, color: color, glow: glow),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: size * 0.26, color: Colors.white),
                if (caption != null) ...[
                  SizedBox(height: size * 0.05),
                  Text(
                    caption!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.glow,
  });

  final double progress;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 5;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    if (glow) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.24)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
    }

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.16);
    canvas.drawCircle(centre, radius, track);

    final swept = progress.clamp(0.0, 1.0);
    if (swept <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * swept, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.glow != glow;
}
