import 'dart:async';

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Quaternion, Vector3;

import '../../domain/focus_zone.dart';
import '../../domain/pinch_tracker.dart';
import '../../domain/session_mode.dart';
import '../../domain/zone_placement.dart';
import '../../domain/zone_tracking.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import 'session_screen.dart';

/// Anchors the focus zone to a real surface, then lets it be dragged, pinched,
/// and turned until it sits where the phone will go.
///
/// A [PlacementGuide] walks the person through scanning, placing, and
/// adjusting; on iOS a [ZoneTracker] watches the zone afterwards and asks for
/// it to be put back when tracking slips.
class ArPlacementScreen extends StatefulWidget {
  const ArPlacementScreen({required this.config, super.key});

  final SessionConfig config;

  @override
  State<ArPlacementScreen> createState() => _ArPlacementScreenState();
}

class _ArPlacementScreenState extends State<ArPlacementScreen> {
  /// How often the iOS tracker polls, and how often a stalled scan is
  /// re-checked for tips.
  static const Duration _pollInterval = Duration(milliseconds: 500);

  /// Only ARKit answers pose queries reliably. The Android plugin's camera
  /// pose call advances the AR session itself, and its anchor pose lookup
  /// cannot find local anchors, so tracking is not watched there.
  static bool get _canWatchTracking => defaultTargetPlatform == TargetPlatform.iOS;

  /// The Android plugin reads a node's rotation as radians where its renderer
  /// expects degrees, so a heading set from here barely turns the model.
  /// There, the twist gesture — handled natively — is the way to turn it.
  static bool get _canTurnFromHere => defaultTargetPlatform != TargetPlatform.android;

  final PinchTracker _pinch = PinchTracker();
  final ZoneTracker _tracker = ZoneTracker();
  late final PlacementGuide _guide = PlacementGuide(now: DateTime.now());

  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  ARAnchor? _anchor;
  ARNode? _node;
  Timer? _poll;

  ZoneTransform _zone = ZoneTransform.initial;

  /// Where a drag has left the zone, relative to its anchor.
  Vector3 _offset = Vector3.zero();

  /// Size at the moment the current pinch started, so the gesture scales from
  /// there rather than compounding every frame.
  ZoneTransform _pinchOrigin = ZoneTransform.initial;

  ZoneStatus _status = ZoneStatus.unknown;
  bool _polling = false;
  bool _busy = false;
  bool _showTips = false;

