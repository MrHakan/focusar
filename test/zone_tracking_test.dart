import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/zone_tracking.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('levelled anchor', () {
    test('keeps the position and drops the lean', () {
      final tilted = Matrix4.compose(
        Vector3(0.2, 0.7, -0.4),
        Quaternion.axisAngle(Vector3(1, 0, 1)..normalize(), 0.3),
        Vector3.all(1),
      );

      final anchor = levelledAnchor(tilted);

      expect(anchor.getTranslation(), Vector3(0.2, 0.7, -0.4));
      expect(anchor.getRotation().isIdentity(), isTrue);
    });
  });

  group('normalizeAffine', () {
    final transform = Matrix4.compose(
      Vector3(0.1, 0.0, -0.3),
      Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
      Vector3.all(1.4),
    );

    test('leaves a column-major matrix alone', () {
      expect(normalizeAffine(transform), transform);
    });

    test('turns a row-major one the right way round', () {
      final fromAndroid = transform.transposed();

      final fixed = normalizeAffine(fromAndroid);

      expect(fixed.getTranslation().x, closeTo(0.1, 1e-9));
      expect(fixed.getTranslation().z, closeTo(-0.3, 1e-9));
      expect(yawOf(fixed), closeTo(0.5, 1e-9));
    });

    test('does not touch the original', () {
      final copy = transform.clone();

      normalizeAffine(transform).setTranslationRaw(9, 9, 9);

      expect(transform, copy);
    });
  });

  test('yawOf reads the heading around the up axis', () {
    for (final yaw in [-2.5, -0.4, 0.0, 0.9, 3.0]) {
      final transform = Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 1, 0), yaw),
        Vector3.all(2),
      );
      expect(yawOf(transform), closeTo(yaw, 1e-9));
    }
  });

  group('zone tracker', () {
    /// A camera at [position], held upright, facing [heading] radians to the
    /// left of -Z. ARKit's camera frame is the landscape-right one: +X runs
    /// from the front camera toward the bottom of the phone. Rolling it a
    /// quarter turn clockwise points +X down and +Y to the screen's right.
    Matrix4 camera({Vector3? position, double heading = 0, double jitter = 0}) {
      final upright = Quaternion.axisAngle(Vector3(0, 1, 0), heading) *
          Quaternion.axisAngle(Vector3(0, 0, 1), -math.pi / 2);
      return Matrix4.compose(
        (position ?? Vector3(0, 1.2, 0)) + Vector3(jitter, 0, 0),
        upright,
        Vector3.all(1),
      );
    }

    /// The desk, a little below and in front of the camera.
    final desk = Vector3(0, 0.75, -0.6);

    test('says nothing before the first pose', () {
      final tracker = ZoneTracker();

      expect(tracker.update().visibility, ZoneVisibility.unknown);
    });

    test('a zone straight ahead is in view', () {
      final tracker = ZoneTracker();

      final status = tracker.update(camera: camera(), zone: Vector3(0, 1.2, -0.6));

      expect(status.visibility, ZoneVisibility.inView);
      expect(status.distance, closeTo(0.6, 1e-9));
    });

    test('the camera model matches an upright phone', () {
      final rotation = camera().getRotation();

      expect(rotation.transformed(Vector3(1, 0, 0)).y, closeTo(-1, 1e-9));
      expect(rotation.transformed(Vector3(0, 1, 0)).x, closeTo(1, 1e-9));
      expect(rotation.transformed(Vector3(0, 0, 1)).z, closeTo(1, 1e-9));
    });

    test('a zone off to the left says so', () {
      final tracker = ZoneTracker();

      final status = tracker.update(camera: camera(), zone: Vector3(-0.8, 1.2, -0.5));

      expect(status.visibility, ZoneVisibility.offScreen);
      expect(status.direction, ZoneDirection.left);
    });

    test('a zone off to the right says so', () {
      final tracker = ZoneTracker();

      final status = tracker.update(camera: camera(), zone: Vector3(0.8, 1.2, -0.5));

      expect(status.direction, ZoneDirection.right);
    });

    test('a zone well below the view says so', () {
      final tracker = ZoneTracker();

      final status = tracker.update(camera: camera(), zone: desk + Vector3(0, -0.6, 0.3));

      expect(status.direction, ZoneDirection.down);
    });

    test('a zone behind the camera says so', () {
      final tracker = ZoneTracker();

      final status = tracker.update(camera: camera(heading: math.pi), zone: desk);

      expect(status.visibility, ZoneVisibility.offScreen);
      expect(status.direction, ZoneDirection.behind);
    });

    test('losing poses for a while loses the zone', () {
      final tracker = ZoneTracker()..update(camera: camera(), zone: desk);

      for (var i = 0; i < ZoneTracker.missingPolls - 1; i++) {
        expect(tracker.update().visibility, isNot(ZoneVisibility.lost));
      }
      expect(tracker.update().visibility, ZoneVisibility.lost);
    });

    test('a frozen camera loses the zone, a moving one finds it again', () {
      final tracker = ZoneTracker();
      final frozen = camera();

      var status = tracker.update(camera: frozen, zone: Vector3(0, 1.2, -0.6));
      for (var i = 0; i < ZoneTracker.frozenPolls; i++) {
        status = tracker.update(camera: frozen, zone: Vector3(0, 1.2, -0.6));
      }
      expect(status.visibility, ZoneVisibility.lost);

      status = tracker.update(camera: camera(jitter: 0.002), zone: Vector3(0, 1.2, -0.6));
      expect(status.visibility, ZoneVisibility.inView);
    });

    test('ordinary hand jitter keeps tracking alive', () {
      final tracker = ZoneTracker();
      var status = ZoneStatus.unknown;

      for (var i = 0; i < ZoneTracker.frozenPolls * 3; i++) {
        status = tracker.update(
          camera: camera(jitter: (i.isEven ? 1 : -1) * 0.0003),
          zone: Vector3(0, 1.2, -0.6),
        );
      }

      expect(status.visibility, ZoneVisibility.inView);
    });

    test('reset forgets everything', () {
      final tracker = ZoneTracker()..update(camera: camera(), zone: desk);

      tracker.reset();

      expect(tracker.status, ZoneStatus.unknown);
      for (var i = 0; i < ZoneTracker.missingPolls; i++) {
        expect(tracker.update().visibility, ZoneVisibility.unknown);
      }
    });
  });
}
