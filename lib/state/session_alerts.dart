import 'package:flutter/services.dart';

/// The nudges a session can give. Behind an interface so tests never reach for
/// a platform channel.
abstract class SessionAlerts {
  const SessionAlerts();

  /// The phone settled and the clock started.
  void started();

  /// The phone moved. Repeats for as long as it stays moved.
  void warn();

  /// The session ended on its own terms.
  void finished();
}

/// Haptics and the system alert sound.
class PlatformAlerts extends SessionAlerts {
  const PlatformAlerts();

  @override
  void started() => HapticFeedback.mediumImpact();

  @override
  void warn() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  void finished() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
  }
}

/// Does nothing. Used by tests and by widget previews.
class SilentAlerts extends SessionAlerts {
  const SilentAlerts();

  @override
  void started() {}

  @override
  void warn() {}

  @override
  void finished() {}
}
