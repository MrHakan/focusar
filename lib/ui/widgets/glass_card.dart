import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted panel used for the grouped controls on the home and wallet screens.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final corner = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: corner,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: corner,
            border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
