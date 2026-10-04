import 'json_reader.dart';
import 'motion_guard.dart';

/// The settings a person chooses once and expects to stick.
class FocusPreferences {
  const FocusPreferences({this.sensitivity = Sensitivity.balanced});

  static const FocusPreferences defaults = FocusPreferences();

  /// How readily the motion guard calls a pick-up.
  final Sensitivity sensitivity;

  FocusPreferences copyWith({Sensitivity? sensitivity}) =>
      FocusPreferences(sensitivity: sensitivity ?? this.sensitivity);

  Map<String, dynamic> toJson() => {'sensitivity': sensitivity.name};

  static FocusPreferences fromJson(Map<String, dynamic> json) =>
      FocusPreferences(
        sensitivity: json.readEnum(
          'sensitivity',
          Sensitivity.values,
          Sensitivity.balanced,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is FocusPreferences && other.sensitivity == sensitivity;

  @override
  int get hashCode => sensitivity.hashCode;
}
