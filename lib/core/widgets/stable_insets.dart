import 'package:flutter/widgets.dart';

/// Keeps the status bar and gesture bar insets steady for everything below.
///
/// The viewer hides the system bars while its controls are hidden. Android
/// then reports their insets as zero, and reports them again a few frames
/// after the bars return, so anything placed from the bottom inset (the
/// video controls, the action bar, the floating tab bar after a dismiss)
/// dropped and then jumped back up. The space is the system's whether or
/// not its bar is drawn at this moment, so the largest inset seen in the
/// current orientation is what the app lays out against.
class StableInsets extends StatefulWidget {
  const StableInsets({super.key, required this.child});

  final Widget child;

  @override
  State<StableInsets> createState() => _StableInsetsState();
}

class _StableInsetsState extends State<StableInsets> {
  Orientation? _orientation;
  double _top = 0;
  double _bottom = 0;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    if (mq.orientation != _orientation) {
      // The bars sit elsewhere after a rotation; start again.
      _orientation = mq.orientation;
      _top = 0;
      _bottom = 0;
    }
    if (mq.viewPadding.top > _top) _top = mq.viewPadding.top;
    if (mq.viewPadding.bottom > _bottom) _bottom = mq.viewPadding.bottom;
    // With the keyboard up the bottom inset is the keyboard's business:
    // padding is rightly zero there, and pages add viewInsets themselves.
    final bool keyboard = mq.viewInsets.bottom > 0;
    return MediaQuery(
      data: mq.copyWith(
        viewPadding: mq.viewPadding.copyWith(top: _top, bottom: _bottom),
        padding: mq.padding.copyWith(
          top: _top,
          bottom: keyboard ? mq.padding.bottom : _bottom,
        ),
      ),
      child: widget.child,
    );
  }
}
