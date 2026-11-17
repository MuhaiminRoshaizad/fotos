import 'package:flutter/material.dart';

import 'frost.dart';

/// Frosted dark glass for the viewer's controls, readable over any photo or
/// video. [shape] is a circle for a single button, a stadium for a row.
class ViewerGlass extends StatelessWidget {
  const ViewerGlass({super.key, required this.shape, required this.child});

  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      // Off under a sheet like the app's bars: over a playing video each
      // panel re-blurs every frame, and with a sheet on top the viewer drew
      // in about 20 ms a frame (phone, 17/11/2026).
      child: Frost(
        sigma: 24,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: const Color(0x8C1C1C1E),
            shape: shape is CircleBorder
                ? const CircleBorder(
                    side: BorderSide(color: Color(0x1FFFFFFF), width: 0.5),
                  )
                : const StadiumBorder(
                    side: BorderSide(color: Color(0x1FFFFFFF), width: 0.5),
                  ),
          ),
          child: child,
        ),
      ),
    );
  }
}
