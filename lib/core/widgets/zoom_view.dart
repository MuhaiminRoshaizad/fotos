import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Pinch to zoom [child], and with [doubleTap] a double-tap zooms in at the
/// spot tapped, or back out. One finger pans only while zoomed in, so at
/// normal size a swipe still reaches the page around it (to turn pages, or
/// to swipe down and close).
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
  State<ZoomView> createState() => _ZoomViewState();
}

class _ZoomViewState extends State<ZoomView>
    with SingleTickerProviderStateMixin {
  final TransformationController _t = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );
  Animation<Matrix4>? _to;
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_changed);
    _anim.addListener(() {
      if (_to != null) _t.value = _to!.value;
    });
  }

  void _changed() {
    final bool zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomed?.call(zoomed);
  }

  /// In at the spot tapped, or back out to normal size.
  void _toggle() {
    final double s = ZoomView.tapScale;
    final Matrix4 target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -_tapAt.dx * (s - 1),
              -_tapAt.dy * (s - 1),
              0,
              1,
            )
            ..scaleByDouble(s, s, 1, 1));
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

  @override
  void dispose() {
    _t.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget view = InteractiveViewer(
      transformationController: _t,
      maxScale: widget.maxScale,
      panEnabled: _zoomed,
      child: widget.child,
    );
    if (!widget.doubleTap) return view;
    return GestureDetector(
      onDoubleTapDown: (TapDownDetails d) => _tapAt = d.localPosition,
      onDoubleTap: _toggle,
      child: view,
    );
  }
}
