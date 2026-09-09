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
import 'package:vector_math/vector_math_64.dart' show Vector3, Vector4;

import 'focus_session_screen.dart';

class ArPlacementScreen extends StatefulWidget {
  const ArPlacementScreen({required this.duration, super.key});

  final Duration duration;

  @override
  State<ArPlacementScreen> createState() => _ArPlacementScreenState();
}

class _ArPlacementScreenState extends State<ArPlacementScreen> {
  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;
  ARPlaneAnchor? _zoneAnchor;
  bool _placed = false;
  bool _busy = false;
  String _message = 'Move slowly around the table, then tap a plane or a visible feature point.';

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
          ARView(
            onARViewCreated: _onArViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: _placed ? 0 : 0.9,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 130,
                  height: 256,
                  decoration: BoxDecoration(
                    color: const Color(0x665B7CFF),
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.lock_outline_rounded, size: 52),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                        child: const Row(
                          children: [
                            Icon(Icons.view_in_ar_rounded, size: 17),
                            SizedBox(width: 7),
                            Text('AR placement', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xE6071427),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _placed ? 'Focus zone placed' : 'Find your focus zone',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 7),
                        Text(_message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        if (_placed) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : () => _continue(),
                              icon: const Icon(Icons.lock_rounded),
                              label: const Text('Use this zone'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _continue(useAr: false),
                          icon: const Icon(Icons.sensors_rounded),
                          label: const Text('Continue without AR'),
                        ),
                      ],
                    ),
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
    ARLocationManager _,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;
    session.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      showWorldOrigin: false,
      handleTaps: true,
    );
    objects.onInitialize();
    session.onPlaneOrPointTap = _onPlaneTapped;
  }

  Future<void> _onPlaneTapped(List<ARHitTestResult> hits) async {
    if (_busy) return;
    ARHitTestResult? hit;
    for (final candidate in hits) {
      if (candidate.type == ARHitTestResultType.plane) {
        hit = candidate;
        break;
      }
    }
    if (hit == null) {
      for (final candidate in hits) {
        if (candidate.type == ARHitTestResultType.point) {
          hit = candidate;
          break;
        }
      }
    }
    if (hit == null || _anchors == null || _objects == null) {
      if (mounted) {
        setState(() {
          _message = 'No surface found at that point. Aim at a textured edge, move sideways, and tap again.';
        });
      }
      return;
    }

    setState(() => _busy = true);
    if (_zoneAnchor != null) {
      await _anchors!.removeAnchor(_zoneAnchor!);
    }

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final addedAnchor = await _anchors!.addAnchor(anchor) ?? false;
    if (!addedAnchor) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final node = ARNode(
      type: NodeType.localGLTF2,
      uri: 'assets/models/focus_zone.gltf',
      scale: Vector3(1, 1, 1),
      position: Vector3.zero(),
      rotation: Vector4(0, 0, 0, 1),
    );
    final addedNode = await _objects!.addNode(node, planeAnchor: anchor) ?? false;
    if (!mounted) return;

    setState(() {
      _busy = false;
      _zoneAnchor = anchor;
      _placed = true;
      _message = addedNode
          ? 'Tap another spot to reposition. Place your phone face-down inside the zone.'
          : 'Zone anchored. Place your phone face-down here to continue.';
    });
  }

  void _continue({bool useAr = true}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FocusSessionScreen(
          duration: widget.duration,
          method: useAr ? FocusMethod.ar : FocusMethod.sensors,
        ),
      ),
    );
  }
}
