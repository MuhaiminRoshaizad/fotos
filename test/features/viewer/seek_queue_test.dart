import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/viewer/presentation/seek_queue.dart';

void main() {
  test('seeks requested during a seek collapse into the newest one', () async {
    final List<Duration> sent = <Duration>[];
    final List<Completer<void>> gates = <Completer<void>>[];
    final SeekQueue queue = SeekQueue((Duration p) {
      sent.add(p);
      gates.add(Completer<void>());
      return gates.last.future;
    });

    queue.request(const Duration(seconds: 1));
    for (int s = 2; s <= 50; s++) {
      queue.request(Duration(seconds: s));
    }
    expect(sent, <Duration>[const Duration(seconds: 1)]);

    gates[0].complete();
    await pumpEventQueue();
    expect(sent, <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 50),
    ]);
  });

  test('idle completes only after the last seek has finished', () async {
    final Completer<void> gate = Completer<void>();
    final SeekQueue queue = SeekQueue((_) => gate.future);
    bool idle = false;

    queue.request(const Duration(seconds: 3));
    unawaited(queue.idle.then((_) => idle = true));
    await pumpEventQueue();
    expect(idle, isFalse);

    gate.complete();
    await pumpEventQueue();
    expect(idle, isTrue);
  });
}
