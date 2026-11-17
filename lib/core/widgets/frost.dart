import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Keeps track of the sheets, dialogs and menus open over the app, so the
/// frosted bars beneath them can stop blurring ([Frost]). Registered on the
/// root navigator, where every one of them opens.
class PopupWatch extends NavigatorObserver with ChangeNotifier {
  final Set<Route<dynamic>> _open = <Route<dynamic>>{};

  /// Whether one is open now. A route whose navigator has gone counts as
  /// closed.
  bool get open => _open.any((Route<dynamic> r) => r.isActive);

  void _add(Route<dynamic>? r) {
    if (r is PopupRoute && _open.add(r)) notifyListeners();
  }

  void _remove(Route<dynamic>? r) {
    if (_open.remove(r)) notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  // At the start of the closing animation, so the blur is back before the
  // sheet has moved off it.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

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
/// 17/11/2026). `enabled` keeps the tree as it is, so nothing inside is
/// rebuilt.
class Frost extends StatelessWidget {
  const Frost({super.key, required this.sigma, required this.child});

  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: popupWatch,
    builder: (BuildContext context, Widget? child) => BackdropFilter(
      enabled: !popupWatch.open,
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    ),
    child: child,
  );
}
