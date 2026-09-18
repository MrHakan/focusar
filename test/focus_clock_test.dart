import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/focus_clock.dart';

void main() {
  group('countdown clock', () {
    test('counts down only while it is running', () {
      final clock = FocusClock.countdown(const Duration(seconds: 3));

      expect(clock.tick(), isTrue);
      expect(clock.displaySeconds, 2);

      expect(clock.tick(paused: true), isFalse);
      expect(clock.displaySeconds, 2);

      clock.tick();
      clock.tick();
      expect(clock.isComplete, isTrue);
      expect(clock.displaySeconds, 0);
    });

    test('stops at zero instead of going negative', () {
      final clock = FocusClock.countdown(const Duration(seconds: 1));
      clock.tick();

      expect(clock.tick(), isFalse);
      expect(clock.displaySeconds, 0);
      expect(clock.elapsedSeconds, 1);
    });

    test('reports progress through the block', () {
      final clock = FocusClock.countdown(const Duration(seconds: 4));
      clock.tick();

      expect(clock.progress, closeTo(0.25, 1e-9));
    });
  });

  group('count-up clock', () {
    test('never completes on its own', () {
      final clock = FocusClock.countUp();
      for (var i = 0; i < 5000; i++) {
        clock.tick();
      }

      expect(clock.isComplete, isFalse);
      expect(clock.displaySeconds, 5000);
    });

    test('sweeps its progress ring once an hour', () {
      final clock = FocusClock.countUp();
      for (var i = 0; i < 1800; i++) {
        clock.tick();
      }

      expect(clock.progress, closeTo(0.5, 1e-9));
    });
  });

  group('formatting', () {
    test('drops the hour field under an hour', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(65), '01:05');
      expect(formatClock(3599), '59:59');
    });

    test('shows unpadded hours above one', () {
      expect(formatClock(3600), '1:00:00');
      expect(formatClock(14100), '3:55:00');
    });

    test('treats a negative clock as zero', () {
      expect(formatClock(-5), '00:00');
    });

    test('writes spans the way the card reads them', () {
      expect(formatSpan(Duration.zero), '0m');
      expect(formatSpan(const Duration(minutes: 45)), '45m');
      expect(formatSpan(const Duration(hours: 2)), '2h');
      expect(formatSpan(const Duration(minutes: 798)), '13h 18m');
    });
  });
}
