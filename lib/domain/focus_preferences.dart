import 'json_reader.dart';
import 'motion_guard.dart';
import 'session_mode.dart';

/// The settings a person chooses once and expects to stick.
class FocusPreferences {
  const FocusPreferences({
    this.sensitivity = Sensitivity.balanced,
    this.dailyGoal = const Duration(hours: 1),
    this.lastConfig,
  });

  /// The daily goals offered on the progress screen.
  static const List<Duration> goalOptions = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(minutes: 90),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
  ];

  static const FocusPreferences defaults = FocusPreferences();

  /// How readily the motion guard calls a pick-up.
  final Sensitivity sensitivity;

  /// Focus a day should hold.
  final Duration dailyGoal;

  /// The settings the last session started with, for quick start. `null`
  /// until a first session has run.
  final SessionConfig? lastConfig;

  FocusPreferences copyWith({
    Sensitivity? sensitivity,
    Duration? dailyGoal,
    SessionConfig? lastConfig,
  }) =>
      FocusPreferences(
        sensitivity: sensitivity ?? this.sensitivity,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        lastConfig: lastConfig ?? this.lastConfig,
      );

  Map<String, dynamic> toJson() => {
        'sensitivity': sensitivity.name,
        'dailyGoalSeconds': dailyGoal.inSeconds,
        if (lastConfig != null) 'lastConfig': lastConfig!.toJson(),
      };

  static FocusPreferences fromJson(Map<String, dynamic> json) =>
      FocusPreferences(
        sensitivity: json.readEnum(
          'sensitivity',
          Sensitivity.values,
          Sensitivity.balanced,
        ),
        dailyGoal: _readGoal(json),
        lastConfig: _readConfig(json),
      );

  static SessionConfig? _readConfig(Map<String, dynamic> json) {
    final config = json.readObject('lastConfig');
    return config == null ? null : SessionConfig.fromJson(config);
  }

  static Duration _readGoal(Map<String, dynamic> json) {
    final goal = json.readDuration('dailyGoalSeconds');
    return goal > Duration.zero ? goal : defaults.dailyGoal;
  }

  @override
  bool operator ==(Object other) =>
      other is FocusPreferences &&
      other.sensitivity == sensitivity &&
      other.dailyGoal == dailyGoal &&
      other.lastConfig == lastConfig;

  @override
  int get hashCode => Object.hash(sensitivity, dailyGoal, lastConfig);
}
