import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart'
    show HitTestEntry, HitTestResult, HitTestTarget;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/natural_sort.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/media/add_to_album.dart';
import '../../../core/media/empty_albums.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/selection/selection.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/bottom_bar_space.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/search_field.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'album_selection.dart';
import 'album_tiles.dart';
import 'albums_providers.dart';
import 'gallery_sheets.dart';

/// The Albums tab: pinned albums and galleries first, then galleries and
/// every folder holding media that is not in a gallery, then Favourites,
/// Recently deleted and the Takeout import as grouped rows.
class AlbumsScreen extends ConsumerWidget {
  const AlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SelectionState sel = ref.watch(selectionProvider);
    final SelectionNotifier selection = ref.read(selectionProvider.notifier);
    final bool selecting = sel.isActiveFor(albumsSelectionOwner);
    final int n = sel.ids.length;
    final bool any =
        (ref.watch(albumsProvider).value?.isNotEmpty ?? false) ||
        (ref.watch(galleriesProvider).value?.isNotEmpty ?? false);
    return LargeTitleScaffold(
      title: 'Albums',
      grouped: true,
      barTitle: selecting ? (n == 0 ? 'Select albums' : '$n selected') : null,
      leading: selecting
          ? BarButton.text(
              label: 'Select all',
              onPressed: () => selection.setIds(selectableAlbumIds(ref)),
            )
          : null,
      trailing: selecting
          ? <Widget>[
              BarButton.text(
                label: 'Done',
                prominent: true,
                onPressed: selection.clear,
              ),
            ]
          : <Widget>[
              BarButton.text(
                label: 'Select',
                onPressed: any ? () => startAlbumSelection(ref) : null,
              ),
              BarButton.icon(
                icon: CupertinoIcons.ellipsis,
                tooltip: 'More',
                onPressed: () => showAlbumsMenu(context, ref),
              ),
            ],
      body: (BuildContext context, Widget header) => MediaAccessGate(
        header: header,
        builder: (Widget h) => _AlbumsBody(header: h),
      ),
    );
  }
}

class _AlbumsBody extends ConsumerStatefulWidget {
  const _AlbumsBody({required this.header});

  final Widget header;

  @override
  ConsumerState<_AlbumsBody> createState() => _AlbumsBodyState();
}

