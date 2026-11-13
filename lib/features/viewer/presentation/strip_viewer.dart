import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/media/animated.dart';
import '../../../core/media/read_mode.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/scroll_handle.dart';
import '../../../core/widgets/zoom_view.dart';
import 'viewer_glass.dart';

/// One page of a strip: its shape, and its picture decoded [width] pixels
/// across.
class StripPage {
  const StripPage({required this.aspect, required this.image});

  /// Width over height.
  final double aspect;
  final ImageProvider Function(int width) image;

  /// A photo or video frame from the library, by its known size.
  factory StripPage.asset(AssetEntity e) {
    final Size s = e.orientatedSize;
    return StripPage(
      // An item whose size Android doesn't know reads as a comic page.
      aspect: s.width > 0 && s.height > 0 ? s.width / s.height : 0.7,
      // A moving page plays from its original file; a still preview would
      // show only its first frame.
      image: (int width) => mayAnimate(e)
          ? AssetEntityImageProvider(e)
          : AssetEntityImageProvider(
              e,
              isOriginal: false,
              thumbnailSize: ThumbnailSize(
                width,
                (width *
                        (s.height > 0 && s.width > 0
                            ? s.height / s.width
                            : 1.43))
                    .round(),
              ),
            ),
    );
  }
}

/// Asks which way to read, showing the current one. Null when dismissed.
Future<ReadMode?> chooseReadMode(BuildContext context, ReadMode now) =>
    showActionSheet<ReadMode>(
      context,
      title: 'Read as',
      message: 'Now: ${now.label}',
      choices: const <SheetChoice<ReadMode>>[
        SheetChoice<ReadMode>(ReadMode.photos, 'Photos'),
        SheetChoice<ReadMode>(ReadMode.pages, 'Pages: tap the edges to turn'),
        SheetChoice<ReadMode>(ReadMode.strip, 'Strip: one long scroll'),
      ],
    );

/// A folder read as one long strip: every page full width, top to bottom,
/// with no gaps, the way long-strip comics are drawn. Each page takes its
/// real height from the start, so nothing shifts as the pictures arrive. A
/// tap shows or hides the bar.
class StripViewer extends StatefulWidget {
  const StripViewer({
    super.key,
    required this.title,
    required this.pages,
    required this.index,
    this.onReadMode,
  });

  final String title;
  final List<StripPage> pages;

  /// The page to open at.
  final int index;

  /// The bar's reading-mode button, given the page on screen; none when
  /// null.
  final ValueChanged<int>? onReadMode;

  @override
  State<StripViewer> createState() => _StripViewerState();
}

class _StripViewerState extends State<StripViewer> {
  ScrollController? _scroll;
  bool _chrome = true;
  bool _zoomed = false;
  late int _page = widget.index;

  /// Where each page starts, at the current width, plus the strip's end.
  List<double> _tops = const <double>[];
  double _width = 0;

  void _layout(double width) {
    if (width == _width) return;
    _width = width;
    double y = 0;
    final List<double> tops = <double>[];
    for (final StripPage page in widget.pages) {
      tops.add(y);
      y += width / page.aspect;
    }
    _tops = <double>[...tops, y];
  }

  @override
  void dispose() {
    _scroll?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggle() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(
      _chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  /// The page under the middle of the screen when scrolled to [offset].
  int _pageAt(double offset) {
    final ScrollController? s = _scroll;
    if (s == null || !s.hasClients || _tops.length < 2) return _page;
    final double mid = offset + s.position.viewportDimension / 2;
    int lo = 0;
    int hi = widget.pages.length - 1;
    while (lo < hi) {
      final int m = (lo + hi + 1) ~/ 2;
      if (_tops[m] <= mid) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    return lo;
  }

  void _track() {
    final ScrollController? s = _scroll;
    if (s == null || !s.hasClients) return;
    final int page = _pageAt(s.offset);
    if (page != _page) setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          _layout(c.maxWidth);
          _scroll ??= ScrollController(initialScrollOffset: _tops[widget.index])
            ..addListener(_track);
          // Decoded at the screen's width, no larger: a long strip holds
          // many pages in memory at once. Zoomed in, the pages on screen are
          // decoded at twice that so they stay sharp.
          final int px = _zoomed
              ? math.min((c.maxWidth * dpr * 2).round(), 2880)
              : math.min((c.maxWidth * dpr).round(), 1440);
          return Stack(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                // Pinch or double-tap to zoom into a panel; one finger
                // still scrolls the strip.
                child: ZoomView(
                  onZoomed: (bool z) => setState(() => _zoomed = z),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: widget.pages.length,
                    itemExtentBuilder: (int i, _) => _tops[i + 1] - _tops[i],
                    itemBuilder: (BuildContext context, int i) => Semantics(
                      image: true,
                      label: 'Page ${i + 1} of ${widget.pages.length}',
                      child: ColoredBox(
                        color: const Color(0xFF151517),
                        child: Image(
                          image: widget.pages[i].image(px),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // A long comic is hundreds of screens; the handle jumps
              // through it, naming the page it lands on.
              Positioned(
                top: MediaQuery.paddingOf(context).top + 72,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
                child: ScrollHandle(
                  controller: _scroll!,
                  semanticLabel: 'Scroll by page',
                  labelAt: (double offset) => HandleLabel(
                    'Page ${_pageAt(offset) + 1}',
                    secondary: 'of ${widget.pages.length}',
                  ),
                ),
              ),
              _StripBar(
                visible: _chrome,
                title: widget.title,
                page: '${_page + 1} of ${widget.pages.length}',
                onClose: () => Navigator.of(context).pop(),
                onReadMode: widget.onReadMode == null
                    ? null
                    : () => widget.onReadMode!(_page),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StripBar extends StatelessWidget {
  const _StripBar({
    required this.visible,
    required this.title,
    required this.page,
    required this.onClose,
    required this.onReadMode,
  });

  final bool visible;
  final String title;
  final String page;
  final VoidCallback onClose;
  final VoidCallback? onReadMode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.short,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x8C000000), Color(0x00000000)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: SizedBox(
                  height: 48,
                  child: NavigationToolbar(
                    leading: ViewerGlass(
                      shape: const CircleBorder(),
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: onClose,
                        child: const Icon(
                          CupertinoIcons.chevron_back,
                          color: Colors.white,
                          semanticLabel: 'Close',
                        ),
                      ),
                    ),
                    trailing: onReadMode == null
                        ? null
                        : ReadModeButton(onPressed: onReadMode!),
                    middle: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          page,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The viewer bar's button for switching between Photos, Pages and Strip.
class ReadModeButton extends StatelessWidget {
  const ReadModeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ViewerGlass(
    shape: const CircleBorder(),
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: const Icon(
        CupertinoIcons.book,
        color: Colors.white,
        semanticLabel: 'Read as',
      ),
    ),
  );
}
