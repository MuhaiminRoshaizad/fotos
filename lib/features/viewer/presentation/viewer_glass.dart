import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

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
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
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
