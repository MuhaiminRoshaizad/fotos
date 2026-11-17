import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Keeps track of the sheets, dialogs and menus open over the app, so the
/// frosted bars beneath them can stop blurring ([Frost]). Registered on the
/// root navigator, where every one of them opens.
class PopupWatch extends NavigatorObserver with ChangeNotifier {
  /// Each one tracked, with the listener on its animation.
  final Map<ModalRoute<dynamic>, VoidCallback> _open =
      <ModalRoute<dynamic>, VoidCallback>{};

  /// How much of the blur shows: 1 with nothing open, 0 once one is fully
  /// up, and in between while one opens, closes or is dragged, in step with
  /// the scrim it fades under (the route's own barrier curve). A route that
  /// has been disposed, as when its navigator has gone, counts as closed.
  double get clear {
    double cover = 0;
    for (final ModalRoute<dynamic> r in _open.keys) {
      if (r.navigator == null) continue;
      final Animation<double>? a = r.animation;
      final double v = a == null ? 1 : r.barrierCurve.transform(a.value);
      if (v > cover) cover = v;
    }
    return 1 - cover;
  }

  void _add(Route<dynamic>? r) {
    if (r is! PopupRoute || _open.containsKey(r)) return;
    for (final ModalRoute<dynamic> gone
        in _open.keys
            .where((ModalRoute<dynamic> o) => o.navigator == null)
            .toList()) {
      final VoidCallback changed = _open.remove(gone)!;
      gone.animation?.removeListener(changed);
    }
    final Animation<double>? a = r.animation;
    void changed() {
      // Closed and finished closing: nothing of it is left on screen.
      if (a!.isDismissed && !r.isActive) {
        _remove(r);
      } else {
        notifyListeners();
      }
    }

    _open[r] = changed;
    a?.addListener(changed);
    notifyListeners();
  }

  void _remove(Route<dynamic>? r) {
    final VoidCallback? changed = _open.remove(r);
    if (changed == null) return;
    (r! as ModalRoute<dynamic>).animation?.removeListener(changed);
    notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  // A popped route stays tracked while it animates away, so the blur comes
  // back as its scrim fades; it goes once the animation has finished.

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }
}

/// The app's one [PopupWatch], beside the root navigator it watches.
final PopupWatch popupWatch = PopupWatch();

/// A frosted backdrop: [child] over a blur of what is behind it.
///
/// While a sheet, dialog or menu is open the blur is switched off: the bars
/// sit under its scrim or behind it, where the blur barely shows, yet each
/// one still cost a full-screen pass every frame. With the selection bar
/// under it, scrolling the Move to picker missed the 120 Hz budget (8.3 ms)
/// on 1.6% of frames, and 0.2% without the blurs (measured on the phone,
/// 17/11/2026).
///
/// It fades out as the sheet comes up and back in as it goes, rather than
/// switching in one frame: switched, the bars went sharp while the scrim
/// over them had barely begun, which showed as a flicker. `enabled` keeps
/// the tree as it is, so nothing inside is rebuilt.
class Frost extends StatelessWidget {
  const Frost({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: popupWatch,
    builder: (BuildContext context, Widget? child) {
      final double s = sigma * popupWatch.clear;
      return BackdropFilter(
        // Below half a pixel the blur can't be seen, but still costs.
        enabled: s >= 0.5,
        filter: ImageFilter.blur(sigmaX: s, sigmaY: s),
        child: child,
      );
    },
    child: child,
  );
}
