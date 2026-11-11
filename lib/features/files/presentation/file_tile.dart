import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/motion.dart';
import '../domain/file_entry.dart';
import 'files_providers.dart';

/// One file or folder in the grid view: a large picture (the image itself,
/// a page from inside a ZIP, a frame of a video, or the type's glyph) with
/// the name under it. Tap opens, press and hold starts selecting, and the
/// corner button opens the same More sheet a row's swipe does.
class FileTile extends ConsumerWidget {
  const FileTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.selected,
    this.pinned = false,
  });

  final FileEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  /// Null when the folder is not selecting.
  final bool? selected;

  /// Pinned tiles sit first in their folder, marked with a pin.
  final bool pinned;

  /// Height of the name under the picture, at the user's text size.
  static double labelHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5).scale(13) /
          13 *
          34 +
      AppSpacing.xs;

  /// Portrait, like a book cover: most of what earns a picture here is a
  /// comic or a document.
  static const double coverAspect = 3 / 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool selecting = selected != null;
    final bool on = selected ?? false;
    return Semantics(
      button: true,
      checked: selecting ? on : null,
      label: pinned ? '${entry.name}, pinned' : entry.name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: selecting ? null : onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: coverAspect,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  AnimatedScale(
                    scale: on ? 0.9 : 1,
                    duration: AppMotion.short,
                    curve: Curves.easeOut,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: ColoredBox(
                        color: cs.groupedRow,
                        child: _Cover(entry: entry),
                      ),
                    ),
                  ),
                  if (pinned && !selecting)
                    const Positioned(
                      left: 6,
                      top: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0x8C000000),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            CupertinoIcons.pin_fill,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (selecting)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Pop(
                          on: on,
                          child: GlyphSwap(
                            icon: on
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 24,
                            color: on ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Pressable(
                        label: 'More options for ${entry.name}',
                        minSize: const Size(44, 44),
                        onTap: onMore,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0x8C000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              CupertinoIcons.ellipsis,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: labelHeight(context) - AppSpacing.xs,
              child: Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.5),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.entry});
  final FileEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final (IconData icon, Color? tint) = switch (entry.kind) {
      FileKind.folder => (CupertinoIcons.folder_fill, cs.primary),
      FileKind.image => (CupertinoIcons.photo, null),
      FileKind.video => (CupertinoIcons.film, null),
      FileKind.pdf => (CupertinoIcons.doc_richtext, cs.error),
      FileKind.zip => (CupertinoIcons.archivebox, null),
      FileKind.text => (CupertinoIcons.doc_text, null),
      _ => (CupertinoIcons.doc, null),
    };
    final Widget glyph = Center(
      child: Icon(icon, size: 44, color: tint ?? cs.onSurfaceVariant),
    );
    if (entry.kind == FileKind.image) {
      return Image.file(
        File(entry.path),
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (_, _, _) => glyph,
      );
    }
    final Uint8List? bytes = switch (entry.kind) {
      FileKind.zip =>
        ref.watch(zipCoverProvider((entry.path, entry.size))).value,
      FileKind.video =>
        ref.watch(videoFrameProvider((entry.path, entry.size))).value,
      _ => null,
    };
    // The glyph holds the place until the picture has been read, and stays
    // when there is none.
    return bytes == null
        ? glyph
        : Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => glyph,
          );
  }
}
