import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Pinch to zoom [child], and with [doubleTap] a double-tap zooms in at the
/// spot tapped, or back out. At normal size it never takes a single finger,
/// so a swipe still reaches what is around it: turning pages, scrolling a
/// strip, or swiping a video down to close. Zoomed in, one finger pans;
/// [onZoomed] lets a page view stop paging meanwhile.
///
/// It is not an InteractiveViewer: that one takes a one-finger drag even
/// at normal size, and on a video it won the swipe-down that closes the
/// viewer (found on the phone, 13/11/2026).
class ZoomView extends StatefulWidget {
  const ZoomView({
    super.key,
    required this.child,
    this.doubleTap = true,
    this.maxScale = 5,
    this.onZoomed,
  });

  final Widget child;

  /// False where a double-tap already means something else, as on a video,
  /// where it skips or plays.
  final bool doubleTap;
  final double maxScale;

  /// Called when it goes from normal size to zoomed in, or back.
  final ValueChanged<bool>? onZoomed;

  /// How far a double-tap zooms in.
  static const double tapScale = 2.6;

  @override
  State<ZoomView> createState() => ZoomViewState();
}

class ZoomViewState extends State<ZoomView>
    with SingleTickerProviderStateMixin {
  final TransformationController _t = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );
  Animation<Matrix4>? _to;
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;
  Size _size = Size.zero;

  // Where a pinch began.
  Matrix4 _startMatrix = Matrix4.identity();
  Offset _startFocal = Offset.zero;
  double _startScale = 1;

  /// The transform drawn now: identity at normal size.
  Matrix4 get transform => _t.value;

  double get _scale => _t.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _t.addListener(_changed);
    _anim.addListener(() {
      if (_to != null) _t.value = _to!.value;
    });
  }

  void _changed() {
    final bool zoomed = _scale > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomed?.call(zoomed);
  }

  /// [scale] about the top-left, moved by [offset], kept so the child
  /// always covers the view.
  Matrix4 _matrix(double scale, Offset offset) {
    final Offset o = Offset(
      offset.dx.clamp(_size.width * (1 - scale), 0.0),
      offset.dy.clamp(_size.height * (1 - scale), 0.0),
    );
    return Matrix4.identity()
      ..translateByDouble(o.dx, o.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _animateTo(Matrix4 target) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = target;
      return;
    }
    _to = Matrix4Tween(
      begin: _t.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: AppMotion.emphasized));
    _anim.forward(from: 0);
  }

  /// In at the spot tapped, or back out to normal size.
  void _toggle() {
    const double s = ZoomView.tapScale;
    _animateTo(_zoomed ? Matrix4.identity() : _matrix(s, -_tapAt * (s - 1)));
  }

  void _onStart(ScaleStartDetails d) {
    _anim.stop();
    _startMatrix = _t.value.clone();
    _startFocal = d.localFocalPoint;
    _startScale = _scale;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    final double s = (_startScale * d.scale).clamp(1.0, widget.maxScale);
    // Keep the point of the picture that was under the fingers under them.
    final Offset p = MatrixUtils.transformPoint(
      Matrix4.inverted(_startMatrix),
      _startFocal,
    );
    _t.value = _matrix(s, d.localFocalPoint - p * s);
  }

  void _onEnd(ScaleEndDetails d) {
    if (_scale < 1.01) _animateTo(Matrix4.identity());
  }

  @override
  void dispose() {
    _t.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        _size = c.biggest;
        return RawGestureDetector(
          // The whole view, margins too: a tap beside a narrow page still
          // reaches whatever turns the page.
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _PinchFirst: GestureRecognizerFactoryWithHandlers<_PinchFirst>(
              () => _PinchFirst(zoomed: () => _zoomed),
              (_PinchFirst r) => r
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd,
            ),
          },
          child: ClipRect(
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: _t,
              builder: (BuildContext context, Matrix4 m, Widget? child) =>
                  Transform(transform: m, child: child),
              child: widget.child,
            ),
          ),
        );
      },
    );
    if (!widget.doubleTap) return view;
    return GestureDetector(
      onDoubleTapDown: (TapDownDetails d) => _tapAt = d.localPosition,
      onDoubleTap: _toggle,
      child: view,
    );
  }
}

/// A scale gesture that won't take a single finger at normal size, so a
/// swipe goes to whatever is around it; two fingers, or any once zoomed in,
/// it takes as usual.
///
/// A second finger is a pinch the moment it lands. Waiting for the pinch to
/// show itself lost it to the scroll or page around: a drag counts both
/// fingers' travel and wins at 18 px, while a pinch with one finger held
/// still only spreads half as fast as the other finger moves.
class _PinchFirst extends ScaleGestureRecognizer {
  _PinchFirst({required this.zoomed});

  final bool Function() zoomed;

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
        !zoomed()) {
      return;
    }
    super.resolve(disposition);
  }
}
