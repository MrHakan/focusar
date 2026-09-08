import 'dart:ui';

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding ?? const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.075),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
          ),
          child: child,
        ),
      ),
    );
  }
}
