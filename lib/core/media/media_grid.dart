import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../haptics/app_haptics.dart';
import '../selection/selection.dart';
import '../theme/app_tokens.dart';
import 'date_scrubber.dart';
import 'grid_geometry.dart';
import 'grouping.dart';
import 'media_tile.dart';

class _TileTag {
  const _TileTag(this.index);
  final int index;
}

/// A grouped, zoomable media grid.
///
/// Tap opens an item. Long-press starts selecting (when [selectionActions] is
/// given) and dragging afterwards selects the whole range passed over. Two
/// fingers pinching step between [GridLevel]s; the item at the top stays in
/// place across the change.
class MediaGrid extends ConsumerStatefulWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.level,
    required this.heroPrefix,
    required this.onOpen,
    this.onLevelChanged,
    this.selectionOwner,
    this.selectionActions,
    this.grouped = true,
    this.header,
    this.overlayTop = 0,
  });

  final List<AssetEntity> items;
  final GridLevel level;
  final String heroPrefix;
  final void Function(int index) onOpen;
  final ValueChanged<GridLevel>? onLevelChanged;
  final String? selectionOwner;
  final List<SelectionAction> Function()? selectionActions;

  /// False for albums sorted by name or size, where date headings mislead.
  final bool grouped;

  /// Scrolls in above the first group (a large title). Its height is
  /// measured after layout so scroll offsets can be mapped past it.
  final Widget? header;

  /// Height of a bar floating over the grid's top edge; the scrubber and
  /// drag-select auto-scroll stay below it.
  final double overlayTop;

  @override
  ConsumerState<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends ConsumerState<MediaGrid> {
  ScrollController _scroll = ScrollController();
  double _headerExtent = 0;
  GridGeometry? _geometry;
  int? _anchorItem;

  // Drag-select.
  int? _dragAnchor;
  Set<String> _dragBase = <String>{};
  Timer? _autoScroll;
  Offset? _lastDragGlobal;

  // Pinch.
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _pinchStart;
  bool _pinchStepped = false;

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level && _geometry != null) {
      final double offset = _scroll.hasClients ? _scroll.offset : 0;
      _anchorItem = _geometry!.itemAt(_gridOffset(offset));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _autoScroll?.cancel();
    super.dispose();
  }

  /// A scroll offset measured from the first group instead of the header.
  double _gridOffset(double offset) =>
      (offset - _headerExtent).clamp(0, double.infinity).toDouble();

  List<MediaGroup<AssetEntity>> get _groups => widget.grouped
      ? groupByDate(
          widget.items,
          (AssetEntity e) => e.createDateTime,
          widget.level,
        )
      : <MediaGroup<AssetEntity>>[MediaGroup<AssetEntity>('', widget.items)];

  // ---- selection -----------------------------------------------------------

  bool get _canSelect =>
      widget.selectionOwner != null && widget.selectionActions != null;

  int? _indexAt(Offset global) {
    final BoxHitTestResult result = BoxHitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final HitTestEntry<HitTestTarget> e in result.path) {
      final HitTestTarget t = e.target;
      if (t is RenderMetaData && t.metaData is _TileTag) {
        return (t.metaData as _TileTag).index;
      }
    }
    return null;
  }

  void _onLongPressStart(int index, LongPressStartDetails d) {
    if (!_canSelect) return;
    final SelectionNotifier sel = ref.read(selectionProvider.notifier);
    final SelectionState state = ref.read(selectionProvider);
    final String id = widget.items[index].id;
    if (!state.isActiveFor(widget.selectionOwner!)) {
      sel.start(widget.selectionOwner!, widget.selectionActions!());
    }
    _dragBase = Set<String>.of(ref.read(selectionProvider).ids)..add(id);
    _dragAnchor = index;
    sel.setIds(_dragBase);
    AppHaptics.longPress();
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (_dragAnchor == null) return;
    _lastDragGlobal = d.globalPosition;
    _selectTo(d.globalPosition);
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _edgeScroll(),
    );
  }

  void _selectTo(Offset global) {
    final int? i = _indexAt(global);
    if (i == null || _dragAnchor == null) return;
    final int a = i < _dragAnchor! ? i : _dragAnchor!;
    final int b = i < _dragAnchor! ? _dragAnchor! : i;
    final Set<String> next = Set<String>.of(_dragBase);
    for (int k = a; k <= b; k++) {
      next.add(widget.items[k].id);
    }
    final int before = ref.read(selectionProvider).ids.length;
    if (next.length != before) {
      ref.read(selectionProvider.notifier).setIds(next);
      if (next.length > before) AppHaptics.tick();
    }
  }

  void _edgeScroll() {
    final Offset? g = _lastDragGlobal;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (g == null || box == null || !_scroll.hasClients) return;
    final double y = box.globalToLocal(g).dy;
    const double zone = 80;
    double delta = 0;
    final double top = widget.overlayTop;
    if (y < top + zone) delta = -(top + zone - y) / 4;
    if (y > box.size.height - zone - AppNavMetrics.height) {
      delta = (y - (box.size.height - zone - AppNavMetrics.height)) / 4;
    }
    if (delta == 0) return;
    final ScrollPosition p = _scroll.position;
    _scroll.jumpTo(
      (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent),
    );
    _selectTo(g);
  }

  void _onLongPressEnd() {
    _dragAnchor = null;
    _autoScroll?.cancel();
    _autoScroll = null;
    _lastDragGlobal = null;
  }

  void _onTap(int index) {
    final SelectionState state = ref.read(selectionProvider);
    if (_canSelect && state.isActiveFor(widget.selectionOwner!)) {
      final SelectionNotifier sel = ref.read(selectionProvider.notifier);
      sel.toggle(widget.items[index].id);
      return;
    }
    widget.onOpen(index);
  }

  // ---- pinch ---------------------------------------------------------------

  double? _spread() {
    if (_pointers.length < 2) return null;
    final List<Offset> p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStart = _spread();
      _pinchStepped = false;
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final double? now = _spread();
    if (now == null || _pinchStart == null || _pinchStepped) return;
    if (widget.onLevelChanged == null) return;
    final double ratio = now / _pinchStart!;
    int delta = 0;
    if (ratio > 1.3) delta = 1;
    if (ratio < 0.77) delta = -1;
    if (delta == 0) return;
    final GridLevel next = widget.level.step(delta);
    _pinchStepped = true;
    if (next != widget.level) {
      AppHaptics.tick();
      widget.onLevelChanged!(next);
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final SelectionState sel = ref.watch(selectionProvider);
    final bool selecting =
        widget.selectionOwner != null &&
        sel.isActiveFor(widget.selectionOwner!);
    final List<MediaGroup<AssetEntity>> groups = _groups;
    final double bottom = AppNavMetrics.clearance(
      MediaQuery.paddingOf(context).bottom,
    );
    final TextScaler headingScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: 1.4);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final int columns = widget.level.columnsFor(c.maxWidth);
        final GridGeometry geo = GridGeometry(
          width: c.maxWidth,
          columns: columns,
          groupSizes: <int>[
            for (final MediaGroup<AssetEntity> g in groups) g.items.length,
          ],
          headerExtent: widget.grouped ? 44 : 0,
        );
        _geometry = geo;
        if (_anchorItem != null) {
          final double target =
              geo.offsetOf(_anchorItem!) +
              (_anchorItem! == 0 ? 0 : _headerExtent);
          _anchorItem = null;
          // The outgoing grid still animates out on the old controller, so it
          // is disposed only after the switch finishes.
          final ScrollController old = _scroll;
          _scroll = ScrollController(initialScrollOffset: target);
          Future<void>.delayed(AppMotion.long, old.dispose);
        }

        int flat = 0;
        final List<Widget> slivers = <Widget>[
          if (widget.header != null)
            SliverToBoxAdapter(
              child: _MeasureHeight(
                onHeight: (double h) => _headerExtent = h,
                child: widget.header!,
              ),
            ),
        ];
        for (final MediaGroup<AssetEntity> g in groups) {
          final int start = flat;
          if (widget.grouped) {
            slivers.add(
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      g.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: headingScaler,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          slivers.add(
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: g.items.length,
              itemBuilder: (BuildContext context, int i) {
                final int index = start + i;
                final AssetEntity e = g.items[i];
                return MetaData(
                  metaData: _TileTag(index),
                  behavior: HitTestBehavior.opaque,
                  child: GestureDetector(
                    onTap: () => _onTap(index),
                    onLongPressStart: _canSelect
                        ? (LongPressStartDetails d) =>
                              _onLongPressStart(index, d)
                        : null,
                    onLongPressMoveUpdate: _canSelect ? _onLongPressMove : null,
                    onLongPressEnd: _canSelect
                        ? (_) => _onLongPressEnd()
                        : null,
                    onLongPressCancel: _canSelect ? _onLongPressEnd : null,
                    child: MediaTile(
                      key: ValueKey<String>(e.id),
                      asset: e,
                      heroTag: '${widget.heroPrefix}-${e.id}',
                      selecting: selecting,
                      selected: selecting && sel.ids.contains(e.id),
                    ),
                  ),
                );
              },
            ),
          );
          flat += g.items.length;
        }
        slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottom)));

        final Widget scroll = CustomScrollView(
          key: ValueKey<GridLevel>(widget.level),
          controller: _scroll,
          slivers: slivers,
        );

        return Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.decelerate,
                  switchOutCurve: AppMotion.accelerate,
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      FadeTransition(
                        opacity: a,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1).animate(a),
                          child: child,
                        ),
                      ),
                  child: scroll,
                ),
              ),
              if (widget.grouped)
                Positioned(
                  top: widget.overlayTop,
                  right: 0,
                  bottom: bottom - AppSpacing.lg,
                  child: DateScrubber(
                    controller: _scroll,
                    labelAt: (double offset) => groups.isEmpty
                        ? ''
                        : groups[geo.groupAt(_gridOffset(offset))].label,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Reports its child's height after each layout, without rebuilding anything.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, required Widget super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}
