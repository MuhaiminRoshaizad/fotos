import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/theme/app_tokens.dart';
import 'viewer_glass.dart';

/// An album read as one long strip: every page full width, top to bottom,
/// with no gaps, the way long-strip comics are drawn. Each page takes its
/// real height from the start, so nothing shifts as the pictures arrive. A
/// tap shows or hides the bar.
class StripViewer extends StatefulWidget {
  const StripViewer({
    super.key,
    required this.title,
    required this.items,
    required this.index,
  });

  final String title;
  final List<AssetEntity> items;

  /// The page to open at.
  final int index;

  @override
  State<StripViewer> createState() => _StripViewerState();
}

class _StripViewerState extends State<StripViewer> {
  ScrollController? _scroll;
  bool _chrome = true;
  late int _page = widget.index;

  /// Where each page starts, at the current width, plus the strip's end.
  List<double> _tops = const <double>[];
  double _width = 0;

  static double _aspect(AssetEntity e) {
    final Size s = e.orientatedSize;
    // An item whose size Android doesn't know reads as a comic page.
    return s.width > 0 && s.height > 0 ? s.width / s.height : 0.7;
  }

  void _layout(double width) {
    if (width == _width) return;
    _width = width;
    double y = 0;
    final List<double> tops = <double>[];
    for (final AssetEntity e in widget.items) {
      tops.add(y);
      y += width / _aspect(e);
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

  /// The page under the middle of the screen.
  void _track() {
    final ScrollController? s = _scroll;
    if (s == null || !s.hasClients || _tops.length < 2) return;
    final double mid = s.offset + s.position.viewportDimension / 2;
    int lo = 0;
    int hi = widget.items.length - 1;
    while (lo < hi) {
      final int m = (lo + hi + 1) ~/ 2;
      if (_tops[m] <= mid) {
        lo = m;
      } else {
        hi = m - 1;
      }
    }
    if (lo != _page) setState(() => _page = lo);
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
          // many pages in memory at once.
          final int px = math.min((c.maxWidth * dpr).round(), 1440);
          return Stack(
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: widget.items.length,
                  itemExtentBuilder: (int i, _) => _tops[i + 1] - _tops[i],
                  itemBuilder: (BuildContext context, int i) {
                    final AssetEntity e = widget.items[i];
                    final int h = (px / _aspect(e)).round();
                    return Semantics(
                      image: true,
                      label: 'Page ${i + 1} of ${widget.items.length}',
                      child: ColoredBox(
                        color: const Color(0xFF151517),
                        child: Image(
                          image: AssetEntityImageProvider(
                            e,
                            isOriginal: false,
                            thumbnailSize: ThumbnailSize(px, h),
                          ),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
              _StripBar(
                visible: _chrome,
                title: widget.title,
                page: '${_page + 1} of ${widget.items.length}',
                onClose: () => Navigator.of(context).pop(),
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
  });

  final bool visible;
  final String title;
  final String page;
  final VoidCallback onClose;

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
