import 'json_reader.dart';
import 'session_mode.dart';
import 'session_record.dart';

/// A running session, as last written to disk.
///
/// The OS may kill a backgrounded app without warning, and a session only
/// banks its credits when it ends. So a live session saves one of these every
/// few seconds, and the next launch turns a leftover one into a record instead
/// of losing what it earned.
class SessionCheckpoint {
  const SessionCheckpoint({
    required this.config,
    required this.startedAt,
    required this.savedAt,
    required this.focused,
    required this.creditsEarned,
    required this.interruptions,
  });

  final SessionConfig config;
  final DateTime startedAt;

  /// When this snapshot was taken. Anything after it is unaccounted for.
  final DateTime savedAt;

  final Duration focused;
  final double creditsEarned;
  final int interruptions;

  /// `true` when there is something worth banking.
  bool get hasProgress => focused > Duration.zero || creditsEarned > 0;

  /// What the session would have recorded had it been stopped at [savedAt].
  SessionRecord toRecord() => SessionRecord(
        startedAt: startedAt,
        focused: focused,
        creditsEarned: creditsEarned,
        interruptions: interruptions,
        mode: config.mode,
        method: config.method,
        completed: config.isTimed && focused >= config.target,
      );

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'startedAt': startedAt.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        'focusedSeconds': focused.inSeconds,
        'creditsEarned': creditsEarned,
        'interruptions': interruptions,
      };

  /// `null` when the stored value is too damaged to say when it started —
  /// without that, a record could not be told apart from one already banked.
  static SessionCheckpoint? fromJson(Map<String, dynamic> json) {
    final startedAt = json.readDate('startedAt');
    if (startedAt == null) return null;
    final config = json.readObject('config');
    return SessionCheckpoint(
      config: config == null
          ? const SessionConfig(mode: FocusMode.timed, method: PlacementMethod.motionOnly)
          : SessionConfig.fromJson(config),
      startedAt: startedAt,
      savedAt: json.readDate('savedAt') ?? startedAt,
      focused: json.readDuration('focusedSeconds'),
      creditsEarned: json.readDouble('creditsEarned'),
      interruptions: json.readInt('interruptions'),
    );
  }
}
