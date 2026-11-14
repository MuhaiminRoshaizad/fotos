import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/app_tokens.dart';

// Video strips sit on the always-dark viewer and editor: iOS's dark
// system greys, whatever the phone's own theme.
const Color _base = Color(0xFF2C2C2E);
const Color _shine = Color(0xFF3A3A3C);

/// One tile of a video strip: its picture once read, faded in over the
/// strip's loading shimmer, and nothing until then.
class FrameTile extends StatelessWidget {
  const FrameTile({super.key, required this.frame, this.alignment});

  final Uint8List? frame;

  /// Which part of a picture wider than its tile shows; the middle if null.
  final Alignment? alignment;

  @override
  Widget build(BuildContext context) {
    final Uint8List? f = frame;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.short,
      child: f == null
          ? const SizedBox.expand()
          : Image.memory(
              f,
              key: ObjectKey(f),
              fit: BoxFit.cover,
              alignment: alignment ?? Alignment.center,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
    );
  }
}

/// What shows under a strip's tiles: a shimmer while any picture is still
/// to come, then the plain strip colour.
class StripLoading extends StatelessWidget {
  const StripLoading({super.key, required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: _base),
        Skeletonizer(
          enabled: loading,
          effect: MediaQuery.disableAnimationsOf(context)
              ? const SolidColorEffect(color: _base)
              : const ShimmerEffect(baseColor: _base, highlightColor: _shine),
          child: const Bone(width: double.infinity, height: double.infinity),
        ),
      ],
    );
  }
}
