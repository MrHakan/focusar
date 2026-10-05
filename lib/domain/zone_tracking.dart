import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// An anchor at [hit]'s position, square to the world and level with it.
///
/// A tap's hit pose can lean — feature points carry a guessed normal, and a
/// plane's pose is only as level as the plane estimate — and a leaning anchor
/// tilts the zone and everything placed on it. World Y is up on both ARKit and
/// ARCore, so dropping the rotation keeps the zone flat on the desk. It also
/// keeps the Android plugin away from its rotation conversion, which mangles
/// any quaternion that is not the identity.
Matrix4 levelledAnchor(Matrix4 hit) => Matrix4.translation(hit.getTranslation());

/// Reads a transform the plugin handed back, whichever way round it came.
///
/// The iOS side sends column-major matrices. The Android side sends a
/// row-major array, which reads back transposed: the translation lands in the
/// bottom row and the true translation slot holds zeros. An affine transform
/// always has a bottom row of `0 0 0 1`, so anything else is transposed.
Matrix4 normalizeAffine(Matrix4 transform) {
  final s = transform.storage;
  const epsilon = 1e-6;
  final bottomRowClear =
      s[3].abs() < epsilon && s[7].abs() < epsilon && s[11].abs() < epsilon;
  return bottomRowClear ? transform.clone() : transform.transposed();
}

/// Heading around the up axis, pulled out of a transform's rotation.
double yawOf(Matrix4 transform) {
  final rotation = Quaternion.identity();
  transform.clone().decompose(Vector3.zero(), rotation, Vector3.zero());
  final yaw = math.atan2(
    2 * (rotation.w * rotation.y + rotation.x * rotation.z),
    1 - 2 * (rotation.y * rotation.y + rotation.x * rotation.x),
  );
  return yaw.isFinite ? yaw : 0;
}

/// Where the zone sits relative to what the camera can see.
enum ZoneVisibility {
  /// Nothing to go on yet, or the platform cannot say.
  unknown,

  /// In front of the camera and on screen.
  inView,

  /// Tracked, but off screen. [ZoneStatus.direction] says which way to turn.
  offScreen,

  /// Tracking has stopped making sense: poses stopped arriving or froze.
  lost,
}

/// Which way to point the phone to find the zone again.
enum ZoneDirection { left, right, up, down, behind }

class ZoneStatus {
  const ZoneStatus(this.visibility, {this.direction, this.distance});

  static const ZoneStatus unknown = ZoneStatus(ZoneVisibility.unknown);

  final ZoneVisibility visibility;
  final ZoneDirection? direction;

  /// Metres from the camera, when known.
  final double? distance;

  @override
  bool operator ==(Object other) =>
      other is ZoneStatus &&
      other.visibility == visibility &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(visibility, direction);
}

/// Watches the camera and the zone, poll by poll, and says whether the zone
/// is in view, off to one side, or lost.
///
/// Built for ARKit's camera frame: the camera looks down -Z, and with the
/// phone held upright +Y points to the right of the screen and -X to its top.
class ZoneTracker {
  /// Polls without a pose, after having had one, before the zone is lost.
  static const int missingPolls = 4;

  /// Polls with an identical camera pose before tracking counts as frozen.
  /// A hand-held camera always jitters a little while it is tracked.
  static const int frozenPolls = 6;

  /// Half the field of view across and up the screen, in degrees. On the
  /// tight side, so "in view" means comfortably on screen.
  static const double halfWidthDegrees = 24;
  static const double halfHeightDegrees = 34;

  /// Movement below this between polls counts as frozen, metres.
  static const double stillTranslation = 1e-5;

  bool _seen = false;
  int _missing = 0;
  int _frozen = 0;
  Matrix4? _lastCamera;
  ZoneStatus _status = ZoneStatus.unknown;

  ZoneStatus get status => _status;

  void reset() {
    _seen = false;
    _missing = 0;
    _frozen = 0;
    _lastCamera = null;
    _status = ZoneStatus.unknown;
  }

  /// Folds in one poll. [camera] is the camera's world transform and [zone]
  /// the zone's world position; either may be missing when the platform did
  /// not answer.
  ZoneStatus update({Matrix4? camera, Vector3? zone}) {
    if (camera == null || zone == null) {
      _missing += 1;
      if (_seen && _missing >= missingPolls) {
        _status = const ZoneStatus(ZoneVisibility.lost);
      }
      return _status;
    }
    _missing = 0;
    _seen = true;

    final last = _lastCamera;
    _lastCamera = camera.clone();
    if (last != null && _same(last, camera)) {
      _frozen += 1;
    } else {
      _frozen = 0;
    }
    if (_frozen >= frozenPolls) {
      return _status = const ZoneStatus(ZoneVisibility.lost);
    }

    final local = Matrix4.inverted(camera).transform3(zone.clone());
    final distance = local.length;
    final forward = -local.z;
    final right = local.y;
    final up = -local.x;

    if (forward <= 0) {
      return _status = ZoneStatus(
        ZoneVisibility.offScreen,
        direction: ZoneDirection.behind,
        distance: distance,
      );
    }

    final across = math.atan2(right, forward) * 180 / math.pi;
    final upward = math.atan2(up, forward) * 180 / math.pi;
    final overX = across.abs() / halfWidthDegrees;
    final overY = upward.abs() / halfHeightDegrees;
    if (overX <= 1 && overY <= 1) {
      return _status = ZoneStatus(ZoneVisibility.inView, distance: distance);
    }

    final direction = overX >= overY
        ? (across > 0 ? ZoneDirection.right : ZoneDirection.left)
        : (upward > 0 ? ZoneDirection.up : ZoneDirection.down);
    return _status = ZoneStatus(
      ZoneVisibility.offScreen,
      direction: direction,
      distance: distance,
    );
  }

  static bool _same(Matrix4 a, Matrix4 b) {
    for (var i = 0; i < 16; i++) {
      if ((a.storage[i] - b.storage[i]).abs() > stillTranslation) return false;
    }
    return true;
  }
}
