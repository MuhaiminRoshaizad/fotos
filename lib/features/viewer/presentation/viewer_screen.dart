import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../video_editor/presentation/save_ring.dart';
import '../../../core/format/formatters.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/add_to_album.dart';
import '../../../core/media/animated.dart';
import '../../../core/media/media_actions.dart';
import '../../../core/media/media_flight.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/toast.dart';
import '../../../core/media/read_mode.dart';
import '../../video_editor/presentation/video_editor_screen.dart';
import 'details_sheet.dart';
import 'video_page.dart';
import 'motion_photo.dart';
import 'strip_viewer.dart';
import '../../../core/widgets/viewer_glass.dart';
import '../../../core/widgets/viewer_top_bar.dart';
import 'viewer_metrics.dart';

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
    this.onShow,
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

  /// Told each item the viewer comes to, so the grid it was opened from can
  /// keep that item's tile in view and the viewer closes back into it.
  final ValueChanged<AssetEntity>? onShow;
}

/// Whether the viewer's page view may take a drag made with [fingers]
/// fingers.
///
/// Two fingers are a pinch, never a page turn: left to itself the page view
/// only stands aside when the fingers move apart on its axis, so a pinch
/// with one finger held still turned the page.
///
/// Nor may it take a drag while a video is zoomed in, so that the finger
/// pans the video. The page view asks extended_image's own zoom whether a
/// drag is a page turn (gesture_page_view.dart, canHorizontalOrVerticalDrag),
/// which a video zoomed by ZoomView never sets; canScrollPage only stops the
/// page moving, so the page view still won every sideways drag and dropped
/// it, and the video could not pan sideways or diagonally.
bool pageMayTakeDrag(int fingers, {required bool videoZoomed}) =>
    fingers == 1 && !videoZoomed;

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

  String? _shown;

  /// Tells [ViewerArgs.onShow] once about each item come to, however it
  /// was reached (a swipe, the filmstrip, a delete, the strip). After the
  /// frame: the grid scrolls in its own layout, not in the middle of ours.
  void _show(AssetEntity e) {
    final ValueChanged<AssetEntity>? onShow = widget.args.onShow;
    if (onShow == null || e.id == _shown) return;
    _shown = e.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => onShow(e));
  }

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

  /// A video pinched in: the pages hold still so a finger pans it.
  bool _videoZoomed = false;

  /// While the editor is open its own player plays, and this one waits.
  bool _editing = false;

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

  /// Opens the video editor; a saved edit takes the original's place in the
  /// viewer when it replaced it, or comes next to it as a copy.
  Future<void> _edit() async {
    final AssetEntity e = _current;
    setState(() => _editing = true);
    final EditOutcome? out = await Navigator.of(context).push<EditOutcome>(
      CupertinoPageRoute<EditOutcome>(
        fullscreenDialog: true,
        builder: (_) => VideoEditorScreen(asset: e),
      ),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (out == null) return;
    ref
      ..invalidate(libraryProvider)
      ..invalidate(albumsProvider)
      ..invalidate(favouritesProvider);
    // Android can be slow to list a new file; the save stands, and the
    // library shows it once listed.
    final AssetEntity? saved = out.saved.id.isEmpty
        ? null
        : await AssetEntity.fromId(out.saved.id);
    if (!mounted) return;
    if (saved == null) {
      showToast(context, 'Saved as ${out.saved.name}');
      return;
    }
    final int at = _items.indexWhere((AssetEntity x) => x.id == e.id);
    if (at < 0) return;
    setState(() {
      if (out.saved.replaced) {
        _items[at] = saved;
      } else {
        _items.insert(at + 1, saved);
      }
    });
    if (out.saved.replaced) {
      showToast(context, 'Replaced with the edited video');
    } else {
      showToast(
        context,
        out.askedToReplace
            ? 'Original kept. Saved as ${out.saved.name}'
            : 'Saved as ${out.saved.name}',
        actionLabel: 'View',
        onAction: () {
          final int i = _items.indexWhere((AssetEntity x) => x.id == saved.id);
          if (i >= 0 && mounted) _showAt(i);
        },
      );
    }
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
    if (opensAsStrip(_mode, _current)) {
      final List<AssetEntity> pictures = <AssetEntity>[
        for (final AssetEntity e in _items)
          if (e.type != AssetType.video) e,
      ];
      final int at = pictures.indexOf(_current);
      _show(at < 0 ? _current : pictures[at]);
      return StripViewer(
        title: widget.args.title,
        pages: <StripPage>[
          for (final AssetEntity e in pictures) StripPage.asset(e),
        ],
        index: at < 0 ? 0 : at,
        onPage: (int page) => _show(pictures[page]),
        onReadMode: (int page) {
          // Back in Photos or Pages, carry on from the page on screen.
          _showAt(_items.indexOf(pictures[page]));
          _chooseReadMode();
        },
      );
    }
    final AssetEntity e = _current;
    _show(e);
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
                  // A pinched-in video pans instead of turning the page.
                  canScrollPage: (_) => !_videoZoomed,
                  shouldAccpetHorizontalOrVerticalDrag:
                      (Map<int, VelocityTracker> fingers) => pageMayTakeDrag(
                        fingers.length,
                        videoZoomed: _videoZoomed,
                      ),
                  onPageChanged: (int i) {
                    _videoZoomed = false;
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
                          active: i == _index && !_editing,
                          chrome: _chrome,
                          onTap: () => _setChrome(!_chrome),
                          onZoomed: (bool z) =>
                              setState(() => _videoZoomed = z),
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
            ViewerTopBar(
              visible: _chrome,
              status: SaveRing(flies: _chrome),
              title: Fmt.date(e.createDateTime),
              subtitle: Fmt.time(e.createDateTime),
              onClose: () => Navigator.of(context).pop(),
              // Pages and Strip are ways to read pictures, not videos.
              trailing: widget.args.folder == null || e.type == AssetType.video
                  ? null
                  : ReadModeButton(onPressed: _chooseReadMode),
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
                            onEdit: e.type == AssetType.video ? _edit : null,
                            onShare: () => ref.read(mediaActionsProvider).share(
                              context,
                              <AssetEntity>[e],
                            ),
                            onAddToAlbum: () =>
                                addToAlbum(context, ref, <AssetEntity>[e]),
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
      height: ViewerMetrics.stripHeight,
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

class _Actions extends StatelessWidget {
  const _Actions({
    required this.favourite,
    required this.onEdit,
    required this.onShare,
    required this.onAddToAlbum,
    required this.onFavourite,
    required this.onDetails,
    required this.onDelete,
  });

  final bool favourite;

  /// Null for a photo: only videos have the editor.
  final VoidCallback? onEdit;
  final VoidCallback onShare;
  final VoidCallback onAddToAlbum;
  final VoidCallback onFavourite;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Six buttons for a video: a little narrower, still a full touch target.
    final double width = onEdit == null ? 56 : 48;
    Widget action(IconData icon, String label, VoidCallback onTap) => Pressable(
      label: label,
      minSize: Size(width, ViewerMetrics.actionButtonHeight),
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
              action(
                CupertinoIcons.plus_rectangle_on_rectangle,
                'Add to album',
                onAddToAlbum,
              ),
              if (onEdit != null)
                action(CupertinoIcons.scissors, 'Edit', onEdit!),
              // The heart fills in place and swells once as it does.
              Pressable(
                label: favourite ? 'Remove from Favourites' : 'Favourite',
                minSize: Size(width, ViewerMetrics.actionButtonHeight),
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

/// Whether [item] opens in the strip reader for a folder read as [mode]. A
/// strip is pictures only: a video can't play as a still in it, so a video
/// opens in the viewer even in a folder read as a strip, rather than an
/// empty strip of none of its pictures.
bool opensAsStrip(ReadMode mode, AssetEntity item) =>
    mode == ReadMode.strip && item.type != AssetType.video;
