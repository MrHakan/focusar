import 'dart:math' as math;

import 'json_reader.dart';

/// The size and heading of the AR focus zone, relative to the anchor it was
/// dropped on. Kept free of vector maths so it can be saved, restored, and
/// tested on its own; the AR screen turns it into a transform.
class ZoneTransform {
  const ZoneTransform({this.scale = 1.0, this.yaw = 0.0});

  /// The footprint of the zone model at scale 1, in metres. These mirror
  /// `assets/models/focus_zone.gltf`, which is sized for a phone lying flat.
  static const double baseLength = 0.165;
  static const double baseWidth = 0.078;

  static const double minScale = 0.5;
  static const double maxScale = 2.5;

  static const ZoneTransform initial = ZoneTransform();

  /// Uniform size factor over the phone-sized default.
  final double scale;

  /// Heading around the surface normal, in radians, normalised to (-pi, pi].
  final double yaw;

  double get lengthMetres => baseLength * scale;
  double get widthMetres => baseWidth * scale;

  /// `16 x 8 cm`, the way the placement screen reports it.
  String get sizeLabel {
    final length = (lengthMetres * 100).round();
    final width = (widthMetres * 100).round();
    return '$length x $width cm';
  }

  /// Multiplies the current size, clamped to the usable range.
  ZoneTransform scaledBy(double factor) {
    if (!factor.isFinite || factor <= 0) return this;
    return copyWith(scale: (scale * factor).clamp(minScale, maxScale));
  }

  /// Turns the zone by [radians] and keeps the heading normalised.
  ZoneTransform rotatedBy(double radians) {
    if (!radians.isFinite) return this;
    return copyWith(yaw: normalizeAngle(yaw + radians));
  }

  ZoneTransform copyWith({double? scale, double? yaw}) => ZoneTransform(
        scale: scale ?? this.scale,
        yaw: yaw ?? this.yaw,
      );

  Map<String, dynamic> toJson() => {'scale': scale, 'yaw': yaw};

  static ZoneTransform fromJson(Map<String, dynamic> json) => ZoneTransform(
        scale: json.readDouble('scale', fallback: 1).clamp(minScale, maxScale),
        yaw: normalizeAngle(json.readDouble('yaw')),
      );

  /// Folds any angle into (-pi, pi].
  static double normalizeAngle(double radians) {
    if (!radians.isFinite) return 0;
    var value = radians % (2 * math.pi);
    if (value > math.pi) value -= 2 * math.pi;
    if (value <= -math.pi) value += 2 * math.pi;
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is ZoneTransform && other.scale == scale && other.yaw == yaw;

  @override
  int get hashCode => Object.hash(scale, yaw);

  @override
  String toString() => 'ZoneTransform(scale: $scale, yaw: $yaw)';
}
