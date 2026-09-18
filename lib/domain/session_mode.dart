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
}
