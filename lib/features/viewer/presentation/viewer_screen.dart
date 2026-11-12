import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/animated.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_flight.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/media/read_mode.dart';
import 'details_sheet.dart';
import 'video_page.dart';
import 'motion_photo.dart';
import 'strip_viewer.dart';
import 'viewer_glass.dart';

/// What the viewer opens with: the list it pages through, where to start,
/// and the hero tag prefix of the grid it came from.
class ViewerArgs {
  const ViewerArgs({
    required this.items,
    required this.index,
    required this.heroPrefix,
    this.library,
    this.folder,
    this.title = '',
  });

  final List<AssetEntity> items;
  final int index;
  final String heroPrefix;

  /// The whole list to page through, still loading. The viewer shows
  /// [items] at once and takes this in when it lands, staying on the same
  /// photo: opening one photo from the widget or the camera need not wait
  /// for the library.
  final Future<List<AssetEntity>>? library;

  /// The folder these come from, as a [readingKey], which decides how they
  /// are read and lets the bar switch it; null for a mixed view such as
  /// the Photos tab, read as photos.
  final String? folder;

  /// The album's name, shown by the strip.
  final String title;
}

/// Full-screen photo and video viewer. Swipe sideways to page, down to close,
/// up for details; pinch or double-tap to zoom; tap to show or hide controls.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.args});

  final ViewerArgs args;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  final GlobalKey<ExtendedImageSlidePageState> _slideKey =
      GlobalKey<ExtendedImageSlidePageState>();
  late final List<AssetEntity> _items = List<AssetEntity>.of(widget.args.items);
  late int _index = widget.args.index;
  late ExtendedPageController _pages = _pagesAt(_index);

  /// Bumped when the list is swapped, so the pages are built afresh at the
  /// new position instead of showing the new list's first item for a frame.
  int _generation = 0;

  static ExtendedPageController _pagesAt(int i) =>
      ExtendedPageController(initialPage: i, pageSpacing: 16);
  final ScrollController _strip = ScrollController();
  bool _chrome = true;
  bool _passedThreshold = false;

  /// True while a finger (or its fling) is scrubbing the filmstrip: the strip
  /// then chooses the photo, not the other way round.
  bool _scrubbing = false;
  Timer? _scrubJump;

  AssetEntity get _current => _items[_index];
  String _hero(AssetEntity e) => '${widget.args.heroPrefix}-${e.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centreStrip(false));
    widget.args.library?.then(
      _takeLibrary,
      onError: (Object _) {
        // Paging stays limited to what the viewer opened with.
      },
    );
  }

  /// Moves to [at], building the pages afresh there.
  void _showAt(int at) {
    if (at == _index) return;
    final ExtendedPageController old = _pages;
    setState(() {
      _index = at;
      _pages = _pagesAt(at);
      _generation++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (mounted) _centreStrip(false);
    });
  }

  ReadMode get _mode =>
      readModeFor(ref.watch(readModesProvider).value, widget.args.folder);

  Future<void> _chooseReadMode() async {
    final String? folder = widget.args.folder;
    if (folder == null) return;
    final ReadMode now = readModeFor(ref.read(readModesProvider).value, folder);
    final ReadMode? next = await chooseReadMode(context, now);
    if (next == null || next == now) return;
    await ref.read(readModesProvider.notifier).set(folder, next);
  }

  void _takeLibrary(List<AssetEntity> all) {
    if (!mounted) return;
    final String id = _current.id;
    final int at = all.indexWhere((AssetEntity e) => e.id == id);
    if (at < 0) return;
    final ExtendedPageController old = _pages;
    setState(() {
      _items
        ..clear()
        ..addAll(all);
      _index = at;
      _pages = _pagesAt(at);
      _generation++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (mounted) _centreStrip(false);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrubJump?.cancel();
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _setChrome(bool on) {
    setState(() => _chrome = on);
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  static const double _thumbW = 36;
  static const double _thumbGap = 2;

  void _centreStrip(bool animate) {
    if (!_strip.hasClients) return;
    final double target = (_index * (_thumbW + _thumbGap)).clamp(
      0,
      _strip.position.maxScrollExtent,
    );
    animate
        ? _strip.animateTo(
            target,
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
          )
        : _strip.jumpTo(target);
  }

  /// The filmstrip moved under the fixed centre frame: whichever thumbnail
  /// sits there becomes the current item. The big photo follows at most
  /// every 60 ms, so a fast fling doesn't decode every photo it passes.
  bool _onStripScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _scrubbing = true;
    } else if (n is ScrollUpdateNotification && _scrubbing) {
      final int i = (n.metrics.pixels / (_thumbW + _thumbGap)).round().clamp(
        0,
        _items.length - 1,
      );
      if (i != _index) {
        setState(() => _index = i);
        AppHaptics.tick();
        _scrubJump ??= Timer(const Duration(milliseconds: 60), () {
          _scrubJump = null;
          if (mounted) _pages.jumpToPage(_index);
        });
      }
    } else if (n is ScrollEndNotification && _scrubbing) {
      _scrubbing = false;
      _scrubJump?.cancel();
      _scrubJump = null;
      // Settle the chosen thumbnail exactly under the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pages.jumpToPage(_index);
        _centreStrip(true);
      });
    }
    return false;
  }

  Future<void> _toggleFavourite() async {
    final AssetEntity e = _current;
    final bool ok = await ref.read(mediaActionsProvider).setFavourite(
      context,
      <AssetEntity>[e],
      !e.isFavorite,
    );
    if (!ok || !mounted) return;
    setState(() => _items[_index] = e.copyWith(isFavorite: !e.isFavorite));
  }

  Future<void> _delete() async {
    final Set<String> gone = await ref.read(mediaActionsProvider).trash(
      context,
      <AssetEntity>[_current],
    );
    if (gone.isEmpty || !mounted) return;
    if (_items.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
  }

  void _details() {
    showAppSheet<void>(
      context,
      scrollControlled: true,
      builder: (_) => DetailsSheet(asset: _current),
    );
  }

  /// The viewer's end of the flight from and back to the grid tile.
  Widget _flying(AssetEntity e, Widget child) => Hero(
    tag: _hero(e),
    createRectTween: mediaFlightTween,
    flightShuttleBuilder: mediaFlightShuttle(e),
    child: child,
  );

  Widget _photo(AssetEntity e, int i) {
    return ExtendedImage(
      // A moving page plays from its original file; a still preview would
      // show only its first frame.
      image: mayAnimate(e)
          ? AssetEntityImageProvider(e)
          : AssetEntityImageProvider(
              e,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize(2560, 2560),
            ),
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      enableSlideOutPage: true,
      gaplessPlayback: true,
      initGestureConfigHandler: (_) => GestureConfig(
        inPageView: true,
        minScale: 1,
        maxScale: 5,
        animationMaxScale: 6,
        initialScale: 1,
        cacheGesture: false,
      ),
      onDoubleTap: (ExtendedImageGestureState s) {
        final double scale = s.gestureDetails?.totalScale ?? 1;
        s.handleDoubleTap(
          scale: scale > 1.01 ? 1 : 2.6,
          doubleTapPosition: s.pointerDownPosition,
        );
        _setChrome(scale > 1.01);
      },
      heroBuilderForSlidingPage: (Widget child) => _flying(e, child),
      loadStateChanged: (ExtendedImageState s) {
        if (s.extendedImageLoadState == LoadState.loading) {
          // The grid thumbnail stands in until the large decode lands.
          return Image(
            image: AssetEntityImageProvider(
              e,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(384),
            ),
            fit: BoxFit.contain,
          );
        }
        if (s.extendedImageLoadState == LoadState.failed) {
          return const Center(
            child: Text(
              'This photo can\'t be shown.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        return null;
      },
    );
  }

  /// Pages mode: a tap on the left or right third turns the page, the
  /// middle third shows or hides the controls.
  void _tapAt(double dx) {
    final ReadMode mode = readModeFor(
      ref.read(readModesProvider).value,
      widget.args.folder,
    );
    if (mode != ReadMode.pages) return _setChrome(!_chrome);
    final double third = MediaQuery.sizeOf(context).width / 3;
    final int step = dx < third ? -1 : (dx > third * 2 ? 1 : 0);
    if (step == 0) return _setChrome(!_chrome);
    final int to = _index + step;
    if (to < 0 || to >= _items.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(to);
    } else {
      _pages.animateToPage(
        to,
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == ReadMode.strip) {
      // A strip is pictures only; a video can't play as a still in it.
      final List<AssetEntity> pictures = <AssetEntity>[
        for (final AssetEntity e in _items)
          if (e.type != AssetType.video) e,
      ];
      final int at = pictures.indexOf(_current);
      return StripViewer(
        title: widget.args.title,
        pages: <StripPage>[
          for (final AssetEntity e in pictures) StripPage.asset(e),
        ],
        index: at < 0 ? 0 : at,
        onReadMode: (int page) {
          // Back in Photos or Pages, carry on from the page on screen.
          _showAt(_items.indexOf(pictures[page]));
          _chooseReadMode();
        },
      );
    }
    final AssetEntity e = _current;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ExtendedImageSlidePage(
        key: _slideKey,
        slideAxis: SlideAxis.vertical,
        slideType: SlideType.onlyImage,
        slidePageBackgroundHandler: (Offset offset, Size size) {
          final double f = (offset.dy.abs() / (size.height / 2)).clamp(0, 1);
          return Colors.black.withValues(alpha: 1 - f);
        },
        onSlidingPage: (ExtendedImageSlidePageState s) {
          final bool past = s.offset.dy > 110;
          if (past != _passedThreshold) {
            _passedThreshold = past;
            AppHaptics.tick();
          }
          // An upward drag is held at zero, so it must not hide the bars.
          if (s.isSliding && s.offset.dy > 0 && _chrome) _setChrome(false);
        },
        slideEndHandler:
            (
              Offset offset, {
              ExtendedImageSlidePageState? state,
              ScaleEndDetails? details,
            }) {
              _passedThreshold = false;
              return offset.dy > 110;
            },
        // Only a downward drag moves the page. An upward one used to lift
        // and shrink it like a dismissal and then open Details on release,
        // which read as a cancelled swipe doing something unasked.
        slideOffsetHandler:
            (Offset offset, {ExtendedImageSlidePageState? state}) =>
                offset.dy < 0 ? Offset(offset.dx, 0) : null,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              // Same reason as in VideoPage: give page text a real style.
              child: Material(
                type: MaterialType.transparency,
                child: ExtendedImageGesturePageView.builder(
                  key: ValueKey<int>(_generation),
                  controller: _pages,
                  itemCount: _items.length,
                  onPageChanged: (int i) {
                    if (_scrubbing) return;
                    setState(() => _index = i);
                    _centreStrip(true);
                  },
                  itemBuilder: (BuildContext context, int i) {
                    final AssetEntity item = _items[i];
                    if (item.type == AssetType.video) {
                      return ExtendedImageSlidePageHandler(
                        extendedImageSlidePageState: _slideKey.currentState,
                        heroBuilderForSlidingPage: (Widget child) =>
                            _flying(item, child),
                        child: VideoPage(
                          key: ValueKey<String>(item.id),
                          asset: item,
                          active: i == _index,
                          chrome: _chrome,
                          onTap: () => _setChrome(!_chrome),
                        ),
                      );
                    }
                    return GestureDetector(
                      onTapUp: (TapUpDetails d) => _tapAt(d.globalPosition.dx),
                      child: MotionPhoto(
                        key: ValueKey<String>('motion-${item.id}'),
                        asset: item,
                        child: _photo(item, i),
                      ),
                    );
                  },
                ),
              ),
            ),
            _TopBar(
              visible: _chrome,
              date: e.createDateTime,
              onClose: () => Navigator.of(context).pop(),
              // Pages and Strip are ways to read pictures, not videos.
              onReadMode:
                  widget.args.folder == null || e.type == AssetType.video
                  ? null
                  : _chooseReadMode,
            ),
            Positioned(
              left: AppSpacing.lg,
              top: MediaQuery.paddingOf(context).top + 64,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: AppMotion.short,
                  child: MotionBadge(
                    key: ValueKey<String>('badge-${e.id}'),
                    asset: e,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: AppMotion.short,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x00000000), Color(0x99000000)],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // Under a video too, below its own scrubber, so the
                          // neighbours are one tap away as they are for photos.
                          _thumbStrip(),
                          _Actions(
                            favourite: e.isFavorite,
                            onShare: () => ref.read(mediaActionsProvider).share(
                              context,
                              <AssetEntity>[e],
                            ),
                            onFavourite: _toggleFavourite,
                            onDetails: _details,
                            onDelete: _delete,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbStrip() {
    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double side = c.maxWidth / 2 - _thumbW / 2;
          return NotificationListener<ScrollNotification>(
            onNotification: _onStripScroll,
            child: ListView.builder(
              controller: _strip,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: side),
              itemExtent: _thumbW + _thumbGap,
              itemCount: _items.length,
              itemBuilder: (BuildContext context, int i) {
                final bool on = i == _index;
                return Semantics(
                  button: true,
                  selected: on,
                  label: 'Item ${i + 1} of ${_items.length}',
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _index = i);
                      _pages.jumpToPage(i);
                      _centreStrip(true);
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: _thumbGap),
                      child: AnimatedContainer(
                        duration: AppMotion.short,
                        margin: EdgeInsets.symmetric(vertical: on ? 2 : 8),
                        decoration: BoxDecoration(
                          border: on
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Opacity(
                          opacity: on ? 1 : 0.6,
                          child: Image(
                            image: AssetEntityImageProvider(
                              _items[i],
                              isOriginal: false,
                              thumbnailSize: const ThumbnailSize.square(160),
                            ),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visible,
    required this.date,
    required this.onClose,
    required this.onReadMode,
  });

  final bool visible;
  final DateTime date;
  final VoidCallback onClose;

  /// Switches between Photos, Pages and Strip; no button when null.
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
                // NavigationToolbar fills whatever height it is given, so the
                // bar needs its own or it covers the whole photo.
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
                          Fmt.date(date),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          Fmt.time(date),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
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

class _Actions extends StatelessWidget {
  const _Actions({
    required this.favourite,
    required this.onShare,
    required this.onFavourite,
    required this.onDetails,
    required this.onDelete,
  });

  final bool favourite;
  final VoidCallback onShare;
  final VoidCallback onFavourite;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label, VoidCallback onTap) => Pressable(
      label: label,
      minSize: const Size(56, 48),
      onTap: onTap,
      child: Icon(icon, color: Colors.white),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: ViewerGlass(
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              action(CupertinoIcons.square_arrow_up, 'Share', onShare),
              // The heart fills in place and swells once as it does.
              Pressable(
                label: favourite ? 'Remove from Favourites' : 'Favourite',
                minSize: const Size(56, 48),
                onTap: onFavourite,
                child: Pop(
                  on: favourite,
                  child: GlyphSwap(
                    icon: favourite
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    color: Colors.white,
                  ),
                ),
              ),
              action(CupertinoIcons.info_circle, 'Details', onDetails),
              action(CupertinoIcons.trash, 'Delete', onDelete),
            ],
          ),
        ),
      ),
    );
  }
}
