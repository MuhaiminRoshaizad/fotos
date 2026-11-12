import 'dart:async';

import 'package:flutter/services.dart';

/// Areas where Android's back swipe is switched off, so a control dragged
/// near the screen's edge keeps the touch. Each owner sets or clears its
/// own area; Android gets the union. Android honours up to 200 dp of each
/// edge.
abstract final class GestureExclusion {
  static const MethodChannel _channel = MethodChannel('my.minned.fotos/native');
  static final Map<Object, Rect> _areas = <Object, Rect>{};

  /// Sets [owner]'s area in logical pixels, or clears it when [area] is null.
  static void set(Object owner, Rect? area, double devicePixelRatio) {
    final Rect? before = _areas[owner];
    if (area == null) {
      if (before == null) return;
      _areas.remove(owner);
    } else {
      if (before == area) return;
      _areas[owner] = area;
    }
    final List<List<int>> rects = <List<int>>[
      for (final Rect r in _areas.values)
        <int>[
          (r.left * devicePixelRatio).floor(),
          (r.top * devicePixelRatio).floor(),
          (r.right * devicePixelRatio).ceil(),
          (r.bottom * devicePixelRatio).ceil(),
        ],
    ];
    // Best effort: without it the back swipe may still take a drag, which
    // is how it behaved before.
    unawaited(
      _channel
          .invokeMethod<void>('setGestureExclusion', <String, Object>{
            'rects': rects,
          })
          .catchError((Object _) {}),
    );
  }
}
