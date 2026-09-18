import 'dart:math' as math;

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
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Quaternion, Vector3;

import '../../domain/focus_zone.dart';
import '../../domain/pinch_tracker.dart';
import '../../domain/session_mode.dart';
import '../../state/wallet_scope.dart';
import '../../theme/app_theme.dart';
import 'session_screen.dart';

/// Anchors the focus zone to a real surface, then lets it be dragged, pinched,
/// and turned until it sits where the phone will go.
class ArPlacementScreen extends StatefulWidget {
  const ArPlacementScreen({required this.config, super.key});

  final SessionConfig config;

  @override
  State<ArPlacementScreen> createState() => _ArPlacementScreenState();
}

class _ArPlacementScreenState extends State<ArPlacementScreen> {
  static const String _hint =
      'Drag to reposition. Pinch to resize. Rotate to align. '
      'Place your phone face-down inside to begin.';
  static const String _searchHint =
      'Move slowly across the desk until a surface lights up, then tap where '
      'the phone will sit.';

  final PinchTracker _pinch = PinchTracker();

  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  ARAnchor? _anchor;
  ARNode? _node;

  ZoneTransform _zone = ZoneTransform.initial;

  /// Size at the moment the current pinch started, so the gesture scales from
  /// there rather than compounding every frame.
  ZoneTransform _pinchOrigin = ZoneTransform.initial;

  bool _placed = false;
  bool _busy = false;
  String _message = _searchHint;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_placed) _zone = WalletScope.of(context).zone;
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          if (!_placed) const IgnorePointer(child: _ReticleOverlay()),
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
                        label: _placed ? _zone.sizeLabel : 'AR placement',
                      ),
                    ],
                  ),
                  const Spacer(),
                  _PlacementPanel(
                    placed: _placed,
                    busy: _busy,
                    message: _message,
                    onUse: _useZone,
                    onReset: _resetZone,
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
    objects.onPanEnd = _onPanEnd;
    objects.onRotationEnd = _onRotationEnd;
  }

  Future<void> _onSurfaceTapped(List<ARHitTestResult> hits) async {
    if (_busy) return;
    final hit = _bestHit(hits);
    if (hit == null || _anchors == null || _objects == null) {
      setState(() => _message =
          'No surface there. Aim at a textured edge, move sideways a little, '
          'and tap again.');
      return;
    }

    setState(() => _busy = true);
    await _clearZone();

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final anchored = await _anchors!.addAnchor(anchor) ?? false;
    if (!anchored) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'That surface would not hold an anchor. Try another spot.';
        });
      }
      return;
    }

    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: 'assets/models/focus_zone.gltf',
      transformation: _composeZone(Vector3.zero()),
    );
    final added = await _objects!.addNode(node, planeAnchor: anchor) ?? false;
    if (!mounted) return;

    setState(() {
      _busy = false;
      _anchor = anchor;
      _node = added ? node : null;
      _placed = true;
      _message = added
          ? _hint
          : 'Zone anchored, but the model would not load. The sensors will '
              'still guard your session.';
    });
  }

  /// Planes are the reliable surfaces; feature points are the fallback.
  ARHitTestResult? _bestHit(List<ARHitTestResult> hits) {
    for (final hit in hits) {
      if (hit.type == ARHitTestResultType.plane) return hit;
    }
    for (final hit in hits) {
      if (hit.type == ARHitTestResultType.point) return hit;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_placed) return;
    if (_pinch.onPointerDown(event.pointer, event.position)) {
      _pinchOrigin = _zone;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_placed) return;
    if (!_pinch.onPointerMove(event.pointer, event.position)) return;
    _applyZone(_pinchOrigin.scaledBy(_pinch.factor));
  }

  void _onPointerUp(PointerEvent event) {
    if (_pinch.onPointerUp(event.pointer)) _pinchOrigin = _zone;
  }

  /// Rewrites only the node's scale, leaving the translation the drag produced
  /// and the heading the twist produced exactly where they are.
  void _applyZone(ZoneTransform next) {
    if (next == _zone) return;
    final node = _node;
    if (node != null) {
      final translation = Vector3.zero();
      final rotation = Quaternion.identity();
      final scale = Vector3.zero();
      node.transform.clone().decompose(translation, rotation, scale);
      node.transform =
          Matrix4.compose(translation, rotation, Vector3.all(next.scale));
    }
    setState(() => _zone = next);
  }

  void _onPanEnd(String nodeName, Matrix4 transform) {
    final node = _node;
    if (node == null || node.name != nodeName) return;
    node.transform = transform;
  }

  void _onRotationEnd(String nodeName, Matrix4 transform) {
    final node = _node;
    if (node == null || node.name != nodeName) return;
    node.transform = transform;
    setState(() => _zone = _zone.copyWith(yaw: _yawOf(transform)));
  }

  /// Heading around the surface normal, pulled back out of the node's matrix.
  double _yawOf(Matrix4 transform) {
    final rotation = Quaternion.identity();
    transform.clone().decompose(Vector3.zero(), rotation, Vector3.zero());
    final yaw = math.atan2(
      2 * (rotation.w * rotation.y + rotation.x * rotation.z),
      1 - 2 * (rotation.y * rotation.y + rotation.x * rotation.x),
    );
    return ZoneTransform.normalizeAngle(yaw);
  }

  Matrix4 _composeZone(Vector3 translation) => Matrix4.compose(
        translation,
        Quaternion.axisAngle(Vector3(0, 1, 0), _zone.yaw),
        Vector3.all(_zone.scale),
      );

  Future<void> _clearZone() async {
    final node = _node;
    final anchor = _anchor;
    if (node != null) _objects?.removeNode(node);
    if (anchor != null) _anchors?.removeAnchor(anchor);
    _node = null;
    _anchor = null;
  }

  void _resetZone() {
    _pinch.reset();
    _applyZone(ZoneTransform.initial);
    _pinchOrigin = ZoneTransform.initial;
  }

  Future<void> _useZone() async {
    await WalletScope.of(context).saveZone(_zone);
    if (!mounted) return;
    _startSession(PlacementMethod.arZone);
  }

  /// The camera is shut down before the timer starts — an AR session left
  /// running for an hour cooks the battery for no benefit.
  void _startSession(PlacementMethod method) {
    _session?.dispose();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          config: SessionConfig(
            mode: widget.config.mode,
            method: method,
            target: widget.config.target,
          ),
        ),
      ),
    );
  }
}

/// The ghost outline shown until a zone is anchored.
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
        child: const Icon(Icons.lock_outline_rounded, size: 48),
      ),
    );
  }
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({
    required this.placed,
    required this.busy,
    required this.message,
    required this.onUse,
    required this.onReset,
    required this.onSkip,
  });

  final bool placed;
  final bool busy;
  final String message;
  final VoidCallback onUse;
  final VoidCallback onReset;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xF2050F1F),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            placed ? 'Focus zone placed' : 'Find your focus zone',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          if (placed) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: busy ? null : onUse,
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Use this zone'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: busy ? null : onReset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset size'),
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: busy ? null : onSkip,
            icon: const Icon(Icons.sensors_rounded, size: 18),
            label: const Text('Continue without AR'),
          ),
        ],
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