  /// A one-off line about the last tap, shown until the next one.
  String? _notice;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_guide.hasZone) _zone = WalletScope.of(context).zone;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = _guide.stage;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // A Listener reads the pinch without entering the gesture arena, so
          // the AR view keeps its own taps, drags, and twists.
          Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (event) => _onPointerUp(event),
            child: ARView(
              onARViewCreated: _onArViewCreated,
              planeDetectionConfig: PlaneDetectionConfig.horizontal,
            ),
          ),
          if (stage == PlacementStage.scanning)
            const IgnorePointer(child: _ScanHint())
          else if (stage == PlacementStage.surfaceFound)
            const IgnorePointer(child: _ReticleOverlay()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      _Badge(
                        icon: Icons.view_in_ar_rounded,
                        label: _guide.hasZone ? _zone.sizeLabel : 'AR placement',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (stage == PlacementStage.placed && _status.direction != null)
                    _DirectionChip(direction: _status.direction!),
                  const Spacer(),
                  _PlacementPanel(
                    stage: stage,
                    busy: _busy,
                    title: _titleFor(stage),
                    message: _messageFor(stage),
                    notice: _notice,
                    canTurn: _canTurnFromHere,
                    onShrink: () => _applyZone(_zone.scaledBy(1 / ZoneTransform.scaleStep)),
                    onGrow: () => _applyZone(_zone.scaledBy(ZoneTransform.scaleStep)),
                    onTurnLeft: () => _applyZone(_zone.rotatedBy(ZoneTransform.rotationStep)),
                    onTurnRight: () =>
                        _applyZone(_zone.rotatedBy(-ZoneTransform.rotationStep)),
                    onReset: _resetZone,
                    onReplace: _replace,
                    onUse: _useZone,
                    onSkip: () => _startSession(PlacementMethod.motionOnly),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(PlacementStage stage) => switch (stage) {
        PlacementStage.scanning => 'Find your desk',
        PlacementStage.surfaceFound => 'Desk found',
        PlacementStage.placed => 'Focus zone placed',
        PlacementStage.lost => 'Lost the zone',
      };

  String _messageFor(PlacementStage stage) => switch (stage) {
        PlacementStage.scanning => _showTips
            ? 'Still looking. Plain, glossy, or dark desks are hard to read — '
                'more light, or a notebook on the desk, gives the camera '
                'something to hold on to.'
            : 'Point the camera at the desk and sweep slowly from side to side.',
        PlacementStage.surfaceFound => 'Tap the spot where the phone will lie.',
        PlacementStage.placed => [
            if (_guide.anchoredToPoint)
              'Anchored to a loose point, so it may drift — tap again once the '
                  'desk lights up.',
            _canTurnFromHere
                ? 'Drag to move, pinch or use − + to resize, twist or use the '
                    'arrows to turn. Tap elsewhere on the desk to move it there.'
                : 'Drag to move, pinch or use − + to resize, twist to turn — '
                    'resize first, as resizing squares it up again. Tap '
                    'elsewhere on the desk to move it there.',
          ].join(' '),
        PlacementStage.lost =>
          'Tracking slipped. Point back at the desk and tap where the zone '
              'should be — its size and heading are kept.',
      };

  void _onArViewCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager locations,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;

    session.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
      handlePans: true,
      handleRotation: true,
    );
    objects.onInitialize();

    session.onPlaneOrPointTap = _onSurfaceTapped;
    session.onPlaneDetected = _onPlaneDetected;
    session.onError = (error) {
      if (mounted) setState(() => _notice = 'The camera hit a problem: $error');
    };
    objects.onPanEnd = _onPanEnd;
    objects.onRotationEnd = _onRotationEnd;
    _guide.restartScan(DateTime.now());
  }

  void _onPlaneDetected(int count) {
    if (!mounted) return;
    setState(() => _guide.planesDetected(count));
  }

  Future<void> _onSurfaceTapped(List<ARHitTestResult> hits) async {
    if (_busy) return;
    final choice = _guide.choose([
      for (final hit in hits)
        SurfaceHit(
          onPlane: hit.type == ARHitTestResultType.plane,
          distance: hit.distance,
        ),
    ]);
    final index = choice.index;
    if (!choice.verdict.accepted || index == null) {
      setState(() => _notice = _rejection(choice.verdict));
      return;
    }
    await _placeAt(hits[index], onPlane: choice.verdict == HitVerdict.plane);
  }

  String _rejection(HitVerdict verdict) => switch (verdict) {
        HitVerdict.tooClose => 'Too close — hold the phone a little higher.',
        HitVerdict.tooFar =>
          'That is further than your desk. Tap the surface in front of you.',
        HitVerdict.offPlane => _guide.hasZone
            ? 'Tap on the desk itself to move the zone there.'
            : 'Tap on the highlighted surface.',
        HitVerdict.noSurface || HitVerdict.plane || HitVerdict.point =>
          'Nothing to hold on to there. Aim at the desk, move sideways a '
              'little, and tap again.',
      };

  /// Anchors a fresh zone at [hit], keeping the size and heading the person
  /// already chose. A drag offset belongs to the old anchor and is dropped.
  Future<void> _placeAt(ARHitTestResult hit, {required bool onPlane}) async {
    final anchors = _anchors;
    final objects = _objects;
    if (anchors == null || objects == null) return;

    setState(() {
      _busy = true;
      _notice = null;
    });
    _clearZone();

    final anchor = ARPlaneAnchor(transformation: levelledAnchor(hit.worldTransform));
    final anchored = await anchors.addAnchor(anchor) ?? false;
    if (!anchored) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = 'That spot would not hold an anchor. Try another one.';
        });
      }
      return;
    }

    _offset = Vector3.zero();
    if (!_canTurnFromHere) _zone = _zone.copyWith(yaw: 0);
    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: 'assets/models/focus_zone.gltf',
      transformation: _initialNodeTransform(),
    );
    final added = await objects.addNode(node, planeAnchor: anchor) ?? false;
    if (!mounted) return;
    // Android only read a size off the first value; now give it the whole
    // transform, so later pinches scale from the same base on both platforms.
    if (added) node.transform = _composeNode();

    _tracker.reset();
    _session?.showPlanes(false);
    setState(() {
      _busy = false;
      _anchor = anchor;
      _node = added ? node : null;
      _status = ZoneStatus.unknown;
      _guide.placed(onPlane: onPlane);
      if (!added) {
        _notice = 'Zone anchored, but the model would not load. The sensors '
            'will still guard your session.';
      }
    });
  }

  /// The transform the zone is created with. The Android plugin sizes a new
  /// model from the first matrix value alone, as the length of its longest
  /// side in metres; give it that, or a phone-sized zone arrives a metre long.
  Matrix4 _initialNodeTransform() {
    final transform = _composeNode();
    if (defaultTargetPlatform == TargetPlatform.android) {
      transform.storage[0] = _zone.lengthMetres;
    }
    return transform;
  }

  Matrix4 _composeNode() => Matrix4.compose(
        _offset,
        Quaternion.axisAngle(Vector3(0, 1, 0), _canTurnFromHere ? _zone.yaw : 0),
        Vector3.all(_zone.scale),
      );

  void _onPointerDown(PointerDownEvent event) {
    if (!_guide.hasZone) return;
    if (_pinch.onPointerDown(event.pointer, event.position)) {
      _pinchOrigin = _zone;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_guide.hasZone) return;
    if (!_pinch.onPointerMove(event.pointer, event.position)) return;
    _applyZone(_pinchOrigin.scaledBy(_pinch.factor));
  }

  void _onPointerUp(PointerEvent event) {
    if (_pinch.onPointerUp(event.pointer)) _pinchOrigin = _zone;
  }

  /// Rebuilds the node from the drag offset, the size, and the heading.
  void _applyZone(ZoneTransform next) {
    // Where a heading cannot be sent, sending any transform squares the zone
    // up, so the state has to say so too.
    if (!_canTurnFromHere) next = next.copyWith(yaw: 0);
    if (next == _zone) return;
    setState(() => _zone = next);
    _node?.transform = _composeNode();
  }

  /// The drag already moved the model natively; this only keeps note of where
  /// it went. Sending it back would make Android re-read its own matrix
  /// transposed and snap the zone onto its anchor.
  void _onPanEnd(String nodeName, Matrix4 transform) {
    if (_node?.name != nodeName) return;
    _offset = normalizeAffine(transform).getTranslation();
  }

  /// As with a drag: note the heading the twist left, without echoing it.
  void _onRotationEnd(String nodeName, Matrix4 transform) {
    if (_node?.name != nodeName) return;
    final normalized = normalizeAffine(transform);
    _offset = normalized.getTranslation();
    setState(() => _zone = _zone.copyWith(yaw: ZoneTransform.normalizeAngle(yawOf(normalized))));
  }

  void _onPoll() {
    if (!mounted) return;
    final tips = _guide.showTips(DateTime.now());
    if (tips != _showTips) setState(() => _showTips = tips);
    if (_canWatchTracking && _guide.hasZone && !_busy) unawaited(_watchTracking());
  }

  /// Asks ARKit where the camera and the zone are, and moves the guide
  /// between placed and lost on what the tracker makes of it.
  Future<void> _watchTracking() async {
    final session = _session;
    final anchor = _anchor;
    if (session == null || anchor == null || _polling) return;
    _polling = true;
    try {
      final camera = await session.getCameraPose();
      final anchorPose = await session.getPose(anchor);
      if (!mounted || !identical(anchor, _anchor)) return;
      final zone = anchorPose?.transform3(_offset.clone());
      final status = _tracker.update(camera: camera, zone: zone);
      final wasLost = _guide.stage == PlacementStage.lost;
      final lost = status.visibility == ZoneVisibility.lost;
      if (status == _status && wasLost == lost) return;
      setState(() {
        _status = status;
        if (lost) {
          _guide.trackingLost();
        } else if (status.visibility != ZoneVisibility.unknown) {
          _guide.trackingRecovered();
        }
      });
      if (lost != wasLost) session.showPlanes(lost);
    } finally {
      _polling = false;
    }
  }

  void _clearZone() {
    final node = _node;
    final anchor = _anchor;
    if (node != null) _objects?.removeNode(node);
    if (anchor != null) _anchors?.removeAnchor(anchor);
    _node = null;
    _anchor = null;
  }

  /// Takes the zone away so the next tap starts it afresh.
  void _replace() {
    _clearZone();
    _tracker.reset();
    _session?.showPlanes(true);
    setState(() {
      _status = ZoneStatus.unknown;
      _notice = null;
      _guide.cleared();
    });
  }

  void _resetZone() {
    _pinch.reset();
    _pinchOrigin = ZoneTransform.initial;
    _applyZone(ZoneTransform.initial);
  }

  Future<void> _useZone() async {
    await WalletScope.of(context).saveZone(_zone);
    if (!mounted) return;
    _startSession(PlacementMethod.arZone);
  }

  /// The camera is shut down before the timer starts — an AR session left
  /// running for an hour cooks the battery for no benefit.
  void _startSession(PlacementMethod method) {
    _poll?.cancel();
    _session?.dispose();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(config: widget.config.copyWith(method: method)),
      ),
    );
  }
}

