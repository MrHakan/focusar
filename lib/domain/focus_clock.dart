/// A second-resolution clock that can either count down to a target or count
/// up without one. Pure logic so the session machine stays testable.
class FocusClock {
  /// Counts down from [target] and completes when it reaches zero.
  FocusClock.countdown(Duration target)
      : targetSeconds = target.inSeconds,
        _elapsed = 0;

  /// Counts up forever. Only an explicit stop ends it.
  FocusClock.countUp()
      : targetSeconds = null,
        _elapsed = 0;

  /// Total seconds to reach, or `null` for an open-ended clock.
  final int? targetSeconds;

  int _elapsed;

  /// Seconds actually spent focusing. Paused time never lands here.
  int get elapsedSeconds => _elapsed;

  Duration get elapsed => Duration(seconds: _elapsed);

  bool get isCountdown => targetSeconds != null;

  /// Seconds left on a countdown, or the elapsed count for an open clock.
  int get displaySeconds {
    final target = targetSeconds;
    if (target == null) return _elapsed;
    final left = target - _elapsed;
    return left < 0 ? 0 : left;
  }

  /// `true` once a countdown has run out. Open clocks never self-complete.
  bool get isComplete {
    final target = targetSeconds;
    return target != null && _elapsed >= target;
  }

  /// 0..1 through a countdown. Open clocks sweep once per hour so the ring
  /// still has something honest to show.
  double get progress {
    final target = targetSeconds;
    if (target == null || target == 0) {
      return (_elapsed % 3600) / 3600;
    }
    final value = _elapsed / target;
    return value.clamp(0.0, 1.0);
  }

  /// Advances one second unless [paused]. Returns `true` if the clock moved.
  bool tick({bool paused = false}) {
    if (paused || isComplete) return false;
    _elapsed += 1;
    return true;
  }
}

/// `25:00` under an hour, `3:55:00` above it — hours are never zero-padded.
String formatClock(int totalSeconds) {
  final safe = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// A human span: `13h 18m`, `45m`, `0m`.
String formatSpan(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes <= 0) return '0m';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
