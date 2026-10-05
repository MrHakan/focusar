/// Where the AR placement flow stands.
enum PlacementStage {
  /// No surface found yet. The person is asked to sweep the desk.
  scanning,

  /// At least one surface is tracked. The person is asked to tap it.
  surfaceFound,

  /// The zone is anchored and can be adjusted.
  placed,

  /// The zone was placed, but tracking has lost it. A tap puts it back.
  lost,
}

/// One result of a tap on the camera view, stripped of the plugin's types.
class SurfaceHit {
  const SurfaceHit({required this.onPlane, required this.distance});

  /// On a tracked plane, as opposed to a loose feature point.
  final bool onPlane;

  /// Metres from the camera.
  final double distance;
}

/// What became of a tap.
enum HitVerdict {
  /// A tracked plane within reach: the steadiest anchor there is.
  plane,

  /// A feature point, accepted only while no plane has been found yet. It
  /// tends to drift, so the person is told so.
  point,

  /// Nothing under the finger.
  noSurface,

  /// Planes are tracked, but the tap missed them.
  offPlane,

  /// Closer than any desk the phone could lie on.
  tooClose,

  /// Further than the desk in front of you.
  tooFar,
}

extension HitVerdictAccepted on HitVerdict {
  bool get accepted => this == HitVerdict.plane || this == HitVerdict.point;
}

/// The result of choosing among a tap's hits.
class HitChoice {
  const HitChoice(this.verdict, [this.index]);

  final HitVerdict verdict;

  /// Which hit to anchor to, when [verdict] is accepted.
  final int? index;
}

/// The placement flow as a plain state machine: what stage it is in, which
/// taps to accept, and when to offer tips. The AR screen feeds it events and
/// renders whatever it says.
class PlacementGuide {
  PlacementGuide({required DateTime now}) : _scanStartedAt = now;

  /// Taps nearer than this hit the lens's own blur, not a desk.
  static const double minDistance = 0.12;

  /// A desk you can put a phone on is within arm's reach.
  static const double maxDistance = 2.0;

  /// How long a scan may go without a surface before tips are shown.
  static const Duration tipsAfter = Duration(seconds: 10);

  PlacementStage _stage = PlacementStage.scanning;
  int _planes = 0;
  bool _onPoint = false;
  DateTime _scanStartedAt;

  PlacementStage get stage => _stage;

  /// Surfaces tracked so far.
  int get planeCount => _planes;

  /// The zone was anchored to a feature point rather than a plane.
  bool get anchoredToPoint => _onPoint;

  bool get isPlaced => _stage == PlacementStage.placed;

  /// A zone exists in the scene, tracked or not.
  bool get hasZone =>
      _stage == PlacementStage.placed || _stage == PlacementStage.lost;

  /// The scan has dragged on long enough to explain what helps.
  bool showTips(DateTime now) =>
      _stage == PlacementStage.scanning &&
      now.difference(_scanStartedAt) >= tipsAfter;

  void planesDetected(int count) {
    if (count <= _planes) return;
    _planes = count;
    if (_stage == PlacementStage.scanning) _stage = PlacementStage.surfaceFound;
  }

  /// Picks the hit to anchor to: the nearest plane within reach, or — only
  /// while no plane exists at all — the nearest feature point.
  HitChoice choose(List<SurfaceHit> hits) {
    HitVerdict? rejection;

    int? best;
    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      if (!hit.onPlane) continue;
      final range = _range(hit.distance);
      if (range != null) {
        rejection ??= range;
        continue;
      }
      if (best == null || hit.distance < hits[best].distance) best = i;
    }
    if (best != null) return HitChoice(HitVerdict.plane, best);
    if (rejection != null) return HitChoice(rejection);

    if (_planes > 0) {
      return HitChoice(hits.isEmpty ? HitVerdict.noSurface : HitVerdict.offPlane);
    }

    for (var i = 0; i < hits.length; i++) {
      final hit = hits[i];
      final range = _range(hit.distance);
      if (range != null) {
        rejection ??= range;
        continue;
      }
      if (best == null || hit.distance < hits[best].distance) best = i;
    }
    if (best != null) return HitChoice(HitVerdict.point, best);
    return HitChoice(rejection ?? HitVerdict.noSurface);
  }

  /// The zone is anchored.
  void placed({required bool onPlane}) {
    _stage = PlacementStage.placed;
    _onPoint = !onPlane;
  }

  /// Takes the zone away so the next tap places it afresh.
  void cleared() {
    _stage = _planes > 0 ? PlacementStage.surfaceFound : PlacementStage.scanning;
    _onPoint = false;
  }

  /// Restarts the scan clock, e.g. after the camera came back.
  void restartScan(DateTime now) => _scanStartedAt = now;

  void trackingLost() {
    if (_stage == PlacementStage.placed) _stage = PlacementStage.lost;
  }

  void trackingRecovered() {
    if (_stage == PlacementStage.lost) _stage = PlacementStage.placed;
  }

  HitVerdict? _range(double distance) {
    if (!distance.isFinite) return HitVerdict.noSurface;
    if (distance < minDistance) return HitVerdict.tooClose;
    if (distance > maxDistance) return HitVerdict.tooFar;
    return null;
  }
}
