import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/services/focus_timer.dart';

void main() {
  test('focus clock counts down only while active', () {
    final timer = FocusTimer(const Duration(seconds: 2));

    timer.tick(paused: false);
    expect(timer.remainingSeconds, 1);

    timer.tick(paused: true);
    expect(timer.remainingSeconds, 1);

    timer.tick(paused: false);
    expect(timer.isComplete, isTrue);
  });

  test('clock formatting supports short and long sessions', () {
    expect(formatClock(65), '01:05');
    expect(formatClock(3661), '01:01:01');
  });
}
