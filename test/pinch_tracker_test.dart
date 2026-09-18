import 'package:flutter_test/flutter_test.dart';
import 'package:focusar/domain/pinch_tracker.dart';

void main() {
  late PinchTracker tracker;

  setUp(() => tracker = PinchTracker());

  test('one finger is not a pinch', () {
    expect(tracker.onPointerDown(1, const Offset(0, 0)), isFalse);
    expect(tracker.isPinching, isFalse);
    expect(tracker.onPointerMove(1, const Offset(80, 0)), isFalse);
  });

  test('two fingers start a pinch and report the spread', () {
    expect(tracker.onPointerDown(1, const Offset(0, 0)), isFalse);
    expect(tracker.onPointerDown(2, const Offset(100, 0)), isTrue);
    expect(tracker.isPinching, isTrue);
    expect(tracker.factor, 1.0);

    expect(tracker.onPointerMove(2, const Offset(200, 0)), isTrue);
    expect(tracker.factor, closeTo(2.0, 1e-9));

    expect(tracker.onPointerMove(2, const Offset(50, 0)), isTrue);
    expect(tracker.factor, closeTo(0.5, 1e-9));
  });

  test('ignores a pinch that starts with the fingers touching', () {
    tracker.onPointerDown(1, const Offset(0, 0));

    expect(tracker.onPointerDown(2, const Offset(4, 0)), isFalse);
    expect(tracker.isPinching, isFalse);
  });

  test('lifting a finger ends the pinch and resets the factor', () {
    tracker.onPointerDown(1, const Offset(0, 0));
    tracker.onPointerDown(2, const Offset(100, 0));
    tracker.onPointerMove(2, const Offset(150, 0));

    expect(tracker.onPointerUp(2), isTrue);
    expect(tracker.isPinching, isFalse);
    expect(tracker.factor, 1.0);
    expect(tracker.pointerCount, 1);
  });

  test('a third finger does not make the size jump', () {
    tracker.onPointerDown(1, const Offset(0, 0));
    tracker.onPointerDown(2, const Offset(100, 0));
    tracker.onPointerMove(2, const Offset(160, 0));
    final before = tracker.factor;

    expect(tracker.onPointerDown(3, const Offset(20, 40)), isFalse);
    expect(tracker.factor, closeTo(before, 1e-9));
  });

  test('ignores movement from a finger it never saw go down', () {
    tracker.onPointerDown(1, const Offset(0, 0));
    tracker.onPointerDown(2, const Offset(100, 0));

    expect(tracker.onPointerMove(9, const Offset(500, 500)), isFalse);
    expect(tracker.factor, 1.0);
  });

  test('swallows movement too small to be a resize', () {
    tracker.onPointerDown(1, const Offset(0, 0));
    tracker.onPointerDown(2, const Offset(1000, 0));

    expect(tracker.onPointerMove(2, const Offset(1000.5, 0)), isFalse);
  });

  test('reset clears every finger', () {
    tracker.onPointerDown(1, const Offset(0, 0));
    tracker.onPointerDown(2, const Offset(100, 0));
    tracker.reset();

    expect(tracker.isPinching, isFalse);
    expect(tracker.pointerCount, 0);
    expect(tracker.factor, 1.0);
  });
}