/// A phone sweeping side to side, until the first surface turns up.
class _ScanHint extends StatefulWidget {
  const _ScanHint();

  @override
  State<_ScanHint> createState() => _ScanHintState();
}

class _ScanHintState extends State<_ScanHint> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            Tween<double>(begin: -46, end: 46)
                .transform(Curves.easeInOut.transform(_sweep.value)),
            0,
          ),
          child: child,
        ),
        child: Container(
          width: 64,
          height: 104,
          decoration: BoxDecoration(
            color: Colors.black26,
            border: Border.all(color: Colors.white70, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.camera_alt_outlined, size: 26),
        ),
      ),
    );
  }
}

/// The ghost outline shown once a surface is found, until a zone is anchored.
class _ReticleOverlay extends StatelessWidget {
  const _ReticleOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 128,
        height: 248,
        decoration: BoxDecoration(
          color: FocusPalette.focus.withValues(alpha: 0.32),
          border: Border.all(color: Colors.white70, width: 2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(Icons.touch_app_rounded, size: 48),
      ),
    );
  }
}

/// Points the way back to a zone that has left the screen.
class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.direction});

  final ZoneDirection direction;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (direction) {
      ZoneDirection.left => (Icons.arrow_back_rounded, 'Zone is to your left'),
      ZoneDirection.right => (Icons.arrow_forward_rounded, 'Zone is to your right'),
      ZoneDirection.up => (Icons.arrow_upward_rounded, 'Zone is above the view'),
      ZoneDirection.down => (Icons.arrow_downward_rounded, 'Zone is below the view'),
      ZoneDirection.behind => (Icons.u_turn_left_rounded, 'Zone is behind you'),
    };
    return _Badge(icon: icon, label: label);
  }
}

