import 'package:flutter/gestures.dart';

/// A scale gesture for pinching that leaves a single finger to whatever is
/// around it (a scroll, a page view, a swipe), unless [oneFinger] says to
/// take one too, as a zoomed-in picture does to pan.
///
/// A second finger is a pinch the moment it lands. Waiting for the pinch to
/// show itself lost it to the scroll or page around: a drag counts both
/// fingers' travel and wins at 18 px, while a pinch with one finger held
/// still only spreads half as fast as the other finger moves.
class PinchFirst extends ScaleGestureRecognizer {
  PinchFirst({required this.oneFinger});

  final bool Function() oneFinger;

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    // Only while both fingers are still undecided: one that already
    // started a scroll keeps scrolling, and this one has let it go.
    if (event is PointerDownEvent && pointerCount >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted &&
        pointerCount < 2 &&
        !oneFinger()) {
      return;
    }
    super.resolve(disposition);
  }
}
