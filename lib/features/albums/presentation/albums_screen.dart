import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/add_to_album.dart';
import '../../../core/media/empty_albums.dart';
import '../../../core/media/media_access_gate.dart';
import '../../../core/media/media_providers.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/inset_group.dart';
import '../../../core/widgets/large_title_scaffold.dart';
import '../../../core/widgets/search_field.dart';
import '../data/album_prefs.dart';
import '../data/galleries.dart';
import 'album_sheets.dart';
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
    return LargeTitleScaffold(
      title: 'Albums',
      grouped: true,
      trailing: <Widget>[
        BarButton.icon(
          icon: CupertinoIcons.arrow_up_arrow_down,
          tooltip: 'Sort albums',
          onPressed: () => showAlbumsOrderSheet(context, ref),
        ),
        BarButton.icon(
          icon: CupertinoIcons.plus,
          tooltip: 'New album or gallery',
          onPressed: () => showNewMenu(context, ref),
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
        AppNavMetrics.clearance(MediaQuery.paddingOf(context).bottom) +
        MediaQuery.viewInsetsOf(context).bottom;
    Widget headed(Widget state) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        Expanded(child: state),
      ],
    );
    return albums.when(
      skipLoadingOnRefresh: true,
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
                ),
            for (final Album a in list)
              if (a.id == id && matches(a.name))
                AlbumTile(key: ValueKey<String>(a.id), album: a),
          ],
        ];
        final List<Gallery> restGalleries =
            galleries
                .where(
                  (Gallery g) =>
                      !prefs.pinned.contains(g.id) && matches(g.name),
                )
                .toList()
              ..sort(
                (Gallery a, Gallery b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
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
        return CustomScrollView(
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
                    ),
                  for (final String n in pending)
                    EmptyAlbumTile(key: ValueKey<String>('empty:$n'), name: n),
                  for (final Album a in rest)
                    AlbumTile(key: ValueKey<String>(a.id), album: a),
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
