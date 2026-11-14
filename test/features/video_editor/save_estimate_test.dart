import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/domain/save_estimate.dart';

void main() {
  Duration now = Duration.zero;
  late SaveEstimate estimate;

  setUp(() {
    now = Duration.zero;
    estimate = SaveEstimate(() => now);
  });

  test('says nothing until it has seen enough of the pace', () {
    // Five seconds opening the encoder, then 1% a second.
    now = const Duration(seconds: 5);
    estimate.report(1);
    now = const Duration(seconds: 6);
    estimate.report(2);
    expect(estimate.left, isNull);
  });

  test('leaves out the start-up before the first percent', () {
    now = const Duration(seconds: 30);
    estimate.report(1);
    for (int p = 2; p <= 11; p++) {
      now += const Duration(seconds: 1);
      estimate.report(p);
    }
    // 1% a second since the first report, 89% to go.
    expect(estimate.left, const Duration(seconds: 89));
  });

  test('counts down between reports instead of creeping up', () {
    now = Duration.zero;
    estimate.report(1);
    now = const Duration(seconds: 10);
    estimate.report(6);
    final Duration first = estimate.left!;
    now = const Duration(seconds: 15);
    expect(estimate.left, first - const Duration(seconds: 5));
  });

  test('never goes below nothing while the last percent is slow', () {
    now = Duration.zero;
    estimate.report(1);
    now = const Duration(seconds: 10);
    estimate.report(98);
    now = const Duration(minutes: 5);
    expect(estimate.left, Duration.zero);
  });

  test('goes by the recent pace, not an early jump', () {
    // As on the emulator: half the progress in two seconds, then a percent
    // every 40 seconds.
    now = const Duration(seconds: 1);
    estimate.report(1);
    now = const Duration(seconds: 3);
    estimate.report(50);
    now = const Duration(seconds: 43);
    estimate.report(51);
    expect(estimate.left, const Duration(seconds: 40 * 49));
  });

  test('evens out a quick encode over the last ten seconds', () {
    // A percent every half second, each report a little early or late.
    for (int p = 1; p <= 40; p++) {
      now = Duration(milliseconds: p * 500 + (p.isEven ? 100 : -100));
      estimate.report(p);
    }
    // 60% to go at half a second each.
    expect(estimate.left!.inMilliseconds, closeTo(30000, 1000));
  });

  test('the time left reads as rounded words', () {
    expect(timeLeft(null), 'Working out the time left');
    expect(timeLeft(const Duration(seconds: 4)), 'Almost done');
    expect(timeLeft(const Duration(seconds: 42)), 'About 40 seconds left');
    expect(timeLeft(const Duration(seconds: 59)), 'About 55 seconds left');
    expect(timeLeft(const Duration(seconds: 75)), 'About a minute left');
    expect(
      timeLeft(const Duration(minutes: 3, seconds: 20)),
      'About 3 minutes left',
    );
    expect(
      timeLeft(const Duration(minutes: 59, seconds: 40)),
      'About 1 hour left',
    );
    expect(
      timeLeft(const Duration(minutes: 77)),
      'About 1 hour 15 minutes left',
    );
    expect(timeLeft(const Duration(minutes: 119)), 'About 2 hours left');
  });
}
