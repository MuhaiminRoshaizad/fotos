import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../video_editor/presentation/save_ring.dart';
import '../../../core/format/formatters.dart';
import '../../../core/media/read_mode.dart';
import '../../../core/theme/app_tokens.dart';
import '../../viewer/presentation/strip_viewer.dart';
import '../domain/file_entry.dart';
import 'files_providers.dart';
import '../../../core/widgets/viewer_top_bar.dart';
import '../../../core/widgets/zoom_view.dart';

/// What the `/files/media` route is given: the items, the one to open at,
/// and who to tell as the viewer moves through them.
typedef FileMediaArgs = (List<FileEntry>, int, ValueChanged<FileEntry>?);

/// Opens [items] in the Files viewer at [index]. The only way in, so the
/// route's arguments keep one shape.
void openFileMedia(
  BuildContext context,
  List<FileEntry> items,
  int index, {
  ValueChanged<FileEntry>? onShow,
}) {
  final FileMediaArgs args = (items, index, onShow);
  context.push('/files/media', extra: args);
}

/// Photos and videos opened from the Files tab, paged through in folder
/// order. Pinch to zoom photos; tap a video to play or pause it. Read as in
/// the bar switches the folder between Photos, Pages (a tap on either edge
/// turns the page) and Strip, the same choice the folder has as an album.
class FileMediaViewer extends ConsumerStatefulWidget {
  const FileMediaViewer({
    super.key,
    required this.items,
    required this.index,
    this.onShow,
  });

  final List<FileEntry> items;
  final int index;

  /// Told each item the viewer comes to, so the folder it was opened from
  /// can keep that item in view and closing lands on it.
  final ValueChanged<FileEntry>? onShow;

  @override
  ConsumerState<FileMediaViewer> createState() => _FileMediaViewerState();
}

class _FileMediaViewerState extends ConsumerState<FileMediaViewer> {
  late PageController _pages = PageController(initialPage: widget.index);
  late int _index = widget.index;
  bool _chrome = true;

  /// A picture or video zoomed in: the pages hold still so a finger pans.
  bool _zoomed = false;

