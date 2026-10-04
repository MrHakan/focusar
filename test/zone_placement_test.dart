import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/zone_placement.dart';

void main() {
  final start = DateTime(2026, 9, 14, 9);

  PlacementGuide guide() => PlacementGuide(now: start);

  const plane = SurfaceHit(onPlane: true, distance: 0.6);
  const nearPlane = SurfaceHit(onPlane: true, distance: 0.4);
  const point = SurfaceHit(onPlane: false, distance: 0.5);

  group('stages', () {
    test('starts out scanning', () {
      final g = guide();

      expect(g.stage, PlacementStage.scanning);
      expect(g.hasZone, isFalse);
    });

    test('a detected surface asks for a tap', () {
      final g = guide()..planesDetected(1);

      expect(g.stage, PlacementStage.surfaceFound);
      expect(g.planeCount, 1);
    });

    test('a smaller plane count never takes the count back', () {
      final g = guide()
        ..planesDetected(3)
        ..planesDetected(1);

      expect(g.planeCount, 3);
    });

    test('placing, losing, and recovering the zone', () {
      final g = guide()
        ..planesDetected(1)
        ..placed(onPlane: true);
      expect(g.stage, PlacementStage.placed);
      expect(g.isPlaced, isTrue);

      g.trackingLost();
      expect(g.stage, PlacementStage.lost);
      expect(g.hasZone, isTrue);

      g.trackingRecovered();
      expect(g.stage, PlacementStage.placed);
    });

    test('tracking news means nothing before a zone exists', () {
      final g = guide()
        ..trackingLost()
        ..trackingRecovered();

      expect(g.stage, PlacementStage.scanning);
    });

    test('clearing the zone goes back to wherever the scan had got to', () {
      final scanned = guide()
        ..planesDetected(2)
        ..placed(onPlane: true)
        ..cleared();
      final unscanned = guide()
        ..placed(onPlane: false)
        ..cleared();

      expect(scanned.stage, PlacementStage.surfaceFound);
      expect(unscanned.stage, PlacementStage.scanning);
      expect(unscanned.anchoredToPoint, isFalse);
    });

    test('remembers that the zone sits on a loose point', () {
      final g = guide()..placed(onPlane: false);

      expect(g.anchoredToPoint, isTrue);
    });
  });

  group('tips', () {
    test('appear only after a long scan', () {
      final g = guide();

      expect(g.showTips(start.add(const Duration(seconds: 3))), isFalse);
      expect(g.showTips(start.add(PlacementGuide.tipsAfter)), isTrue);
    });

    test('go away once a surface is found', () {
      final g = guide()..planesDetected(1);

      expect(g.showTips(start.add(const Duration(minutes: 1))), isFalse);
    });

    test('wait again after the scan restarts', () {
      final g = guide()..restartScan(start.add(const Duration(seconds: 30)));

      expect(g.showTips(start.add(const Duration(seconds: 35))), isFalse);
    });
  });

  group('choosing a hit', () {
    test('prefers the nearest plane', () {
      final choice = (guide()..planesDetected(1)).choose([point, plane, nearPlane]);

      expect(choice.verdict, HitVerdict.plane);
      expect(choice.index, 2);
    });

    test('accepts a feature point only while no plane exists', () {
      final early = guide().choose([point]);
      final late = (guide()..planesDetected(1)).choose([point]);

      expect(early.verdict, HitVerdict.point);
      expect(early.index, 0);
      expect(late.verdict, HitVerdict.offPlane);
      expect(late.index, isNull);
    });

    test('rejects a plane out of reach', () {
      final g = guide()..planesDetected(1);

      expect(
        g.choose([const SurfaceHit(onPlane: true, distance: 3.5)]).verdict,
        HitVerdict.tooFar,
      );
      expect(
        g.choose([const SurfaceHit(onPlane: true, distance: 0.05)]).verdict,
        HitVerdict.tooClose,
      );
    });

    test('a plane in reach wins over one out of reach', () {
      final choice = (guide()..planesDetected(1)).choose([
        const SurfaceHit(onPlane: true, distance: 4),
        plane,
      ]);

      expect(choice.verdict, HitVerdict.plane);
      expect(choice.index, 1);
    });

    test('an empty tap finds nothing', () {
      expect(guide().choose(const []).verdict, HitVerdict.noSurface);
      expect((guide()..planesDetected(1)).choose(const []).verdict, HitVerdict.noSurface);
    });

    test('a point out of reach says why', () {
      final choice = guide().choose([const SurfaceHit(onPlane: false, distance: 5)]);

      expect(choice.verdict, HitVerdict.tooFar);
    });

    test('a broken distance is no surface at all', () {
      final choice = (guide()..planesDetected(1)).choose([
        const SurfaceHit(onPlane: true, distance: double.nan),
      ]);

      expect(choice.verdict, HitVerdict.noSurface);
    });

    test('only planes and points are accepted', () {
      expect(HitVerdict.plane.accepted, isTrue);
      expect(HitVerdict.point.accepted, isTrue);
      for (final verdict in [
        HitVerdict.noSurface,
        HitVerdict.offPlane,
        HitVerdict.tooClose,
        HitVerdict.tooFar,
      ]) {
        expect(verdict.accepted, isFalse);
      }
    });
  });
}
