import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/focus_zone.dart';

void main() {
  group('sizing', () {
    test('starts at the size of the model on disk', () {
      const zone = ZoneTransform.initial;

      expect(zone.scale, 1.0);
      expect(zone.lengthMetres, closeTo(0.165, 1e-9));
      expect(zone.widthMetres, closeTo(0.078, 1e-9));
      expect(zone.sizeLabel, '17 x 8 cm');
    });

    test('pinching scales the footprint', () {
      final zone = ZoneTransform.initial.scaledBy(2);

      expect(zone.scale, 2.0);
      expect(zone.lengthMetres, closeTo(0.33, 1e-9));
    });

    test('clamps to a usable range', () {
      expect(ZoneTransform.initial.scaledBy(100).scale, ZoneTransform.maxScale);
      expect(ZoneTransform.initial.scaledBy(0.001).scale, ZoneTransform.minScale);
    });

    test('ignores a nonsense factor', () {
      const zone = ZoneTransform.initial;

      expect(zone.scaledBy(0), zone);
      expect(zone.scaledBy(-2), zone);
      expect(zone.scaledBy(double.nan), zone);
      expect(zone.scaledBy(double.infinity), zone);
    });
  });

  group('heading', () {
    test('accumulates rotation', () {
      final zone = ZoneTransform.initial.rotatedBy(0.5).rotatedBy(0.25);

      expect(zone.yaw, closeTo(0.75, 1e-9));
    });

    test('wraps past half a turn instead of running away', () {
      final zone = ZoneTransform.initial.rotatedBy(math.pi * 1.5);

      expect(zone.yaw, closeTo(-math.pi / 2, 1e-9));
      expect(zone.yaw, inExclusiveRange(-math.pi, math.pi + 1e-9));
    });

    test('normalises any angle into a half turn either way', () {
      for (final angle in [0.0, 3.0, -3.0, 7.0, -7.0, 100.0]) {
        final wrapped = ZoneTransform.normalizeAngle(angle);
        expect(wrapped, greaterThan(-math.pi));
        expect(wrapped, lessThanOrEqualTo(math.pi));
      }
      expect(ZoneTransform.normalizeAngle(double.nan), 0);
    });
  });

  group('persistence', () {
    test('round-trips through json', () {
      final zone = ZoneTransform.initial.scaledBy(1.4).rotatedBy(0.8);
      final restored = ZoneTransform.fromJson(zone.toJson());

      expect(restored, zone);
    });

    test('falls back to the default when the saved value is junk', () {
      final restored = ZoneTransform.fromJson(const {'scale': 'huge'});

      expect(restored, ZoneTransform.initial);
    });

    test('clamps a saved scale that is out of range', () {
      final restored = ZoneTransform.fromJson(const {'scale': 99.0});

      expect(restored.scale, ZoneTransform.maxScale);
    });
  });
}
