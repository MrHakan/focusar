class FocusTimer {
  FocusTimer(Duration duration) : remainingSeconds = duration.inSeconds;

  int remainingSeconds;

  bool get isComplete => remainingSeconds <= 0;

  void tick({required bool paused}) {
    if (!paused && remainingSeconds > 0) {
      remainingSeconds -= 1;
    }
  }
}

String formatClock(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