  void _setZoomed(bool z) {
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  /// Bumped when the pages are rebuilt at a new place.
  int _generation = 0;

  String? _shown;

  /// Tells [FileMediaViewer.onShow] once about each item come to, after the
  /// frame, so the folder scrolls in its own layout.
  void _show(FileEntry e) {
    final ValueChanged<FileEntry>? onShow = widget.onShow;
    if (onShow == null || e.path == _shown) return;
    _shown = e.path;
    WidgetsBinding.instance.addPostFrameCallback((_) => onShow(e));
  }

  List<FileEntry> get _pictures => <FileEntry>[
    for (final FileEntry e in widget.items)
      if (e.kind == FileKind.image) e,
  ];

  String? get _folder {
    final String? root = ref.watch(storageRootProvider).value;
    if (root == null || widget.items.isEmpty) return null;
    // Joined with / on any platform, as Albums writes it.
    return readingKey(
      p
          .split(p.relative(p.dirname(widget.items.first.path), from: root))
          .join('/'),
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _showAt(int at) {
    final PageController old = _pages;
    setState(() {
      _index = at;
      _pages = PageController(initialPage: at);
      _generation++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _chooseReadMode(String folder) async {
    final ReadMode now = readModeFor(ref.read(readModesProvider).value, folder);
    final ReadMode? next = await chooseReadMode(context, now);
    if (next == null || next == now) return;
    await ref.read(readModesProvider.notifier).set(folder, next);
  }

  /// Pages mode: the left or right third turns the page, the middle shows
  /// or hides the bar.
  void _tapAt(double dx, ReadMode mode) {
    final double third = MediaQuery.sizeOf(context).width / 3;
    final int step = mode != ReadMode.pages
        ? 0
        : (dx < third ? -1 : (dx > third * 2 ? 1 : 0));
    if (step == 0) return setState(() => _chrome = !_chrome);
    final int to = _index + step;
    if (to < 0 || to >= widget.items.length) return;
    MediaQuery.disableAnimationsOf(context)
        ? _pages.jumpToPage(to)
        : _pages.animateToPage(
            to,
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
          );
  }

  @override
  Widget build(BuildContext context) {
    final String? folder = _folder;
    final ReadMode mode = readModeFor(
      ref.watch(readModesProvider).value,
      folder,
    );
    if (mode == ReadMode.strip && folder != null) {
      final List<FileEntry> pictures = _pictures;
      final int at = pictures.indexOf(widget.items[_index]);
      final List<double>? aspects = ref
          .watch(
            pictureAspectsProvider(
              pictures.map((FileEntry e) => e.path).join('\n'),
            ),
          )
          .value;
      if (aspects == null) {
        return const Scaffold(backgroundColor: Colors.black);
      }
      _show(at < 0 ? widget.items[_index] : pictures[at]);
      return StripViewer(
        title: p.basename(p.dirname(widget.items.first.path)),
        index: at < 0 ? 0 : at,
        pages: <StripPage>[
          for (final (int i, FileEntry e) in pictures.indexed)
            StripPage(
              aspect: aspects[i],
              image: (int width) => ResizeImage(
                FileImage(File(e.path)),
                width: width,
                policy: ResizeImagePolicy.fit,
              ),
            ),
        ],
        onPage: (int page) => _show(pictures[page]),
        onReadMode: (int page) {
          // Back in Photos or Pages, carry on from the page on screen.
          _showAt(widget.items.indexOf(pictures[page]));
          _chooseReadMode(folder);
        },
      );
    }
    final FileEntry e = widget.items[_index];
    _show(e);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            key: ValueKey<int>(_generation),
            controller: _pages,
            // Zoomed in, a finger pans the picture instead of turning the page.
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.items.length,
            onPageChanged: (int i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (BuildContext context, int i) {
              final FileEntry item = widget.items[i];
              if (item.kind == FileKind.video) {
                return _FileVideo(
                  key: ValueKey<String>(item.path),
                  file: File(item.path),
                  active: i == _index,
                  onZoomed: _setZoomed,
                );
              }
              return GestureDetector(
                onTapUp: (TapUpDetails d) => _tapAt(d.globalPosition.dx, mode),
                child: ZoomView(
                  onZoomed: _setZoomed,
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
                ),
              );
            },
          ),
          ViewerTopBar(
            visible: _chrome,
            status: SaveRing(flies: _chrome),
            title: e.name,
            subtitle: '${Fmt.size(e.size)} · ${Fmt.date(e.modified)}',
            onClose: () => Navigator.of(context).pop(),
            // Pages and Strip are ways to read pictures, not videos.
            trailing: folder != null && e.kind == FileKind.image
                ? ReadModeButton(onPressed: () => _chooseReadMode(folder))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Width over height of each picture at [paths] (one per line), read from
/// the file's header without decoding it, so a strip can lay every page out
/// at its true height before any picture arrives.
final pictureAspectsProvider = FutureProvider.autoDispose
    .family<List<double>, String>((Ref ref, String paths) async {
      final List<double> out = <double>[];
      for (final String path in paths.split('\n')) {
        double aspect = 0.7;
        try {
          final ui.ImmutableBuffer data = await ui.ImmutableBuffer.fromFilePath(
            path,
          );
          final ui.ImageDescriptor d = await ui.ImageDescriptor.encoded(data);
          if (d.width > 0 && d.height > 0) aspect = d.width / d.height;
          d.dispose();
          data.dispose();
        } on Exception {
          // A picture that can't be read keeps a comic page's shape.
        }
        out.add(aspect);
      }
      return out;
    });

class _FileVideo extends StatefulWidget {
  const _FileVideo({
    super.key,
    required this.file,
    required this.active,
    required this.onZoomed,
  });
  final File file;
  final bool active;
  final ValueChanged<bool> onZoomed;

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
          // Pinch zooms; a tap still plays and pauses.
          ZoomView(
            doubleTap: false,
            onZoomed: widget.onZoomed,
            child: Center(
              child: AspectRatio(
                aspectRatio: v.aspectRatio,
                child: VideoPlayer(_c),
              ),
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
