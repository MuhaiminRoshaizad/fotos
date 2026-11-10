import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/format/formatters.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/file_entry.dart';

/// Photos and videos opened from the Files tab, paged through in folder
/// order. Pinch to zoom photos; tap a video to play or pause it.
class FileMediaViewer extends StatefulWidget {
  const FileMediaViewer({super.key, required this.items, required this.index});

  final List<FileEntry> items;
  final int index;

  @override
  State<FileMediaViewer> createState() => _FileMediaViewerState();
}

class _FileMediaViewerState extends State<FileMediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.index);
  late int _index = widget.index;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FileEntry e = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${Fmt.size(e.size)} · ${Fmt.date(e.modified)}',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (int i) => setState(() => _index = i),
        itemBuilder: (BuildContext context, int i) {
          final FileEntry item = widget.items[i];
          if (item.kind == FileKind.video) {
            return _FileVideo(
              key: ValueKey<String>(item.path),
              file: File(item.path),
              active: i == _index,
            );
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(item.path),
                fit: BoxFit.contain,
                cacheWidth: 2560,
                errorBuilder: (_, _, _) => const Text(
                  'This photo can\'t be shown.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FileVideo extends StatefulWidget {
  const _FileVideo({super.key, required this.file, required this.active});
  final File file;
  final bool active;

  @override
  State<_FileVideo> createState() => _FileVideoState();
}

class _FileVideoState extends State<_FileVideo> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then(
      (_) {
        if (!mounted) return;
        setState(() => _ready = true);
        if (widget.active) _c.play();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_FileVideo old) {
    super.didUpdateWidget(old);
    if (_ready && !widget.active) _c.pause();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text(
          'This video can\'t be played.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (!_ready) return const SizedBox.shrink();
    final VideoPlayerValue v = _c.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => v.isPlaying ? _c.pause() : _c.play(),
      child: Stack(
        children: <Widget>[
          Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio,
              child: VideoPlayer(_c),
            ),
          ),
          if (!v.isPlaying)
            const Center(
              child: Icon(
                CupertinoIcons.play_circle,
                size: 72,
                color: Colors.white,
              ),
            ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
            child: Row(
              children: <Widget>[
                Text(
                  '${Fmt.duration(v.position)} / ${Fmt.duration(v.duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: VideoProgressIndicator(
                    _c,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
