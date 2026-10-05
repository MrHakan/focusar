import 'json_reader.dart';

/// How a focus session is scored.
enum FocusMode {
  /// A fixed block. The clock counts down and the session ends by itself.
  timed,

  /// An open block. The clock counts up and only stops when you stop it.
  openEnded,
}

/// How the phone's resting place is chosen before the session starts.
enum PlacementMethod {
  /// Straight to the motion sensors, no camera involved.
  motionOnly,

  /// An ARCore/ARKit zone is anchored to a real surface first.
  arZone,
}

/// Where a session currently sits in its lifecycle.
enum SessionStage {
  /// Waiting for the phone to be put face-down and go still.
  arming,

  /// Counting, credits accruing.
  focusing,

  /// The phone moved. The clock is held and the alarm repeats.
  interrupted,

  /// The person pressed pause. No alarm, no credits, no clock.
  paused,

  /// Finished — either the countdown ran out or an open block was stopped.
  complete,
}

extension FocusModeLabels on FocusMode {
  String get label => switch (this) {
        FocusMode.timed => 'Deep block',
        FocusMode.openEnded => 'Earn screen time',
      };

  String get blurb => switch (this) {
        FocusMode.timed => 'Commit to a fixed length and finish it.',
        FocusMode.openEnded => 'Stay off the phone for as long as you can.',
      };
}

/// Everything needed to start a session.
class SessionConfig {
  const SessionConfig({
    required this.mode,
    required this.method,
    this.target = const Duration(minutes: 25),
  });

  final FocusMode mode;
  final PlacementMethod method;

  /// Only meaningful for [FocusMode.timed].
  final Duration target;

  bool get isTimed => mode == FocusMode.timed;
  bool get usesAr => method == PlacementMethod.arZone;

  SessionConfig copyWith({FocusMode? mode, PlacementMethod? method, Duration? target}) =>
      SessionConfig(
        mode: mode ?? this.mode,
        method: method ?? this.method,
        target: target ?? this.target,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'method': method.name,
        'targetSeconds': target.inSeconds,
      };

  static SessionConfig fromJson(Map<String, dynamic> json) {
    final target = json.readDuration('targetSeconds');
    return SessionConfig(
      mode: json.readEnum('mode', FocusMode.values, FocusMode.timed),
      method: json.readEnum(
        'method',
        PlacementMethod.values,
        PlacementMethod.motionOnly,
      ),
      target: target > Duration.zero ? target : const Duration(minutes: 25),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionConfig &&
      other.mode == mode &&
      other.method == method &&
      other.target == target;

  @override
  int get hashCode => Object.hash(mode, method, target);
}
