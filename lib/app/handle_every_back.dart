import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps Android passing every Back to fotos, so Flutter decides what each
/// one does: a pushed page closes, another tab goes to the first, and the
/// first tab asks before leaving (see TabRoot).
///
/// On Android 14 and later the app tells Android in advance whether it
/// handles Back, and Android closes the app itself when the answer is no.
/// Flutter's default relays an answer from whichever navigator last
/// changed; fotos has several (the shell, each tab, the viewer, sheets),
/// and one that cannot pop answers no, so after a sheet or the viewer
/// closed, Back on a tab closed fotos without asking. Logged on the phone
/// on 12/11/2026. When nothing in fotos takes a Back, Flutter closes the
/// app itself, so always answering yes loses nothing.
bool handleEveryBack(NavigationNotification notification) {
  _tellAndroid();
  return true;
}

void _tellAndroid() {
  final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
  // As Flutter's own relay: the engine isn't ready before the app starts.
  if (state == null || state == AppLifecycleState.detached) return;
  SystemNavigator.setFrameworkHandlesBack(true);
}

/// Says it again each time fotos comes to the front: a new Android window
/// for the same app starts without the answer.
class HandleEveryBack extends StatefulWidget {
  const HandleEveryBack({super.key, required this.child});

  final Widget child;

  @override
  State<HandleEveryBack> createState() => _HandleEveryBackState();
}

class _HandleEveryBackState extends State<HandleEveryBack> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: _tellAndroid,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tellAndroid());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
