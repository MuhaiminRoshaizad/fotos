import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fotos/features/video_editor/presentation/timeline_frames.dart';

void main() {
  test(
    'keeps at most a few hundred frames, the ones nearest the view',
    () async {
      final TimelineFrames frames = TimelineFrames(
        (List<int> times) async => <Uint8List?>[
          for (final int _ in times) Uint8List(1),
        ],
      );
      addTearDown(frames.dispose);
      // Scrolling through 1000 moments, a screenful at a time.
      for (int at = 0; at < 1000; at += 10) {
        frames.want(<int>[for (int t = at; t < at + 10; t++) t]);
        await pumpEventQueue();
      }
      final int kept = <int>[
        for (int t = 0; t < 1000; t++)
          if (frames.has(t)) t,
      ].length;
      expect(kept, TimelineFrames.keep);
      // The latest stretch is kept; the start, long scrolled past, is not.
      expect(frames.has(995), isTrue);
      expect(frames.has(0), isFalse);
    },
  );
}
