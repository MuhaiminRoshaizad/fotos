import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import 'files_providers.dart';

/// A picture or video file's thumbnail from Android's thumbnail store, with
/// [placeholder] (the file's glyph) until it arrives and where there is
/// none.
class FileThumb extends ConsumerWidget {
  const FileThumb({
    super.key,
    required this.path,
    required this.px,
    required this.placeholder,
  });

  final String path;

  /// The thumbnail's size in physical pixels.
  final int px;
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Uint8List? bytes = ref.watch(fileThumbProvider((path, px))).value;
    return AnimatedSwitcher(
      duration: AppMotion.short,
      child: bytes == null
          ? KeyedSubtree(key: const ValueKey<bool>(false), child: placeholder)
          : Image.memory(
              bytes,
              key: const ValueKey<bool>(true),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