/// Scan · Place · Adjust, with the current step lit.
class _Steps extends StatelessWidget {
  const _Steps({required this.stage});

  final PlacementStage stage;

  @override
  Widget build(BuildContext context) {
    final current = switch (stage) {
      PlacementStage.scanning => 0,
      PlacementStage.surfaceFound => 1,
      PlacementStage.placed || PlacementStage.lost => 2,
    };
    const labels = ['SCAN', 'PLACE', 'ADJUST'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Container(
              width: 18,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
            ),
          Text(
            labels[i],
            style: kEyebrow.copyWith(
              fontSize: 10.5,
              color: i == current
                  ? FocusPalette.focusSoft
                  : i < current
                      ? Colors.white54
                      : Colors.white24,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({
    required this.stage,
    required this.busy,
    required this.title,
    required this.message,
    required this.notice,
    required this.canTurn,
    required this.onShrink,
    required this.onGrow,
    required this.onTurnLeft,
    required this.onTurnRight,
    required this.onReset,
    required this.onReplace,
    required this.onUse,
    required this.onSkip,
  });

  final PlacementStage stage;
  final bool busy;
  final String title;
  final String message;
  final String? notice;
  final bool canTurn;
  final VoidCallback onShrink;
  final VoidCallback onGrow;
  final VoidCallback onTurnLeft;
  final VoidCallback onTurnRight;
  final VoidCallback onReset;
  final VoidCallback onReplace;
  final VoidCallback onUse;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final placed = stage == PlacementStage.placed;
    final hasZone = placed || stage == PlacementStage.lost;
    final lost = stage == PlacementStage.lost;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xF2050F1F),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: lost ? FocusPalette.alarm : Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Steps(stage: stage),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          if (notice != null) ...[
            const SizedBox(height: 8),
            Text(
              notice!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FocusPalette.card, fontSize: 13, height: 1.35),
            ),
          ],
          if (placed) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Smaller',
                  onPressed: busy ? null : onShrink,
                ),
                _ControlButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Bigger',
                  onPressed: busy ? null : onGrow,
                ),
                if (canTurn) ...[
                  const SizedBox(width: 10),
                  _ControlButton(
                    icon: Icons.rotate_left_rounded,
                    tooltip: 'Turn left',
                    onPressed: busy ? null : onTurnLeft,
                  ),
                  _ControlButton(
                    icon: Icons.rotate_right_rounded,
                    tooltip: 'Turn right',
                    onPressed: busy ? null : onTurnRight,
                  ),
                ],
                const SizedBox(width: 10),
                _ControlButton(
                  icon: Icons.restart_alt_rounded,
                  tooltip: 'Reset size and heading',
                  onPressed: busy ? null : onReset,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: busy ? null : onUse,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Use this zone'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (hasZone)
                TextButton.icon(
                  onPressed: busy ? null : onReplace,
                  icon: const Icon(Icons.ads_click_rounded, size: 18),
                  label: const Text('Place again'),
                ),
              TextButton.icon(
                onPressed: busy ? null : onSkip,
                icon: const Icon(Icons.sensors_rounded, size: 18),
                label: const Text('Continue without AR'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
