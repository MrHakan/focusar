import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Two-finger pinch detection built from raw pointer events.
///
/// The AR view owns the gesture arena for taps, drags, and twists, so a normal
/// [GestureDetector] on top of it would steal them. A `Listener` sees pointer
/// events without competing for them, and this class turns that stream into a
/// scale factor for the focus zone.
class PinchTracker {
  /// Ignore pinches that start with the fingers almost touching — the factor
  /// they produce is mostly noise.
  static const double minimumSpan = 24;

  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _baseline;
  double _factor = 1;

  /// `true` while at least two fingers are down and a baseline was taken.
  bool get isPinching => _baseline != null;

  /// Size change since the pinch began. 1.0 means unchanged.
  double get factor => _factor;

  int get pointerCount => _pointers.length;

  /// Returns `true` when a pinch begins.
  bool onPointerDown(int pointer, Offset position) {
    _pointers[pointer] = position;
    if (_pointers.length < 2) return false;
    if (_baseline == null) return _begin();
    _rebaseline();
    return false;
  }

  /// Returns `true` when [factor] changed and the zone should be resized.
  bool onPointerMove(int pointer, Offset position) {
    if (!_pointers.containsKey(pointer)) return false;
    _pointers[pointer] = position;
    final baseline = _baseline;
    final span = _span();
    if (baseline == null || span == null) return false;

    final next = span / baseline;
    if (!next.isFinite || (next - _factor).abs() < 0.001) return false;
    _factor = next;
    return true;
  }

  /// Returns `true` when the pinch ends.
  bool onPointerUp(int pointer) {
    if (_pointers.remove(pointer) == null) return false;
    if (_pointers.length >= 2) {
      _rebaseline();
      return false;
    }
    if (_baseline == null) return false;
    _baseline = null;
    _factor = 1;
    return true;
  }

  void reset() {
    _pointers.clear();
    _baseline = null;
    _factor = 1;
  }

  bool _begin() {
    final span = _span();
    if (span == null || span < minimumSpan) return false;
    _baseline = span;
    _factor = 1;
    return true;
  }

  /// Keeps [factor] continuous when a finger joins or leaves mid-pinch.
  void _rebaseline() {
    final span = _span();
    if (span == null || span < minimumSpan || _factor <= 0) return;
    _baseline = span / _factor;
  }

  /// Distance between the two fingers that started the pinch.
  double? _span() {
    if (_pointers.length < 2) return null;
    final points = _pointers.values.toList(growable: false);
    final delta = points[1] - points[0];
    final span = math.sqrt(delta.dx * delta.dx + delta.dy * delta.dy);
    return span.isFinite ? span : null;
  }
}
