import 'json_reader.dart';
import 'session_mode.dart';

/// What a finished session leaves behind.
class SessionRecord {
  const SessionRecord({
    required this.startedAt,
    required this.focused,
    required this.creditsEarned,
    required this.interruptions,
    required this.mode,
    required this.method,
    required this.completed,
  });

  final DateTime startedAt;

  /// Time that actually counted — pauses and interruptions excluded.
  final Duration focused;

  final double creditsEarned;

  /// How many times the phone was picked up or moved.
  final int interruptions;

  final FocusMode mode;
  final PlacementMethod method;

  /// `true` when a countdown ran out, `false` when the session was stopped early.
  final bool completed;

  /// A run with no interruptions at all.
  bool get clean => interruptions == 0;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'focusedSeconds': focused.inSeconds,
        'creditsEarned': creditsEarned,
        'interruptions': interruptions,
        'mode': mode.name,
        'method': method.name,
        'completed': completed,
      };

  static SessionRecord fromJson(Map<String, dynamic> json) => SessionRecord(
        startedAt: json.readDate('startedAt') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        focused: json.readDuration('focusedSeconds'),
        creditsEarned: json.readDouble('creditsEarned'),
        interruptions: json.readInt('interruptions'),
        mode: _enumByName(FocusMode.values, json['mode'], FocusMode.timed),
        method: _enumByName(
          PlacementMethod.values,
          json['method'],
          PlacementMethod.motionOnly,
        ),
        completed: json.readBool('completed'),
      );
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