class _AlbumsBodyState extends ConsumerState<_AlbumsBody> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- hold and drag across tiles while selecting -------------------------

  /// The selectable tiles in the order they are laid out.
  List<String> _order = const <String>[];
  String? _anchor;
  bool _sweepTo = true;
  Set<String> _base = const <String>{};
  int _swept = 0;

  String? _idAt(Offset global) {
    final HitTestResult result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      global,
      View.of(context).viewId,
    );
    for (final HitTestEntry<HitTestTarget> e in result.path) {
      final HitTestTarget t = e.target;
      if (t is RenderMetaData && t.metaData is AlbumTag) {
        return (t.metaData as AlbumTag).id;
      }
    }
    return null;
  }

  void _sweepStart(LongPressStartDetails d) {
    final String? id = _idAt(d.globalPosition);
    if (id == null) return;
    _anchor = id;
    _base = Set<String>.of(ref.read(selectionProvider).ids);
    // Starting on a selected tile takes tiles out; otherwise puts them in.
    _sweepTo = !_base.contains(id);
    _swept = 0;
    _sweepOver(id);
  }

  void _sweepMove(LongPressMoveUpdateDetails d) {
    if (_anchor == null) return;
    final String? id = _idAt(d.globalPosition);
    if (id != null) _sweepOver(id);
  }

  /// Sets every tile between the one the sweep began on and [id], so a
  /// quick drag can't skip the tiles it passed.
  void _sweepOver(String id) {
    final int a = _order.indexOf(_anchor!);
    final int b = _order.indexOf(id);
    if (a < 0 || b < 0) return;
    final List<String> range = _order.sublist(
      a < b ? a : b,
      (a < b ? b : a) + 1,
    );
    if (range.length != _swept) {
      _swept = range.length;
      AppHaptics.tick();
    }
    ref
        .read(selectionProvider.notifier)
        .setIds(
          _sweepTo
              ? <String>{..._base, ...range}
              : (Set<String>.of(_base)..removeAll(range)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final Widget header = widget.header;
    final String q = _query.text.trim().toLowerCase();
    bool matches(String name) => q.isEmpty || name.toLowerCase().contains(q);
    final AsyncValue<List<Album>> albums = ref.watch(albumsProvider);
    final AlbumPrefs prefs =
        ref.watch(albumPrefsProvider).value ?? const AlbumPrefs();
    final List<String> empty =
        ref.watch(emptyAlbumsProvider).value ?? const <String>[];
    // The page does not resize for the keyboard, so the list makes room.
    final double bottom =
        bottomClearance(context) + MediaQuery.viewInsetsOf(context).bottom;
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return albums.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => headed(const _AlbumsSkeleton()),
      error: (_, _) => headed(
        EmptyState(
          icon: CupertinoIcons.exclamationmark_circle,
          title: 'Couldn\'t load your albums',
          message: 'Something went wrong reading the photo library.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(albumsProvider),
        ),
      ),
      data: (List<Album> list) {
        final List<Gallery> galleries =
            ref.watch(galleriesProvider).value ?? const <Gallery>[];
        // Albums in a gallery are shown inside it; a search still finds them.
        final Set<String> grouped = <String>{
          for (final Gallery g in galleries) ...g.albumIds,
        };
        List<Album> inside(Gallery g) => g.order.apply(<Album>[
          for (final Album a in list)
            if (g.albumIds.contains(a.id)) a,
        ]);
        final List<Widget> pinned = <Widget>[
          for (final String id in prefs.pinned) ...<Widget>[
            for (final Gallery g in galleries)
              if (g.id == id && matches(g.name))
                GalleryTile(
                  key: ValueKey<String>(g.id),
                  gallery: g,
                  albums: inside(g),
                  onSelect: () => startAlbumSelection(ref, first: g.id),
                ),
            for (final Album a in list)
              if (a.id == id && matches(a.name))
                AlbumTile(
                  key: ValueKey<String>(a.id),
                  album: a,
                  onSelect: () => startAlbumSelection(ref, first: a.id),
                ),
          ],
        ];
        final List<Gallery> restGalleries =
            galleries
                .where(
                  (Gallery g) =>
                      !prefs.pinned.contains(g.id) && matches(g.name),
                )
                .toList()
              ..sort((Gallery a, Gallery b) => naturalCompare(a.name, b.name));
        final List<Album> rest = prefs.order.apply(
          list
              .where(
                (Album a) =>
                    !prefs.pinned.contains(a.id) &&
                    matches(a.name) &&
                    (q.isNotEmpty || !grouped.contains(a.id)),
              )
              .toList(),
        );
        final List<String> allPending = pendingEmptyAlbums(empty, list);
        final List<String> pending = allPending.where(matches).toList();
        if (allPending.length != empty.length) {
          // An empty album that now holds something is a real folder; forget
          // the placeholder so deleting that folder later doesn't revive it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final String n in empty.where(
              (String n) => !allPending.contains(n),
            )) {
              ref.read(emptyAlbumsProvider.notifier).remove(n);
            }
          });
        }
        final int favourites = ref.watch(favouritesProvider).value?.length ?? 0;
        final int trashed = ref.watch(trashProvider).value?.length ?? 0;
        final bool nothing =
            pinned.isEmpty &&
            restGalleries.isEmpty &&
            rest.isEmpty &&
            pending.isEmpty;
        _order = <String>[
          for (final String id in prefs.pinned)
            if (galleries.any((Gallery g) => g.id == id && matches(g.name)) ||
                list.any((Album a) => a.id == id && matches(a.name)))
              id,
          for (final Gallery g in restGalleries) g.id,
          for (final Album a in rest) a.id,
        ];
        final bool selecting = ref
            .watch(selectionProvider)
            .isActiveFor(albumsSelectionOwner);
        final Widget scroll = CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: <Widget>[
            SliverToBoxAdapter(child: header),
            if (list.isNotEmpty || allPending.isNotEmpty)
              SliverToBoxAdapter(
                child: SearchField(
                  controller: _query,
                  focus: _focus,
                  active: _focus.hasFocus || _query.text.isNotEmpty,
                  placeholder: 'Search albums',
                ),
              ),
            if (q.isNotEmpty && nothing)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'No album is called “${_query.text.trim()}”.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (pinned.isNotEmpty) ...<Widget>[
              const SliverToBoxAdapter(child: GroupHeading('Pinned')),
              AlbumGrid(tiles: pinned),
            ],
            if (q.isEmpty ||
                !nothing &&
                    (restGalleries.isNotEmpty ||
                        rest.isNotEmpty ||
                        pending.isNotEmpty))
              const SliverToBoxAdapter(child: GroupHeading('On this phone')),
            if (q.isNotEmpty &&
                restGalleries.isEmpty &&
                rest.isEmpty &&
                pending.isEmpty)
              const SliverToBoxAdapter(child: SizedBox.shrink())
            else if (list.isEmpty && pending.isEmpty && galleries.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text('No folders with photos or videos yet.'),
                ),
              )
            else
              AlbumGrid(
                tiles: <Widget>[
                  for (final Gallery g in restGalleries)
                    GalleryTile(
                      key: ValueKey<String>(g.id),
                      gallery: g,
                      albums: inside(g),
                      onSelect: () => startAlbumSelection(ref, first: g.id),
                    ),
                  for (final String n in pending)
                    EmptyAlbumTile(key: ValueKey<String>('empty:$n'), name: n),
                  for (final Album a in rest)
                    AlbumTile(
                      key: ValueKey<String>(a.id),
                      album: a,
                      onSelect: () => startAlbumSelection(ref, first: a.id),
                    ),
                ],
              ),
            if (q.isEmpty)
              SliverToBoxAdapter(
                child: InsetGroup(
                  header: 'Library',
                  children: <Widget>[
                    GroupRow(
                      leading: const Icon(CupertinoIcons.heart),
                      title: 'Favourites',
                      value: favourites == 0 ? null : '$favourites',
                      onTap: () => context.push('/albums/favourites'),
                    ),
                    GroupRow(
                      leading: const Icon(CupertinoIcons.trash),
                      title: 'Recently deleted',
                      value: trashed == 0 ? null : '$trashed',
                      onTap: () => context.push('/albums/trash'),
                    ),
                  ],
                ),
              ),
            if (q.isEmpty)
              SliverToBoxAdapter(
                child: InsetGroup(
                  header: 'Bring photos home',
                  footer:
                      'Pick the ZIPs from your Takeout export. Locked Folder '
                      'items are skipped and counted.',
                  children: <Widget>[
                    GroupRow(
                      leading: const Icon(CupertinoIcons.arrow_down_circle),
                      title: 'Import from Google Takeout',
                      onTap: () => context.push('/albums/takeout'),
                    ),
                  ],
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        );
        // Always present, so starting to select doesn't rebuild every tile
        // under a new parent.
        return GestureDetector(
          onLongPressStart: selecting ? _sweepStart : null,
          onLongPressMoveUpdate: selecting ? _sweepMove : null,
          onLongPressEnd: selecting ? (_) => _anchor = null : null,
          child: scroll,
        );
      },
    );
  }
}

class _AlbumsSkeleton extends StatelessWidget {
  const _AlbumsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SearchFieldPlaceholder(),
        Expanded(
          // Where the grid starts under the "On this phone" heading.
          child: AlbumGridSkeleton(top: AppSpacing.xl + 24 + AppSpacing.sm),
        ),
      ],
    );
  }
}
